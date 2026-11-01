import AVFAudio
import Foundation

struct SingAudioFormat: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: Int
}

struct SingAudioBuffer: @unchecked Sendable {
    let format: SingAudioFormat
    let frameCount: Int
    let samples: AVAudioPCMBuffer
    private let lease: SingAudioBufferLease?

    init(
        format: SingAudioFormat,
        frameCount: Int,
        samples: AVAudioPCMBuffer,
        lease: SingAudioBufferLease? = nil
    ) {
        self.format = format
        self.frameCount = frameCount
        self.samples = samples
        self.lease = lease
    }

    func release() {
        lease?.release()
    }
}

final class SingAudioBufferLease: @unchecked Sendable {
    private let lock = NSLock()
    private var returned = false
    private let onRelease: () -> Void

    init(onRelease: @escaping () -> Void) {
        self.onRelease = onRelease
    }

    func release() {
        lock.lock()
        guard !returned else {
            lock.unlock()
            return
        }
        returned = true
        lock.unlock()
        onRelease()
    }
}

enum SingAudioError: LocalizedError {
    case unavailable(String)
    case staleOccurrence
    case invalidMix

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .staleOccurrence: return "The current song changed. Prepare Sing again."
        case .invalidMix: return "Choose a vocal mix from 0 to 100 percent."
        }
    }
}

protocol SingCaptureRoute: AnyObject, Sendable {
    var format: SingAudioFormat? { get }
    var isAvailable: Bool { get }
    func start(_ receive: @escaping @Sendable (SingAudioBuffer) -> Void) async throws
    func stop()
}

protocol SingSeparator: AnyObject, Sendable {
    var backend: String { get }
    var modelRevision: String { get }
    func prepare(format: SingAudioFormat) async throws -> Int64
    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer
}

protocol SingStreamingSeparator: SingSeparator {
    func processStreaming(_ input: SingAudioBuffer, vocalPercent: Int) throws -> [SingAudioBuffer]
    func finishStreaming() throws -> [SingAudioBuffer]
}

protocol SingOutputSink: AnyObject, Sendable {
    var onFailure: (@Sendable (String) -> Void)? { get set }
    func start(format: SingAudioFormat) throws
    func enqueue(_ buffer: SingAudioBuffer)
    func stop()
}

/// Safe default until a native Core Audio tap and a validated model backend are installed.
final class UnavailableSingRoute: SingCaptureRoute, @unchecked Sendable {
    var format: SingAudioFormat? { nil }
    var isAvailable: Bool { false }

    func start(_ receive: @escaping @Sendable (SingAudioBuffer) -> Void) async throws {
        throw SingAudioError.unavailable("Audio capture is not available on this Host.")
    }

    func stop() {}
}

final class UnavailableSingSeparator: SingSeparator, @unchecked Sendable {
    let backend = "none"
    let modelRevision = "none"

    func prepare(format: SingAudioFormat) async throws -> Int64 {
        throw SingAudioError.unavailable("No Sing separation backend is installed.")
    }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer {
        throw SingAudioError.unavailable("No Sing separation backend is installed.")
    }
}

final class UnavailableSingOutput: SingOutputSink, @unchecked Sendable {
    var onFailure: (@Sendable (String) -> Void)?

    func start(format: SingAudioFormat) throws {
        throw SingAudioError.unavailable("No Sing audio output is installed.")
    }

    func enqueue(_ buffer: SingAudioBuffer) {}

    func stop() {}
}

final class SingMixState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func set(_ value: Int) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class SingCoordinator {
    private let maximumStartupLatencyMs: Int64 = 1_000
    private let route: SingCaptureRoute
    private let separator: SingSeparator
    private let output: SingOutputSink
    private let mixState = SingMixState()
    private var pipeline: SingAudioPipeline?
    private(set) var session = SingSession()
    private var occurrenceId: String?
    private var preparationGeneration = 0
    var onSessionChanged: (() -> Void)?
    var onLifecycle: ((HostLogLevel, String, String, [String: String]) -> Void)?

    var currentOccurrence: String? { occurrenceId }
    var capabilityAvailable: Bool {
        guard separator.backend != "none" else { return false }
        #if !arch(arm64)
            if separator.backend == "mlx-mel-roformer" {
                return false
            }
        #endif
        return HostBuild.profile != "production"
            || ["coreml-waveform", "mlx-mel-roformer"].contains(separator.backend)
    }

    init(
        route: SingCaptureRoute = CoreAudioSingRoute(),
        separator: SingSeparator = SingSeparatorFactory.defaultBackend(),
        output: SingOutputSink = AVAudioSingOutput()
    ) {
        self.route = route
        self.separator = separator
        self.output = output
    }

    func prepare(for occurrence: String) async {
        onLifecycle?(.info, "sing.prepare.started", "Sing preparation started", ["occurrence_id": occurrence])
        stop()
        preparationGeneration += 1
        let generation = preparationGeneration
        occurrenceId = occurrence
        session = SingSession(status: "preparing", backend: separator.backend, modelRevision: separator.modelRevision)
        mixState.set(session.vocalPercent)
        onSessionChanged?()
        guard route.isAvailable, let format = route.format else {
            fail("Audio capture is unavailable. Grant system audio access and choose a supported output.")
            return
        }
        do {
            let latency = try await separator.prepare(format: format)
            guard generation == preparationGeneration, occurrenceId == occurrence else { return }
            guard latency <= maximumStartupLatencyMs else {
                fail("The Sing model takes too long to prime for live playback.")
                return
            }
            session.latencyMs = latency
            session.status = "ready"
            onLifecycle?(
                .info,
                "sing.prepare.ready",
                "Sing preparation completed",
                ["occurrence_id": occurrence, "latency_ms": String(latency)]
            )
            onSessionChanged?()
        } catch {
            guard generation == preparationGeneration, occurrenceId == occurrence else { return }
            fail(error.localizedDescription)
        }
    }

    func enable(for occurrence: String) async throws {
        try checkOccurrence(occurrence)
        onLifecycle?(.info, "sing.enable.started", "Sing enable started", ["occurrence_id": occurrence])
        guard session.status == "ready" else {
            throw SingAudioError.unavailable(session.issue ?? "Sing is not ready.")
        }
        guard let format = route.format else {
            throw SingAudioError.unavailable("The Music output format is unavailable.")
        }
        output.onFailure = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.occurrenceId == occurrence else {
                    return
                }
                self.fail(message)
            }
        }
        var startedPipeline: SingAudioPipeline?
        do {
            try output.start(format: format)
            let route = route
            let expectedOccurrence = occurrence
            let pipeline = SingAudioPipeline(
                separator: separator,
                output: output,
                mixState: mixState,
                onFailure: { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.occurrenceId == expectedOccurrence else { return }
                        self.fail(message)
                    }
                })
            pipeline.start()
            startedPipeline = pipeline
            self.pipeline = pipeline
            try await route.start { buffer in
                pipeline.submit(buffer)
            }
            guard occurrenceId == occurrence else {
                route.stop()
                throw SingAudioError.staleOccurrence
            }
        } catch {
            onLifecycle?(.error, "sing.enable.failed", error.localizedDescription, ["occurrence_id": occurrence])
            if let startedPipeline {
                startedPipeline.stop()
                if let activePipeline = self.pipeline, activePipeline === startedPipeline {
                    self.pipeline = nil
                    output.stop()
                    output.onFailure = nil
                }
            } else {
                output.stop()
                output.onFailure = nil
            }
            session.status = "failed"
            session.issue = error.localizedDescription
            onSessionChanged?()
            throw error
        }
        session.status = "active"
        onLifecycle?(.info, "sing.enable.active", "Sing is active", ["occurrence_id": occurrence])
    }

    func disable(for occurrence: String) throws {
        try checkOccurrence(occurrence)
        stop()
    }

    func setVocalPercent(_ value: Int, for occurrence: String) throws {
        try checkOccurrence(occurrence)
        guard (0...100).contains(value) else { throw SingAudioError.invalidMix }
        guard session.status == "ready" || session.status == "active" else {
            throw SingAudioError.unavailable(session.issue ?? "Sing is not ready.")
        }
        session.vocalPercent = value
        mixState.set(value)
    }

    func stop() {
        preparationGeneration += 1
        route.stop()
        pipeline?.stop()
        pipeline = nil
        output.stop()
        output.onFailure = nil
        if session.status == "active" { session.status = "ready" }
    }

    func invalidate() {
        preparationGeneration += 1
        route.stop()
        pipeline?.stop()
        pipeline = nil
        output.stop()
        output.onFailure = nil
        occurrenceId = nil
        session = SingSession()
    }

    private func checkOccurrence(_ value: String) throws {
        guard occurrenceId == value else { throw SingAudioError.staleOccurrence }
    }

    private func fail(_ message: String) {
        onLifecycle?(.error, "sing.failed", message, ["occurrence_id": occurrenceId ?? ""])
        route.stop()
        pipeline?.stop()
        pipeline = nil
        output.stop()
        output.onFailure = nil
        session.status = "failed"
        session.issue = message
        onSessionChanged?()
    }
}
