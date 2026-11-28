import Foundation

/// One Web Remote's audio socket. The first message must be a valid handshake with the Remote's paired token. After
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
    static let dropLogEveryTicks = 30

    private let socket: WebRemoteSession
    weak var hub: RemoteAudioHub?
    private(set) var handshake: Handshake?
    private(set) var frames: RemoteAudioFrameWriter?
    private var streamGeneration: UInt64 = 0
    private var lateCushion = LateDropCushion()
    private var playoutWindow = RemoteAudioPlayoutReport.empty
    private var lastTotalDropped = 0
    private var clock = RemoteClockEstimator()
    private var pingSequence: UInt64 = 0
    private var outstandingPingsUs: [UInt64] = []
    private var timer: Task<Void, Never>?

    var clientId: String? {
        handshake?.clientId
    }

    var isAuthenticated: Bool {
        handshake != nil
    }

    static let maximumCushionUs: UInt64 = 80_000

    var jitterCushionUs: UInt64 {
        let base: UInt64
        if let spread = clock.rttSpreadUs {
            base = UInt64(min(max(28_000 + spread / 2, 18_000), 45_000))
        } else {
            base = 28_000
        }
        return min(base + lateCushion.boostUs, Self.maximumCushionUs)
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
        case "REMOTE_AUDIO_PLAYOUT":
            guard let report = RemoteAudioPlayoutReport.decode(text) else {
                hub?.reportInvalidMessage("playout report")
                return
            }
            playoutWindow = playoutWindow.adding(report)
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

    func close() {
        timer?.cancel()
        timer = nil
        frames?.close()
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

    func beginFrames() -> RemoteAudioFrameWriter {
        frames?.close()
        streamGeneration &+= 1
        let generation = streamGeneration
        let writer = RemoteAudioFrameWriter(
            write: socket.makeBinaryWriter(),
            onDegraded: { [weak self] in Task { @MainActor in self?.streamDegraded(generation: generation) } })
        frames = writer
        return writer
    }

    func endFrames() {
        frames?.close()
        frames = nil
    }

    private func streamDegraded(generation: UInt64) {
        guard generation == streamGeneration else { return }
        hub?.streamDegraded(from: self)
    }

    private func startTimer() {
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isAuthenticated else { return }
                self.tick()
                try? await Task.sleep(for: .seconds(2))
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
        frames?.checkDegraded()
        let drops = frames?.statistics() ?? RemoteAudioFrameWriter.Statistics(droppedInFlight: 0, droppedLate: 0)
        lateCushion.observe(lateDrops: drops.droppedLate, remoteUnderrunFrames: playoutWindow.underrunFrames)
        let totalDropped = frames?.totalDroppedFrames() ?? 0
        let networkDrops = totalDropped >= lastTotalDropped ? totalDropped - lastTotalDropped : totalDropped
        lastTotalDropped = totalDropped
        hub?.observeQualityWindow(from: self, networkDrops: networkDrops, playout: playoutWindow)
        playoutWindow = .empty
        if drops.dropped > 0, pingSequence % UInt64(Self.dropLogEveryTicks) == 0 {
            hub?.log?(
                .warning, "stream.drops",
                "The Remote audio socket dropped \(drops.droppedInFlight) frames for a full socket and "
                    + "\(drops.droppedLate) frames that were late, in the last minute. "
                    + "The jitter cushion is \(jitterCushionUs / 1_000) ms.")
        }
        hub?.sessionTimingChanged(self)
        let telemetry = hub?.telemetry(for: self) ?? .idle
        let message = RemoteAudioSyncMessage.make(
            telemetry: telemetry, nowUs: now, clock: clock, jitterBufferMs: Double(jitterCushionUs) / 1_000,
            droppedStaleFrames60s: drops.dropped)
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            _ = socket.send(data)
        }
    }
}
