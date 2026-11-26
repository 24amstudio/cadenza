import Foundation

/// Sends Music's output to the approved stage receivers that were asked to transmit. It owns the capture, chooses each
/// receiver's route, sends the init segment once per receiver and generation, and wraps every encoded unit in a frame.
@MainActor
final class StageAudioTransmitter {
    enum Failure: Error, Equatable {
        case noOutput
    }

    private let capture: SingCaptureRoute
    private let hub: StageHub
    private var encoders: StageAudioEncoders?
    private var ac3Helper: URL?
    private var format: CastTransmitChannelFormat = .transcodeAuto
    /// Set by the coordinator at the `survival` budget. Receivers then get stereo, and no receiver gets AC-3.
    var stereoOnly = false
    private var sourceChannels = 0
    private var routes: [String: StageCodecPlan.Route] = [:]
    private var initSent: Set<String> = []
    private var ac3Splitter = AC3Splitter()
    private var ac3Track: FragmentedMP4.Track?
    private var presentedSamples: [StageCodecPlan.Route: UInt64] = [:]
    private var fragmentSequence: UInt32 = 0
    private var generation: UInt32 = 0

    private(set) var isRunning = false

    init(hub: StageHub, capture: SingCaptureRoute = CoreAudioSingRoute()) {
        self.hub = hub
        self.capture = capture
    }

    /// Starts the capture for the first transmitting receiver. Calling it again only refreshes the routes.
    func start(format: CastTransmitChannelFormat, ac3Helper: URL?) async throws {
        self.format = format
        self.ac3Helper = ac3Helper
        guard !isRunning else {
            refreshRoutes()
            return
        }
        guard let captureFormat = capture.format else { throw Failure.noOutput }
        sourceChannels = captureFormat.channelCount
        let encoders = StageAudioEncoders(
            sourceChannels: sourceChannels, sampleRate: captureFormat.sampleRate, ac3Helper: ac3Helper,
            onAC3: { [weak self] data in Task { @MainActor in self?.ac3Output(data) } })
        self.encoders = encoders
        ac3Splitter = AC3Splitter()
        ac3Track = nil
        isRunning = true
        refreshRoutes()
        do {
            try await capture.start { [weak self] buffer in
                let outputs = encoders.encode(buffer.samples)
                guard !outputs.isEmpty else { return }
                Task { @MainActor in self?.deliver(outputs) }
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        capture.stop()
        encoders?.stop()
        encoders = nil
        isRunning = false
        routes = [:]
        hub.setSentRoutes([:])
        initSent = []
        ac3Track = nil
    }

    /// Recomputes each transmitting receiver's route. Call it when a receiver starts or stops transmitting.
    func refreshRoutes() {
        routes = [:]
        for session in hub.approvedSessions where session.isTransmitting {
            guard let profile = session.profile,
                let route = StageCodecPlan.route(
                    sourceChannels: sourceChannels, profile: profile, format: format,
                    ac3Encoder: ac3Helper != nil, stereoOnly: stereoOnly)
            else { continue }
            routes[session.id] = route
        }
        encoders?.setRoutes(Set(routes.values))
        hub.setSentRoutes(routes.mapValues(\.sentRoute))
    }

    /// Tells every transmitting receiver to drop what it buffered. The next frames start a new generation with a fresh
    /// init segment, because a flushed source buffer has lost its track configuration.
    func flush() {
        guard isRunning else { return }
        generation &+= 1
        initSent = []
        presentedSamples = [:]
        ac3Splitter = AC3Splitter()
        hub.broadcast(StageFrame.flush(generation: generation), binary: true)
    }

    private func ac3Output(_ data: Data) {
        for frame in ac3Splitter.append(data) {
            if ac3Track == nil, let info = AC3SyncInfo(frame) {
                ac3Track = .ac3(channels: info.channels, sampleRate: 48_000, dac3: info.dac3)
            }
            deliver([(.ac3, [frame])])
        }
    }

    private func deliver(_ outputs: [(StageCodecPlan.Route, [Data])]) {
        for (route, units) in outputs {
            for (sessionId, sessionRoute) in routes where sessionRoute == route {
                guard let session = hub.sessions[sessionId] else { continue }
                for unit in units {
                    send(route: route, unit: unit, to: session)
                }
            }
        }
    }

    private func send(route: StageCodecPlan.Route, unit: Data, to session: StageHub.Session) {
        switch route {
        case .lpcm(let channels):
            let time = presentationTime(route, samples: unit.count / (4 * channels))
            guard
                let frame = StageFrame.audio(
                    codec: .lpcmRaw, channels: channels, sampleRate: .hz48000, presentationTimeUs: time, payload: unit)
            else { return }
            _ = session.send(frame, true)
        case .aac:
            sendFragment(
                route: route, track: .aac(channels: 2, sampleRate: 48_000), codec: .aacFMP4, unit: unit, to: session)
        case .ac3:
            guard let ac3Track else { return }
            sendFragment(route: route, track: ac3Track, codec: .ac3FMP4, unit: unit, to: session)
        }
    }

    private func sendFragment(
        route: StageCodecPlan.Route, track: FragmentedMP4.Track, codec: StageFrame.Codec, unit: Data,
        to session: StageHub.Session
    ) {
        let key = "\(session.id)|\(codec.rawValue)"
        if !initSent.contains(key) {
            guard
                let initFrame = StageFrame.initSegment(
                    codec: codec, channels: track.channels, sampleRate: .hz48000,
                    payload: FragmentedMP4.initSegment(track))
            else { return }
            _ = session.send(initFrame, true)
            initSent.insert(key)
        }
        let duration = route == .ac3 ? StageAudioEncoders.ac3SamplesPerFrame : StageAudioEncoders.aacSamplesPerFrame
        let time = presentedSamples[route] ?? 0
        presentedSamples[route] = time + duration
        fragmentSequence &+= 1
        let fragment = FragmentedMP4.fragment(
            track, sequence: fragmentSequence, baseTime: time, sampleDuration: UInt32(duration), samples: [unit])
        guard
            let frame = StageFrame.audio(
                codec: codec, channels: track.channels, sampleRate: .hz48000,
                presentationTimeUs: time * 1_000_000 / 48_000, payload: fragment)
        else { return }
        _ = session.send(frame, true)
    }

    private func presentationTime(_ route: StageCodecPlan.Route, samples: Int) -> UInt64 {
        let time = presentedSamples[route] ?? 0
        presentedSamples[route] = time + UInt64(samples)
        return time * 1_000_000 / 48_000
    }
}
