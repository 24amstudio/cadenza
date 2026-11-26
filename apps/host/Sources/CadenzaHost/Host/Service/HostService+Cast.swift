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
        "cast.transmit", "cast.presentation", "video.output", "lip_sync.offset", "lyrics.offset", "stage.approve",
    ]

    private func applySetting(_ action: CommandAction) async throws {
        switch action.kind {
        case "cast.transmit": try await transmitToCast(action)
        case "cast.presentation": try setCastPresentation(action)
        case "video.output": try setVideoOutput(action)
        case "lyrics.offset": try setLyricOffset(action)
        case "stage.approve": try approveStage(pin: action.pin ?? "")
        default: try setLipSyncOffset(action)
        }
    }

    /// Stage receivers are named `stage:<receiverId>` in a `cast.transmit` command, so they never collide with Cast names.
    static let stageDevicePrefix = "stage:"

    /// A URL-loading Cast app ID. Empty means Cadenza uses its own stream and the Default Media Receiver.
    static let webLoaderAppIdKey = "experimentalCastWebLoaderAppId"

    private func transmitToStage(_ receiverId: String, start: Bool) async throws {
        guard
            let session = publishedState.stageHub.approvedSessions.first(where: { $0.profile?.receiverId == receiverId }
            )
        else {
            throw CadenzaError.failure("cast_unavailable", "That TV is not connected to this Host.")
        }
        do {
            try await publishedState.stage.setTransmitting(
                sessionId: session.id, start, format: publishedState.castTransmitFormat)
        } catch {
            throw CadenzaError.failure("cast_unavailable", "Cadenza could not start audio for the TV: \(error).")
        }
    }

    private func transmitToCast(_ action: CommandAction) async throws {
        guard let start = action.start, let name = action.device else {
            throw CadenzaError.failure("invalid_command", "Cast transmission needs a device and a start flag.")
        }
        if name.hasPrefix(Self.stageDevicePrefix) {
            try await transmitToStage(String(name.dropFirst(Self.stageDevicePrefix.count)), start: start)
            return
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
        if let loader = webLoaderConfiguration(lanHost: lanHost) {
            await publishedState.castTransmitter.start(device: device, lanHost: lanHost, webLoader: loader)
            if case .failed(_, let reason) = publishedState.castTransmitter.state {
                throw CadenzaError.failure("cast_unavailable", reason)
            }
            publishedState.setVideoOutputTarget(.castTransmitter)

            return
        }
        let current = try? queue.snapshot().current
        let currentSong = current?.song
        let lookedUpVideo: URL? =
            if let song = currentSong, song.mediaType == .musicVideo {
                await music.videoFileURL(for: song.identity)
            } else { nil }
        let route = CastRoutingCoordinator.route(
            for: .googleCast(device.display),
            content: Self.castContent(for: currentSong, localVideo: lookedUpVideo),
            presentation: publishedState.hostBudget == .survival ? .audioOnly : publishedState.castPresentation)
        let localVideo = route == .defaultReceiverVideo ? lookedUpVideo : nil
        let artworkData: Data? =
            if let artURL = currentSong?.artworkUrl, let cached = try? await artwork.data(for: artURL) {
                cached
            } else { nil }
        let motionData: Data? =
            if publishedState.hostBudget < .constrained, let song = currentSong, !song.album.isEmpty {
                try? await motion.video(album: song.album, artist: song.artist)
            } else { nil }
        await publishedState.castTransmitter.start(
            device: device, lanHost: lanHost, localVideoFile: localVideo, artwork: artworkData, motion: motionData)
        if case .failed(_, let reason) = publishedState.castTransmitter.state {
            throw CadenzaError.failure("cast_unavailable", reason)
        }
        if let currentSong, localVideo != nil, publishedState.castTransmitter.streamPort != 0 {
            publishedState.castTransmitter.updateVideoSession(castVideoSession(for: currentSong))
        }
        // Cast audio takes the karaoke display, so the Mac stops drawing the line while the Cast device is the target.
        publishedState.setVideoOutputTarget(.castTransmitter)
    }

    /// The experimental web loader, when an app ID is configured and the Host can serve the stage page.
    private func webLoaderConfiguration(lanHost: String) -> CastTransmitter.WebLoader? {
        let appId =
            (UserDefaults.standard.string(forKey: Self.webLoaderAppIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appId.isEmpty else { return nil }
        let base = stageMediaBase() ?? "http://\(lanHost):\(configuration.webPort)"
        return CastTransmitter.WebLoader(appId: appId, url: "\(base)/tv")
    }

    /// The video session for a local music video: its suite ID, its karaoke WebVTT, and the saved offsets.
    func castVideoSession(for song: Song) -> CastTransmitter.VideoSessionMetadata {
        let document =
            lyricDocument?.occurrenceId == (try? queue.snapshot().current?.occurrenceId) ? lyricDocument : nil
        let subtitles = WebVTTKaraoke.render(
            document: document
                ?? LyricDocument(
                    occurrenceId: "", revision: "", language: nil, translationSource: "", lines: []),
            userOffsetMs: document?.userOffsetMs ?? 0, lipSyncOffsetMs: publishedState.lipSyncOffsetMs)
        return CastTransmitter.VideoSessionMetadata(
            title: song.title, artist: song.artist, suiteId: StageTrackSuite.suiteId(for: song.identity),
            subtitles: subtitles, lipSyncOffsetMs: publishedState.lipSyncOffsetMs)
    }

    /// A library music video with a DRM-free file on disk is local. Any other music video is a FairPlay catalog video.
    static func castContent(for song: Song?, localVideo: URL?) -> CastRoutingCoordinator.Content {
        guard let song, song.mediaType == .musicVideo else { return .song }
        return localVideo == nil ? .protectedMusicVideo : .localMusicVideo
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
