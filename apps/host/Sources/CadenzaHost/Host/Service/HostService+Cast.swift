import Foundation

extension HostService {
    /// Commands other than Sing. Cast and karaoke settings are handled here, and every other command goes to the queue.
    func executeOtherCommand(_ frame: Frame, actor: String) async throws -> Frame {
        guard let action = frame.action, Self.settingKinds.contains(action.kind) else {
            return try await queue.execute(frame, actor: actor)
        }
        if let previous = try queue.journal.previous(frame, actor: actor) { return previous }
        try queue.journal.prepare(frame, actor: actor, plan: nil)
        do {
            try await applySetting(action)
            try queue.journal.dispatched(frame, actor: actor)
            let result = try queue.journal.result(frame, outcome: "applied")
            try queue.journal.finish(frame, actor: actor, result: result)
            queue.publish()
            return result
        } catch {
            let code = (error as? CadenzaError)?.code ?? "cast_unavailable"
            let result = try queue.journal.result(
                frame, outcome: "rejected", code: code, message: error.localizedDescription)
            try queue.journal.finish(frame, actor: actor, result: result)
            queue.publish()
            return result
        }
    }

    static let settingKinds: Set<String> = [
        "cast.transmit", "cast.presentation", "video.output", "lip_sync.offset", "lyrics.offset",
    ]

    private func applySetting(_ action: CommandAction) async throws {
        switch action.kind {
        case "cast.transmit": try await transmitToCast(action)
        case "cast.presentation": try setCastPresentation(action)
        case "video.output": try setVideoOutput(action)
        case "lyrics.offset": try setLyricOffset(action)
        default: try setLipSyncOffset(action)
        }
    }

    private func transmitToCast(_ action: CommandAction) async throws {
        guard let start = action.start, let name = action.device else {
            throw CadenzaError.failure("invalid_command", "Cast transmission needs a device and a start flag.")
        }
        guard start else {
            publishedState.castTransmitter.stop()

            return
        }
        guard let device = publishedState.castDiscovery.devices.first(where: { $0.name == name }) else {
            throw CadenzaError.failure("cast_unavailable", "That Cast device is not on this network.")
        }
        guard let lanHost = LANAddresses.all().first else {
            throw CadenzaError.failure("cast_unavailable", "This Host has no LAN address for Cast to reach.")
        }
        let current = try? queue.snapshot().current
        let currentSong = current?.song
        let artworkData: Data? =
            if let artURL = currentSong?.artworkUrl, let cached = try? await artwork.data(for: artURL) {
                cached
            } else { nil }
        let motionData: Data? =
            if publishedState.hostBudget < .constrained, let song = currentSong, !song.album.isEmpty {
                try? await motion.video(album: song.album, artist: song.artist)
            } else { nil }
        let localVideo =
            currentSong?.mediaType == .musicVideo && currentSong?.source == "library"
            ? await music.videoFileURL(for: currentSong!.identity) : nil
        await publishedState.castTransmitter.start(
            device: device, lanHost: lanHost, localVideoFile: localVideo, artwork: artworkData, motion: motionData)
        if case .failed(_, let reason) = publishedState.castTransmitter.state {
            throw CadenzaError.failure("cast_unavailable", reason)
        }
        if let currentSong, publishedState.castTransmitter.streamPort != 0 {
            let route = await CastVideoSource.resolve(
                song: currentSong,
                catalog: catalog,
                music: music,
                credentials: store.credentials,
                lanHost: lanHost,
                streamPort: publishedState.castTransmitter.streamPort,
                hasArtwork: artworkData != nil,
                hasMotion: motionData != nil)
            publishedState.castTransmitter.updateVideoSession(
                CastTransmitter.VideoSessionMetadata(
                    title: currentSong.title,
                    artist: currentSong.artist,
                    route: route,
                    lipSyncOffsetMs: publishedState.lipSyncOffsetMs))
        }
        // Cast audio takes the karaoke display, so the Mac stops drawing the line while the Cast device is the target.
        publishedState.setVideoOutputTarget(.castTransmitter)
    }

    private func setVideoOutput(_ action: CommandAction) throws {
        guard let raw = action.videoOutput, let target = VideoOutputTarget(rawValue: raw) else {
            throw CadenzaError.failure("invalid_command", "Choose the Mac or a Cast device for the lyrics.")
        }
        publishedState.setVideoOutputTarget(target)
    }

    private func setCastPresentation(_ action: CommandAction) throws {
        guard let wire = action.presentation,
            let mode = CastPresentationMode.allCases.first(where: { $0.wireName == wire })
        else {
            throw CadenzaError.failure("invalid_command", "Choose Auto, Audio Only, or Full Suite for Cast.")
        }
        publishedState.setCastPresentation(mode)
    }

    private func setLyricOffset(_ action: CommandAction) throws {
        guard let identity = action.song, let offset = action.userOffsetMs, (-5000...5000).contains(offset) else {
            throw CadenzaError.failure("invalid_command", "The lyric offset must be between -5 and 5 seconds.")
        }
        try LyricOffsetStore(database: store.database).save(Int(offset), for: identity, at: Date())
        // The lyric document in use is updated too, so Remotes stay synchronized with the saved nudge.
        if let current = try? queue.snapshot().current, current.song.identity == identity,
            var updated = lyricDocument, updated.occurrenceId == current.occurrenceId
        {
            updated.userOffsetMs = Int(offset)
            lyricDocument = updated
            publishAirPlayKaraokeVTT(for: current.song, document: updated)
            network.broadcast(Frame(type: "lyrics", lyrics: updated))
        }
    }

    /// The lyric document with the nudge saved for its track, so Remotes start from it.
    func withUserOffset(_ document: LyricDocument, for song: Song) -> LyricDocument {
        var stored = document
        stored.userOffsetMs = try? LyricOffsetStore(database: store.database).offset(for: song.identity)
        return stored
    }

    private func setLipSyncOffset(_ action: CommandAction) throws {
        guard let offset = action.lipSyncOffsetMs, (-500...500).contains(offset) else {
            throw CadenzaError.failure("invalid_command", "The lip-sync offset must be between -500 and 500 ms.")
        }
        publishedState.setLipSyncOffset(Int(offset))
        if let current = try? queue.snapshot().current, let doc = lyricDocument,
            doc.occurrenceId == current.occurrenceId
        {
            publishAirPlayKaraokeVTT(for: current.song, document: doc)
        }
    }
}
