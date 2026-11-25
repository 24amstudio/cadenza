import Foundation

extension HostService {
    // Search, suggestions, song preparation, and music video playback. Each runs as one cancellable job per request.
    func operation(_ frame: Frame, peer: NetworkService.Peer) {
        guard let requestId = frame.requestId, jobs.count < 16 else {
            fail(CadenzaError.failure("busy", "Too many searches are running."), request: frame, peer: peer)
            return
        }
        let key = peer.id + requestId
        jobs[key]?.cancel()
        network.send(Frame(type: "operation.started", requestId: requestId), to: peer)
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            let startedAt = monotonicMs()
            do {
                if frame.type == "search.suggest" {
                    // Suggestions are counted rather than logged one by one: they arrive as the user types.
                    let suggestions = try await self.catalog.suggest(frame.query ?? "")
                    try Task.checkCancellation()
                    self.queue.remember(suggestions.songs)
                    var reply = Frame(type: "search.suggestions", requestId: requestId, songs: suggestions.songs)
                    reply.terms = suggestions.terms
                    self.network.send(reply, to: peer)
                    self.logger.count("search.suggest")
                } else if frame.type == "search" {
                    let songs: [Song]
                    if frame.scope == "library" {
                        songs = try await self.music.librarySearch(frame.query ?? "")
                    } else {
                        songs = try await self.catalog.search(frame.query ?? "", videos: true)
                    }
                    try Task.checkCancellation()
                    self.logger.log(
                        .info, category: "catalog", action: "search.completed", "Search returned \(songs.count) songs",
                        remoteVersion: peer.remoteVersion,
                        metadata: [
                            "scope": frame.scope ?? "catalog", "query": String((frame.query ?? "").prefix(80)),
                            "count": String(songs.count), "ms": String(monotonicMs() - startedAt),
                            "remote_id": peer.remoteId ?? "",
                        ])
                    self.queue.remember(songs)
                    self.network.send(Frame(type: "search.result", requestId: requestId, songs: songs), to: peer)
                } else if frame.type == "video.play" {
                    // The video plays in Music's own window. It is not added to Music's queue, so the queue keeps its place.
                    guard let identity = frame.song, identity.source == "catalog",
                        let video = await self.catalog.video(id: identity.id)
                    else {
                        throw CadenzaError.failure("invalid_command", "Search for this music video before playing it.")
                    }
                    try await self.music.playVideo(video)
                    try Task.checkCancellation()
                    self.network.send(Frame(type: "video.started", requestId: requestId, song: identity), to: peer)
                } else {
                    guard let song = frame.song, Wire.validate(song) else {
                        throw CadenzaError.failure("invalid_command", "Invalid song identity.")
                    }
                    try await self.queue.prepare(song, metadata: frame.songMetadata)
                    try Task.checkCancellation()
                    self.network.send(Frame(type: "song.ready", requestId: requestId, song: song), to: peer)
                }
            } catch {
                if !Task.isCancelled { self.fail(error, request: frame, peer: peer) }
            }
        }
    }

    /// The song whose lyrics a playing item uses: the studio track of a music video when one matches, otherwise the item.
    func lyricSong(for song: Song) async -> Song {
        guard song.mediaType == .musicVideo else { return song }
        let candidates = (try? await catalog.search("\(song.title) \(song.artist)")) ?? []
        return VideoStudioMatch.pick(video: song, candidates: candidates) ?? song
    }
}
