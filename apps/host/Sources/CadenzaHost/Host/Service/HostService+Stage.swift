import Foundation

// Stage receivers (a Tier-2 `/tv` browser and a Tier-3 Android TV) connect to the Web listener's `/cast/live` socket and
// read `/api/v1/cast/` media from it. They never reach the Remote command socket.
extension HostService {
    /// Wires the stage to the Host's listener, media, and playback. Called once while the Host is set up.
    func configureStage() {
        let stage = publishedState.stage
        webRemote.onStageSocket = { [weak self] socket, role in self?.openStageSocket(socket, role: role) }
        webRemote.stageMediaReply = { [weak self] request in
            guard let self else { return nil }
            return StageMediaRelay(store: self.publishedState.stageSuites)
                .reply(to: request.path, rangeHeader: request.headers["range"])
        }
        stage.presentation = { [weak self] in self?.publishedState.castPresentation ?? .auto }
        stage.lipSyncOffsetMs = { [weak self] in self?.publishedState.lipSyncOffsetMs ?? 0 }
        stage.playbackDelayMs = { [weak self] in self?.sing.playbackDelayMs ?? 0 }
        stage.mediaBase = { [weak self] in self?.stageMediaBase() }
        stage.artwork = { [weak self] url in try? await self?.artwork.data(for: url.absoluteString) ?? nil }
        stage.motion = { [weak self] album, artist in try? await self?.motion.video(album: album, artist: artist) ?? nil
        }
        stage.videoFile = { [weak self] identity in await self?.music.videoFileURL(for: identity) }
        stage.ac3Helper = { CastAC3Encoder.configuredHelperURL() }
        publishedState.stageHub.onChange = { [weak self] in self?.queue.publish() }
        publishedState.stageHub.onCommand = { [weak self] session, kind in
            self?.runStageCommand(kind: kind, receiverId: session.profile?.receiverId ?? session.id)
        }
    }

    /// The Host address that stage receivers reach. Nil when no LAN address is available.
    func stageMediaBase() -> String? {
        let host = configuration.advertisedAddress.isEmpty ? LANAddresses.all().first : configuration.advertisedAddress
        guard let host, !host.isEmpty else { return nil }
        return "http://\(host):\(configuration.webPort)"
    }

    func openStageSocket(_ socket: WebRemoteSession, role: String) {
        let hub = publishedState.stageHub
        let session = StageHub.Session(
            id: UUID().uuidString, role: role,
            send: { [weak socket] payload, binary in socket?.send(payload, binary: binary) ?? false },
            close: { [weak socket] in socket?.close() })
        hub.attach(session)
        socket.onText = { [weak self] bytes in
            self?.publishedState.stageHub.receive(Data(bytes), from: session.id)
            self?.queue.publish()
        }
        socket.onSocketClosed = { [weak self] in
            guard let self else { return }
            self.publishedState.stageHub.detach(session.id)
            self.queue.publish()
        }
    }

    /// Approves a pending stage receiver by its PIN. The PIN comes from a paired Remote or from the Host's own sheet.
    func approveStage(pin: String) throws {
        guard publishedState.stageHub.approve(pin: pin) else {
            throw CadenzaError.failure("invalid_command", "No TV is waiting with that PIN. Check the PIN on the TV.")
        }
        queue.publish()
    }

    /// Runs a playback command from a stage receiver through the same path as a Remote's command, so it is journaled and
    /// deduplicated the same way.
    func runStageCommand(kind: String, receiverId: String) {
        let frame = Frame(type: "command", commandId: UUID().uuidString, action: CommandAction(kind: kind))
        Task { @MainActor in
            _ = try? await executeCommand(frame, actor: "stage:\(receiverId)")
            queue.publishPending()
        }
    }

    /// Revokes a TV's token. Its socket closes, and it pairs again on its next connection.
    func forgetStage(receiverId: String) {
        publishedState.stageHub.forget(receiverId: receiverId)
        queue.publish()
    }

    /// Playback kinds that end Sing's current playback, so its audio chain is reset before Music changes track or position.
    static let interruptingPlaybackKinds: Set<String> = [
        "playback.pause", "playback.stop", "playback.seek", "playback.skip", "playback.previous",
    ]

    /// The transport command was sent to Music. The flush and optimistic state go out before Music answers.
    func stageTransportDispatched(kind: String, positionMs: Int64?) {
        let isPlaying = kind != "playback.pause" && kind != "playback.stop"
        let target = kind == "playback.seek" ? (positionMs ?? 0) : 0
        publishedState.stage.transportDispatched(isPlaying: isPlaying, targetPositionMs: target)
    }
}
