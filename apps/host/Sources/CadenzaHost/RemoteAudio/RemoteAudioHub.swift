import Foundation
import Observation

/// What the Host reports to the target session each two seconds.
struct RemoteAudioTelemetry: Equatable {
    let streamMode: RemoteAudioStreamMode
    let calibrationState: String
    let electronicOffsetMs: Double
    let linkHealthy: Bool
}

/// Where the room measurement stands. The raw values are the wire values in `REMOTE_AUDIO_SETUP`.
enum RemoteAudioRoomStatus: String, Sendable, Equatable {
    case notMeasured = "not_measured"
    case measuring
    case measured
    case needsMicrophone = "needs_microphone"
    case failed
}

/// The commands a Remote may send on its audio socket.
enum RemoteAudioCommand: String, Sendable, Equatable {
    case newEnvironment = "new_environment"
}

/// A paired Remote that is connected on Wi-Fi, as the Output settings list it.
struct RemoteAudioPeer: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// Owns the Wi-Fi Remote audio sockets and the one stream the Host sends. The Host owns the subwoofer setup. A Remote
/// or the Output settings change it, and the Host stores it and pushes it to every connected Remote. The stream runs
/// only while its setup is enabled and the target Remote is connected. A lost socket leaves the setup enabled, so the
/// stream resumes when the Remote returns. A degraded link turns the setup off, and Music returns to the Mac.
@MainActor
@Observable
final class RemoteAudioHub {
    /// The room measurement in progress. The microphone runs only for its two seconds.
    private struct RoomMeasurement {
        let window: RoomCalibrationWindow
        let microphone: RoomMicrophone
        let key: String
    }

    nonisolated static let calibrationRate = 48_000.0

    /// Checks a Remote's paired token against the Host's store. Set by the Host once the store exists. Until then,
    /// no handshake succeeds.
    @ObservationIgnored var authenticate: (@MainActor (DeviceAuth) -> Bool)?
    /// Records stream events in the Host log.
    @ObservationIgnored var log: (@MainActor (HostLogLevel, String, String) -> Void)?
    @ObservationIgnored var makeEngine: @MainActor () -> RemoteAudioStreamEngine = { RemoteAudioStreamEngine() }
    /// The Host's power budget. A measurement runs only at `unrestricted` or `balanced`.
    @ObservationIgnored var budget: @MainActor () -> HostOperatingBudget = { .unrestricted }
    /// The room a stream plays in: the Host's output device and the Remote's browser. Nil when either is unknown.
    @ObservationIgnored var roomKey: @MainActor (RemoteAudioSession) -> String? = { _ in nil }
    @ObservationIgnored var loadRoomOffsetUs: @MainActor (String) -> Int64? = { _ in nil }
    @ObservationIgnored var saveRoomOffsetUs: @MainActor (Int64, String) -> Void = { _, _ in }
    @ObservationIgnored var clearRoomOffsetUs: @MainActor (String) -> Void = { _ in }
    @ObservationIgnored var makeMicrophone: @MainActor () -> RoomMicrophone = { RoomMicrophone() }
    @ObservationIgnored var microphoneAuthorized: @MainActor () -> Bool = { RoomMicrophone.isAuthorized }
    /// The saved subwoofer setup. The Host reads it at launch and writes it on every change.
    @ObservationIgnored var loadSetup: @MainActor () -> RemoteAudioStreamConfig? = { nil }
    @ObservationIgnored var saveSetup: @MainActor (RemoteAudioStreamConfig) -> Void = { _ in }
    /// The name a paired Remote was given.
    @ObservationIgnored var remoteName: @MainActor (String) -> String = { _ in "Remote" }

    /// The subwoofer setup the Host owns. Nil until one is saved or a Remote sends one.
    private(set) var setup: RemoteAudioStreamConfig?
    /// The acoustic offset the current room has, in milliseconds. Nil until a measurement or a saved profile applies.
    private(set) var acousticOffsetMs: Double?
    /// True while the microphone is listening for a room measurement.
    private(set) var measuring = false
    /// True while a stream is running for the Remote.
    private(set) var streamingNow = false
    private(set) var roomStatus: RemoteAudioRoomStatus = .notMeasured

    private var sessions: [ObjectIdentifier: RemoteAudioSession] = [:]
    private var streaming: RemoteAudioSession?
    private var streamingMode: RemoteAudioStreamMode?
    private var engine: RemoteAudioStreamEngine?
    private var startTask: Task<Void, Never>?
    private var electronicOffsetMs = 0.0
    private var electronicLocked = false
    private var generation: UInt32 = 0
    private var roomKeyInUse: String?
    private var measurement: RoomMeasurement?
    /// Rooms that already tried a measurement in this run, so a failed attempt does not repeat on every connect.
    private var attemptedRooms: Set<String> = []
    private var roomFailed = false
    private var needsMicrophone = false
    /// Set by a new environment that has no stream to act on yet. The next stream drops the saved room first.
    private var replaceRoomOnStart = false

    /// Restores the saved setup. Called once while the Host is configured.
    func restoreSetup() {
        setup = loadSetup()
    }

    var connectedRemotes: [RemoteAudioPeer] {
        sessions.values.compactMap { session in
            guard let id = session.clientId else { return nil }
            return RemoteAudioPeer(id: id, name: remoteName(id))
        }
        .sorted { $0.name < $1.name }
    }

    func attach(_ socket: WebRemoteSession) {
        let session = RemoteAudioSession(socket: socket)
        session.hub = self
        sessions[ObjectIdentifier(session)] = session
        socket.onText = { [weak session] bytes in session?.receive(text: Data(bytes)) }
        socket.onBinary = { [weak session] bytes in session?.receive(binary: Data(bytes)) }
        socket.onSocketClosed = { [weak self, weak session] in
            guard let self, let session else { return }
            self.detach(session)
        }
    }

    func sessionAuthenticated(_ session: RemoteAudioSession) {
        if let message = setupMessage() {
            session.sendSetup(message)
        }
        reconcile()
    }

    /// A Remote sent a complete setup. The Host adopts it, saves it, and pushes it to every connected Remote.
    func apply(_ config: RemoteAudioStreamConfig, from session: RemoteAudioSession) {
        adoptSetup(config)
    }

    /// The Output settings changed the setup.
    func updateSetup(_ config: RemoteAudioStreamConfig) {
        adoptSetup(config)
    }

    func reportInvalidMessage(_ kind: String) {
        log?(.warning, "stream.refused", "A Remote sent a \(kind) outside its contract, so it was ignored.")
    }

    /// The target's Wi-Fi link stopped keeping up. Cadenza turns the setup off and gives Music back to the Mac. The
    /// Remote turns it on again with a new config.
    func streamDegraded(from session: RemoteAudioSession) {
        guard session === streaming else { return }
        stopStream()
        log?(
            .warning, "stream.degraded",
            "The Wi-Fi link to the Remote could not keep up, so Cadenza stopped the stream and restored Music on the Mac."
        )
        if var off = setup {
            off.enabled = false
            adoptSetup(off)
        }
    }

    /// A Remote asked for a command. The only command is a new output environment.
    func command(_ command: RemoteAudioCommand, from session: RemoteAudioSession) {
        switch command {
        case .newEnvironment:
            log?(.info, "calibration.new_environment", "A Remote asked for a new output environment.")
            startNewEnvironment()
        }
    }

    /// The Remote's state for its next telemetry message. Nil while no stream runs for that session.
    func telemetry(for session: RemoteAudioSession) -> RemoteAudioTelemetry? {
        guard session === streaming, let setup, let streamingMode else { return nil }
        let calibration: String
        switch streamingMode {
        case .pureTransferExclusive:
            calibration = "not_required"
        case .pureTransferMirror:
            calibration = electronicLocked ? "electronic_locked" : "degraded"
        case .crossoverSplit:
            if acousticOffsetMs != nil {
                calibration = "acoustic_locked"
            } else {
                calibration = electronicLocked ? "electronic_locked" : "degraded"
            }
        }
        return RemoteAudioTelemetry(
            streamMode: setup.streamMode, calibrationState: calibration, electronicOffsetMs: electronicOffsetMs,
            linkHealthy: engine != nil)
    }

    /// Called when the jitter cushion moves, so the next frames use the new offsets.
    func sessionTimingChanged(_ session: RemoteAudioSession) {
        guard session === streaming else { return }
        applyTiming()
    }

    /// Play, pause, skip, and seek drop what the Host and the Remote have buffered. The next frames start a new
    /// generation.
    func flush() {
        guard let streaming, let engine else { return }
        generation &+= 1
        engine.flush()
        streaming.sendFlush(generation: generation)
    }

    /// Starts a new output environment. The saved measurement for the current room is dropped, and the room is measured
    /// again. With no stream running, the next stream drops the saved measurement and measures.
    func startNewEnvironment() {
        replaceRoomOnStart = true
        if streamingNow, streamingMode == .crossoverSplit, let engine, measurement == nil, let key = roomKeyInUse {
            replaceRoomOnStart = false
            clearRoomOffsetUs(key)
            acousticOffsetMs = nil
            attemptedRooms.remove(key)
            roomFailed = false
            if let window = beginRoomMeasurement() {
                engine.beginCalibration(window)
            }
            applyTiming()
        }
        refreshRoomStatus()
        broadcastSetup()
    }

    private func adoptSetup(_ next: RemoteAudioStreamConfig) {
        setup = next
        saveSetup(next)
        reconcile()
        broadcastSetup()
    }

    private func detach(_ session: RemoteAudioSession) {
        session.close()
        sessions.removeValue(forKey: ObjectIdentifier(session))
        if session === streaming {
            stopStream()
            log?(.info, "stream.stopped", "The Remote's audio socket closed, and Music returned to the Mac.")
        }
        reconcile()
    }

    private func reconcile() {
        guard let setup, setup.enabled, let target = setup.targetClientId else {
            stopStream()
            return
        }
        let candidate = sessions.values.first { $0.isAuthenticated && $0.clientId == target }
        if let candidate, candidate === streaming, setup.streamMode == streamingMode {
            engine?.update(
                config: setup, remoteOffsetUs: remoteOffsetUs(candidate),
                localGoalUs: localOffsetUs(config: setup, session: candidate))
            return
        }
        stopStream()
        guard let candidate else { return }
        streaming = candidate
        streamingMode = setup.streamMode
        startTask = Task { @MainActor [weak self] in
            await self?.startStream(setup, session: candidate)
        }
    }

    private func startStream(_ config: RemoteAudioStreamConfig, session: RemoteAudioSession) async {
        let hostFrames = HostOutputLatency.defaultOutputFrames()
        electronicLocked = hostFrames != nil
        electronicOffsetMs = Self.electronicDeltaMs(session: session, hostFrames: hostFrames)
        roomKeyInUse = config.streamMode == .crossoverSplit ? roomKey(session) : nil
        if replaceRoomOnStart, let key = roomKeyInUse {
            clearRoomOffsetUs(key)
            attemptedRooms.remove(key)
        }
        replaceRoomOnStart = false
        acousticOffsetMs = roomKeyInUse.flatMap { loadRoomOffsetUs($0) }.map { Double($0) / 1_000 }
        let window = roomNeedsMeasurement() ? beginRoomMeasurement() : nil
        let engine = makeEngine()
        do {
            try await engine.start(
                config: config, remoteOffsetUs: remoteOffsetUs(session),
                localOffsetUs: localOffsetUs(config: config, session: session), calibration: window,
                deliver: { [weak session] frame in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { session?.send(frame) }
                    }
                })
        } catch {
            cancelRoomMeasurement()
            guard streaming === session else { return }
            stopStream()
            log?(
                .warning, "stream.failed",
                "Cadenza could not start the Remote audio stream: \(error.localizedDescription)")
            return
        }
        guard streaming === session, streamingMode == config.streamMode else {
            engine.stop()
            cancelRoomMeasurement()
            return
        }
        self.engine = engine
        streamingNow = true
        refreshRoomStatus()
        log?(.info, "stream.started", "Cadenza started the Remote audio stream in \(config.streamMode.rawValue) mode.")
    }

    private func stopStream() {
        startTask?.cancel()
        startTask = nil
        engine?.stop()
        engine = nil
        cancelRoomMeasurement()
        streaming = nil
        streamingMode = nil
        streamingNow = false
        electronicLocked = false
        refreshRoomStatus()
    }

    private func roomNeedsMeasurement() -> Bool {
        guard let key = roomKeyInUse else { return false }
        return acousticOffsetMs == nil && !attemptedRooms.contains(key)
    }

    /// Starts the microphone for one measurement. It runs only at an unrestricted or balanced budget, and only where
    /// microphone access was already granted in Settings. Cadenza never asks for access from here.
    private func beginRoomMeasurement() -> RoomCalibrationWindow? {
        guard let key = roomKeyInUse, [.unrestricted, .balanced].contains(budget()) else { return nil }
        guard microphoneAuthorized() else {
            needsMicrophone = true
            refreshRoomStatus()
            log?(
                .info, "calibration.skipped",
                "Room calibration needs microphone access. Allow it in Settings, then choose Set Up New Environment.")
            return nil
        }
        attemptedRooms.insert(key)
        let window = RoomCalibrationWindow(sampleRate: Self.calibrationRate) { [weak self] in
            Task { @MainActor in self?.roomWindowFilled() }
        }
        let microphone = makeMicrophone()
        do {
            try microphone.start { block in window.appendMic(block) }
        } catch {
            roomFailed = true
            log?(
                .warning, "calibration.failed",
                "The microphone could not start, so the room was not measured. The electronic alignment stays in place."
            )
            refreshRoomStatus()
            return nil
        }
        measurement = RoomMeasurement(window: window, microphone: microphone, key: key)
        measuring = true
        needsMicrophone = false
        roomFailed = false
        refreshRoomStatus()
        log?(.info, "calibration.started", "Cadenza is measuring this room for 2 seconds of music. No test tone plays.")
        return window
    }

    private func cancelRoomMeasurement() {
        measurement?.microphone.stop()
        measurement = nil
        measuring = false
    }

    /// The two seconds are full. The microphone stops, and the correlation runs off the main actor.
    private func roomWindowFilled() {
        guard let finished = measurement else { return }
        cancelRoomMeasurement()
        refreshRoomStatus()
        guard let captured = finished.window.completeWindow() else { return }
        let key = finished.key
        Task { @MainActor [weak self] in
            let deltaMs = await Task.detached(priority: .utility) {
                SilentCalibrationEngine.acousticDeltaMs(
                    mic: captured.mic, mainsReference: captured.mains, subReference: captured.sub,
                    sampleRate: Self.calibrationRate)
            }.value
            self?.finishRoomMeasurement(deltaMs, key: key)
        }
    }

    private func finishRoomMeasurement(_ deltaMs: Double?, key: String) {
        guard let deltaMs else {
            roomFailed = true
            log?(
                .warning, "calibration.no_signal",
                "The room measurement found no clear signal, so the electronic alignment stays in place.")
            refreshRoomStatus()
            return
        }
        let offsetUs = Int64((deltaMs * 1_000).rounded())
        guard abs(offsetUs) <= HostStore.maximumRoomOffsetUs else {
            roomFailed = true
            log?(
                .warning, "calibration.out_of_range", "The measured room offset is outside ±50 ms, so it was not used.")
            refreshRoomStatus()
            return
        }
        saveRoomOffsetUs(offsetUs, key)
        guard roomKeyInUse == key, streamingNow else { return }
        acousticOffsetMs = Double(offsetUs) / 1_000
        applyTiming()
        refreshRoomStatus()
        log?(
            .info, "calibration.locked",
            "The room is measured, and the sub is aligned by \(String(format: "%.1f", Double(offsetUs) / 1_000)) ms.")
    }

    private func refreshRoomStatus() {
        let next: RemoteAudioRoomStatus
        if measuring {
            next = .measuring
        } else if acousticOffsetMs != nil {
            next = .measured
        } else if roomFailed {
            next = .failed
        } else if needsMicrophone {
            next = .needsMicrophone
        } else {
            next = .notMeasured
        }
        guard next != roomStatus else { return }
        roomStatus = next
        broadcastSetup()
    }

    /// The setup as the Remotes read it: the saved values, the room status, and the measured offset.
    private func setupMessage() -> Data? {
        let current = setup
        var message: [String: Any] = [
            "version": 1,
            "type": "REMOTE_AUDIO_SETUP",
            "enabled": current?.enabled ?? false,
            "streamMode": (current?.streamMode ?? .pureTransferExclusive).rawValue,
            "crossoverHz": current?.crossoverHz ?? RemoteAudioStreamConfig.defaultCrossoverHz,
            "subGainDb": current?.subGainDb ?? 0,
            "phaseInvert": current?.phaseInvert ?? false,
            "manualDistanceOffsetMs": current?.manualDistanceOffsetMs ?? 0,
            "roomStatus": roomStatus.rawValue,
            "acousticOffsetMs": acousticOffsetMs ?? 0,
        ]
        if let target = current?.targetClientId {
            message["targetClientId"] = target
        }
        return try? JSONSerialization.data(withJSONObject: message)
    }

    private func broadcastSetup() {
        guard let message = setupMessage() else { return }
        for session in sessions.values where session.isAuthenticated {
            session.sendSetup(message)
        }
    }

    /// Pushes the current offsets to the running engine. The local output glides to its goal, and the Remote's
    /// frames keep the jitter cushion.
    private func applyTiming() {
        guard let engine, let setup, let streaming else { return }
        engine.update(
            config: setup, remoteOffsetUs: remoteOffsetUs(streaming),
            localGoalUs: localOffsetUs(config: setup, session: streaming))
    }

    /// The Remote's frames play at the jitter cushion after capture.
    private func remoteOffsetUs(_ session: RemoteAudioSession) -> UInt64 {
        UInt64(session.jitterCushionUs)
    }

    /// The Host's own output plays later by the electronic delta, the manual trim, and the room's acoustic offset.
    /// Those corrections are applied to the Host's output only, because the Remote is the reference.
    private func localOffsetUs(config: RemoteAudioStreamConfig, session: RemoteAudioSession) -> Double {
        let electronicMs = Self.electronicDeltaMs(session: session, hostFrames: HostOutputLatency.defaultOutputFrames())
        let netMs = electronicMs + config.manualDistanceOffsetMs
        let acousticUs = (acousticOffsetMs ?? 0) * 1_000
        return Double(session.jitterCushionUs) + netMs * 1_000 + acousticUs
    }

    private static func electronicDeltaMs(session: RemoteAudioSession, hostFrames: Int?) -> Double {
        guard let handshake = session.handshake, let hostFrames else { return 0 }
        return SilentCalibrationEngine.electronicDeltaMs(
            remoteBaseLatencyMs: handshake.baseLatencyMs, remoteOutputLatencyMs: handshake.outputLatencyMs,
            hostLatencyFrames: hostFrames, sampleRate: 48_000)
    }
}
