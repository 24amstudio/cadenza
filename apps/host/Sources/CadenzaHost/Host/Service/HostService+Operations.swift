import Foundation

extension HostService {
    struct VideoLyricResolution {
        var lyricSong: Song
        var cachedSegments: [VideoLyricAligner.Segment]
        var needsEnvelopeAlignment: Bool
    }

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
                    guard let identity = frame.song else {
                        throw CadenzaError.failure("invalid_command", "Invalid music video identity.")
                    }
                    let video: Song
                    if identity.source == "catalog" {
                        guard let found = await self.catalog.video(id: identity.id) else {
                            throw CadenzaError.failure("invalid_command", "Search for this music video before playing it.")
                        }
                        video = found
                    } else if identity.source == "library" {
                        video = try await self.music.resolveVideo(identity)
                    } else {
                        throw CadenzaError.failure(
                            "invalid_command", "Music video playback requires a catalog or library identity.")
                    }
                    try await self.music.playVideo(video)
                    try Task.checkCancellation()
                    await self.prepareAirPlayKaraokeIfConfigured(for: video)
                    self.network.send(
                        Frame(type: "video.started", requestId: requestId, song: identity), to: peer)
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

    func resolveLyricSource(for song: Song) async -> VideoLyricResolution {
        guard song.mediaType == .musicVideo else {
            return VideoLyricResolution(lyricSong: song, cachedSegments: [], needsEnvelopeAlignment: false)
        }
        let candidates = (try? await catalog.search("\(song.title) \(song.artist)")) ?? []
        if let fastPath = VideoStudioMatch.pick(video: song, candidates: candidates) {
            return VideoLyricResolution(lyricSong: fastPath, cachedSegments: [], needsEnvelopeAlignment: false)
        }
        if let cached = try? LyricOffsetStore(database: store.database).alignment(for: song.identity),
            let matched = candidates.first(where: { $0.id == cached.studioSongId })
                ?? VideoStudioMatch.pickBestCandidate(video: song, candidates: candidates)
        {
            return VideoLyricResolution(
                lyricSong: matched, cachedSegments: cached.segments, needsEnvelopeAlignment: false)
        }
        if let candidate = VideoStudioMatch.pickBestCandidate(video: song, candidates: candidates) {
            return VideoLyricResolution(lyricSong: candidate, cachedSegments: [], needsEnvelopeAlignment: true)
        }
        return VideoLyricResolution(lyricSong: song, cachedSegments: [], needsEnvelopeAlignment: false)
    }

    func loadDocument(for lyricSong: Song, occurrence: String) async throws -> LyricDocument {
        var lastError: Error?
        for attempt in 0..<6 {
            do {
                return try await lyrics.document(song: lyricSong, occurrence: occurrence)
            } catch let error as CadenzaError where error.code == "lyrics_unavailable" {
                lastError = error
                guard attempt < 5, music.accessibility.permitted else { break }
                try? await queue.primeLyrics(occurrence: occurrence)
                try await Task.sleep(for: .milliseconds(1_000 << min(attempt, 3)))
            }
        }
        if let lastError { throw lastError }
        throw CadenzaError.failure("lyrics_unavailable", "Lyrics are unavailable. Try again from the Lyrics pane.")
    }

    func applyVideoAlignment(
        _ document: LyricDocument, video: Song, resolution: VideoLyricResolution
    ) async -> LyricDocument {
        guard video.mediaType == .musicVideo else { return document }
        if !resolution.cachedSegments.isEmpty {
            return VideoLyricAligner.remap(document, segments: resolution.cachedSegments)
        }
        guard resolution.needsEnvelopeAlignment,
            publishedState.hostBudget <= .balanced,
            resolution.lyricSong.source == "catalog",
            let previewData = try? await catalog.previewAudioData(for: resolution.lyricSong.id),
            let studioEnvelope = try? await AudioEnvelopeDecoder.envelope(fromAudioData: previewData),
            !studioEnvelope.isEmpty
        else { return document }

        guard let captured = await captureVideoEnvelope(for: video) else { return document }
        let segments = VideoEnvelopeAlignment.piecewiseSegments(studio: studioEnvelope, captured: captured)
        guard !segments.isEmpty else { return document }
        let record = VideoAlignmentRecord(studioSongId: resolution.lyricSong.id, segments: segments)
        try? LyricOffsetStore(database: store.database).saveAlignment(record, for: video.identity, at: Date())
        return VideoLyricAligner.remap(document, segments: segments)
    }

    private func captureVideoEnvelope(for video: Song) async -> [Float]? {
        if case .transmitting = publishedState.castTransmitter.state {
            let captured = publishedState.castTransmitter.envelopeCollector.snapshot()
            return captured.count >= 100 ? captured : nil
        }
        guard !["preparing", "ready", "active"].contains(sing.session.status) else { return nil }
        let collector = VideoAudioEnvelopeCollector(maxSeconds: 30)
        let tap = CoreAudioSingRoute(muteWhenTapped: false)
        alignmentCollector = collector
        alignmentTap = tap
        defer { stopAlignmentCapture() }
        guard (try? await tap.start { buffer in collector.append(buffer: buffer) }) != nil else { return nil }
        let deadline = monotonicMs() + 4_500
        while monotonicMs() < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return nil }
            let currentId = (try? queue.snapshot().current?.song.id)
            if currentId != video.id { return nil }
        }
        let captured = collector.snapshot()
        return captured.count >= 100 ? captured : nil
    }

    func stopAlignmentCapture() {
        alignmentTap?.stop()
        alignmentTap = nil
        alignmentCollector?.reset()
        alignmentCollector = nil
    }

    func publishAirPlayKaraokeVTT(for song: Song, document: LyricDocument) {
        guard song.mediaType == .musicVideo, let sessionId = activeAirPlaySessionId else { return }
        let vtt = WebVTTKaraoke.render(
            document: document,
            userOffsetMs: document.userOffsetMs ?? 0,
            lipSyncOffsetMs: publishedState.lipSyncOffsetMs)
        airPlayKaraokeProxy.updateVTT(vtt, for: sessionId)
    }

    private func prepareAirPlayKaraokeIfConfigured(for song: Song) async {
        guard song.source == "catalog",
            let tokenData = try? store.credentials.read(AppleWebPlayback.tokenAccount),
            let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty,
            let lanHost = LANAddresses.all().first,
            let devToken = try? await catalog.currentDeveloperToken(),
            let assets = try? await AppleWebPlayback.fetchAssets(
                adamId: song.id, developerToken: devToken, mediaUserToken: token),
            let fairplay = assets.first(where: { $0.flavor.lowercased().contains("fairplay") })
                ?? assets.first
        else {
            activeAirPlaySessionId = nil
            airPlayKaraokeProxy.clear()
            return
        }
        guard (try? await airPlayKaraokeProxy.start()) != nil else { return }
        var req = URLRequest(url: fairplay.hlsURL)
        req.timeoutInterval = 8
        guard let (data, _) = try? await AppleHTTP().data(req, maximum: 131_072),
            let masterText = String(data: data, encoding: .utf8)
        else { return }
        let sessionId = song.id + "-" + String(UUID().uuidString.prefix(8)).lowercased()
        activeAirPlaySessionId = sessionId
        let vtt: String
        if let doc = lyricDocument {
            vtt = WebVTTKaraoke.render(
                document: doc,
                userOffsetMs: doc.userOffsetMs ?? 0,
                lipSyncOffsetMs: publishedState.lipSyncOffsetMs)
        } else {
            vtt = "WEBVTT\n\n"
        }
        let durationSeconds = max(1, Int((song.durationMs ?? 240_000) / 1_000))
        _ = airPlayKaraokeProxy.publish(
            sessionId: sessionId,
            originalMaster: masterText,
            baseURL: fairplay.hlsURL,
            durationSeconds: durationSeconds,
            vttText: vtt,
            lanHost: lanHost)
    }
}
