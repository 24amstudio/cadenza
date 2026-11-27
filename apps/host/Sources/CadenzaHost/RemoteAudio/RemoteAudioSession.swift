import Foundation

/// One Web Remote's audio socket. The first message must be a valid handshake with the Remote's paired token. After
/// that, the session takes stream configs, answers clock pings, reports sync telemetry every two seconds, and sends
/// audio frames through the stale-frame gate.
@MainActor
final class RemoteAudioSession {
    struct Handshake: Equatable {
        let clientId: String
        let baseLatencyMs: Double
        let outputLatencyMs: Double
        let userAgent: String
    }

    private struct HandshakeWire: Decodable {
        let version: Int
        let type: String
        let clientId: String
        let token: String
        let transport: String
        let sampleRate: Int
        let baseLatencyMs: Double
        let outputLatencyMs: Double
        let userAgent: String
    }

    private struct MessageType: Decodable {
        let type: String
    }

    private struct CommandWire: Decodable {
        let version: Int
        let type: String
        let action: String
    }

    static let maximumOutstandingPings = 8

    private let socket: WebRemoteSession
    weak var hub: RemoteAudioHub?
    private(set) var handshake: Handshake?
    private var clock = RemoteClockEstimator()
    private var gate = AudioFrameGate()
    private var inFlight = 0
    private var pingSequence: UInt64 = 0
    private var outstandingPingsUs: [UInt64] = []
    private var timer: Task<Void, Never>?

    var clientId: String? {
        handshake?.clientId
    }

    var isAuthenticated: Bool {
        handshake != nil
    }

    /// The jitter cushion from the clock's round-trip spread, kept between 18 and 45 ms. It starts at 28 ms.
    var jitterCushionUs: UInt64 {
        guard let spread = clock.rttSpreadUs else { return 28_000 }
        return UInt64(min(max(28_000 + spread / 2, 18_000), 45_000))
    }

    init(socket: WebRemoteSession) {
        self.socket = socket
    }

    func receive(text: Data) {
        guard isAuthenticated else {
            authenticate(text)
            return
        }
        guard let kind = try? JSONDecoder().decode(MessageType.self, from: text) else { return }
        switch kind.type {
        case "REMOTE_AUDIO_STREAM_CONFIG":
            do {
                let config = try RemoteAudioStreamConfig.decode(text)
                hub?.apply(config, from: self)
            } catch {
                hub?.reportInvalidMessage("stream setting")
            }
        case "REMOTE_AUDIO_COMMAND":
            guard let command = Self.command(from: text) else {
                hub?.reportInvalidMessage("command")
                return
            }
            hub?.command(command, from: self)
        default:
            return
        }
    }

    /// Reads a `REMOTE_AUDIO_COMMAND`. Returns nil for any other message, or for an action the Host does not know.
    private static func command(from text: Data) -> RemoteAudioCommand? {
        guard let wire = try? JSONDecoder().decode(CommandWire.self, from: text),
            wire.version == 1, wire.type == "REMOTE_AUDIO_COMMAND"
        else { return nil }
        return RemoteAudioCommand(rawValue: wire.action)
    }

    /// Sends one setup message, which is a text frame.
    func sendSetup(_ message: Data) {
        _ = socket.send(message)
    }

    func receive(binary: Data) {
        guard isAuthenticated, let pong = RemoteAudioWire.pong(binary),
            let index = outstandingPingsUs.firstIndex(of: pong.t1HostSendUs)
        else { return }
        outstandingPingsUs.remove(at: index)
        clock.add(
            t1: pong.t1HostSendUs, t2: pong.t2RemoteRecvUs, t3: pong.t3RemoteSendUs, t4: RemoteAudioClock.nowUs())
    }

    /// Sends one frame if the gate admits it. The gate counts each drop, and a stalled link tears the stream down.
    func send(_ frame: RemoteAudioWire.AudioFrame) {
        guard isAuthenticated, let data = RemoteAudioWire.encode(frame) else { return }
        let now = RemoteAudioClock.nowUs()
        if gate.admit(nowUs: now, targetPlayoutUs: frame.targetPlayoutHostUs, inFlight: inFlight) == .send {
            inFlight += 1
            let accepted = socket.send(data, binary: true, onWritten: { [weak self] in self?.inFlight -= 1 })
            if !accepted { inFlight -= 1 }
        }
        if gate.isDegraded(nowUs: now) {
            hub?.streamDegraded(from: self)
        }
    }

    /// Control frames bypass the gate, so a flush reaches the Remote even while audio is being dropped.
    func sendFlush(generation: UInt32) {
        _ = socket.send(RemoteAudioWire.flush(generation: generation), binary: true)
    }

    func close() {
        timer?.cancel()
        timer = nil
    }

    private func authenticate(_ text: Data) {
        guard let wire = try? JSONDecoder().decode(HandshakeWire.self, from: text),
            wire.version == 1, wire.type == "REMOTE_AUDIO_HANDSHAKE", wire.transport == "wifi_lan",
            wire.sampleRate == 48_000, (16...256).contains(wire.token.utf8.count),
            (1...120).contains(wire.clientId.utf8.count),
            (0...1_000).contains(wire.baseLatencyMs), (0...1_000).contains(wire.outputLatencyMs),
            wire.userAgent.utf8.count <= 512
        else {
            socket.close()
            return
        }
        let auth = DeviceAuth(remoteId: wire.clientId, token: wire.token, lastCreditSequence: 0)
        guard hub?.authenticate?(auth) == true else {
            socket.close()
            return
        }
        handshake = Handshake(
            clientId: wire.clientId, baseLatencyMs: wire.baseLatencyMs, outputLatencyMs: wire.outputLatencyMs,
            userAgent: wire.userAgent)
        startTimer()
        hub?.sessionAuthenticated(self)
    }

    private func startTimer() {
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isAuthenticated else { return }
                self.tick()
            }
        }
    }

    /// Every two seconds the session pings the Remote and, while it streams, reports its state.
    private func tick() {
        let now = RemoteAudioClock.nowUs()
        pingSequence &+= 1
        outstandingPingsUs.append(now)
        if outstandingPingsUs.count > Self.maximumOutstandingPings {
            outstandingPingsUs.removeFirst()
        }
        _ = socket.send(RemoteAudioWire.ping(sequence: pingSequence, t1HostSendUs: now), binary: true)
        if gate.isDegraded(nowUs: now) {
            hub?.streamDegraded(from: self)
        }
        hub?.sessionTimingChanged(self)
        guard let telemetry = hub?.telemetry(for: self) else { return }
        let message: [String: Any] = [
            "version": 1,
            "type": "REMOTE_AUDIO_SYNC",
            "streamMode": telemetry.streamMode.rawValue,
            "calibrationState": telemetry.calibrationState,
            "electronicOffsetMs": telemetry.electronicOffsetMs,
            "acousticOffsetMs": 0,
            "clockOffsetUs": NSNumber(value: clock.offsetUs(atHostUs: now) ?? 0),
            "clockDriftPpm": clock.driftPpm,
            "jitterBufferMs": Double(jitterCushionUs) / 1_000,
            "droppedStaleFrames60s": gate.droppedStaleFrames60s(nowUs: now),
            "linkHealthy": telemetry.linkHealthy,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            _ = socket.send(data)
        }
    }
}
