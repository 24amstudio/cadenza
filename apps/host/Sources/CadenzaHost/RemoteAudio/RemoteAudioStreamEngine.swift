import AVFAudio
import Foundation

/// Captures Music's output and turns each block into the Host's own output and one Remote audio frame. Music is always
/// muted by the process tap while the stream runs, so the Host plays its part itself. A Remote frame plays at the
final class RemoteAudioStreamEngine: @unchecked Sendable {
    typealias Deliver = @Sendable (RemoteAudioWire.AudioFrame) -> Void

    enum Failure: Error, Equatable {
        case unsupportedOutput
    }

    /// Music's capture is stereo on every Host this build targets. A block larger than this is skipped, not split.
    static let maximumBlockFrames = 4_096
    /// The block size the capture delivers in practice. The glide is counted in these blocks.
    static let nominalBlockFrames = 512

    private let capture: SingCaptureRoute
    private let queue = DispatchQueue(label: "app.cadenza.host.remote-audio.engine")
    private var state: State?
    private(set) var mode: RemoteAudioStreamMode?
    private let loadLock = NSLock()
    private var busyNanoseconds: UInt64 = 0
    private var loadWindowStart = DispatchTime.now().uptimeNanoseconds

    private struct State {
        var config: RemoteAudioStreamConfig
        var sampleRate: Double
        var dsp: CrossoverDspEngine?
        var local: AVAudioSingOutput?
        var remoteOffset: OffsetSlew
        var localOffset: OffsetSlew
        var calibration: RoomCalibrationWindow?
        var sequence: UInt32 = 0
        var flushedAtUs: UInt64 = 0
        var quality: RemoteAudioQuality = .lossless
        let deliver: Deliver
    }

    init(capture: SingCaptureRoute = CoreAudioSingRoute()) {
        self.capture = capture
    }

    /// Starts the capture. A Remote frame plays at `capture time + remoteOffsetUs`. The Host's own output plays at
    /// `capture time + localOffsetUs`, and the glide reaches that value from the first block.
    func start(
        config: RemoteAudioStreamConfig, remoteOffsetUs: Double, localOffsetUs: Double,
        calibration: RoomCalibrationWindow?, deliver: @escaping Deliver
    ) async throws {
        guard let format = capture.format, format.channelCount == 2 else { throw Failure.unsupportedOutput }
        let dsp =
            config.streamMode == .crossoverSplit
            ? try CrossoverDspEngine(
                sampleRate: format.sampleRate, crossoverHz: config.crossoverHz, maximumFrames: Self.maximumBlockFrames)
            : nil
        var local: AVAudioSingOutput?
        if config.streamMode != .pureTransferExclusive {
            let output = AVAudioSingOutput()
            let channels = config.streamMode == .crossoverSplit ? 1 : 2
            try output.start(format: SingAudioFormat(sampleRate: format.sampleRate, channelCount: channels))
            local = output
        }
        let blockMs = Double(Self.nominalBlockFrames) / format.sampleRate * 1_000
        let next = State(
            config: config, sampleRate: format.sampleRate, dsp: dsp, local: local,
            remoteOffset: OffsetSlew(current: remoteOffsetUs, sampleRate: format.sampleRate, blockMs: blockMs),
            localOffset: OffsetSlew(current: localOffsetUs, sampleRate: format.sampleRate, blockMs: blockMs),
            calibration: calibration, deliver: deliver)
        queue.sync { state = next }
        self.mode = config.streamMode
        do {
            try await capture.start { [weak self] buffer in self?.receive(buffer) }
        } catch {
            stop()
            throw error
        }
    }

    /// Stops the capture at once, so Music is unmuted on return. The local output is released on the queue.
    func stop() {
        capture.stop()
        mode = nil
        queue.async { [self] in
            state?.local?.stop()
            state = nil
        }
    }

    func flush(onFlushed: @escaping @Sendable () -> Void) {
        let requestedUs = RemoteAudioClock.nowUs()
        queue.async { [self] in
            state?.local?.flush()
            state?.flushedAtUs = requestedUs
            onFlushed()
        }
    }

    func update(config: RemoteAudioStreamConfig, remoteOffsetUs: Double, localGoalUs: Double) {
        queue.async { [self] in
            guard var current = state else { return }
            if config.crossoverHz != current.config.crossoverHz, let dsp = current.dsp {
                try? dsp.setCrossover(hz: config.crossoverHz)
            }
            current.config = config
            current.remoteOffset.setGoal(remoteOffsetUs)
            current.localOffset.setGoal(localGoalUs)
            state = current
        }
    }

    func setQuality(_ quality: RemoteAudioQuality) {
        queue.async { [self] in
            state?.quality = quality
        }
    }

    func takeBusyFraction() -> Double {
        let now = DispatchTime.now().uptimeNanoseconds
        return loadLock.withLock {
            let elapsed = now &- loadWindowStart
            let busy = busyNanoseconds
            busyNanoseconds = 0
            loadWindowStart = now
            guard elapsed > 0 else { return 0 }
            return min(1, Double(busy) / Double(elapsed))
        }
    }

    /// Feeds the sub and mains references into a room calibration window from the next block on.
    func beginCalibration(_ window: RoomCalibrationWindow) {
        queue.async { [self] in
            state?.calibration = window
        }
    }

    private func receive(_ buffer: SingAudioBuffer) {
        defer { buffer.release() }
        let count = Int(buffer.frameCount)
        guard count > 0, count <= Self.maximumBlockFrames, buffer.format.channelCount == 2,
            let channels = buffer.samples.floatChannelData
        else { return }
        let span = Self.blockSpanUs(buffer, frames: count)
        // The pooled buffer is released as soon as its samples are copied, so the queue never reads it.
        let left = Array(UnsafeBufferPointer(start: channels[0], count: count))
        let right = Array(UnsafeBufferPointer(start: channels[1], count: count))
        queue.async { [self] in process(left: left, right: right, captureUs: span.end, startUs: span.start) }
    }

    private func process(left: [Float], right: [Float], captureUs: UInt64, startUs: UInt64) {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { recordBusy(since: started) }
        guard var current = state else { return }
        defer { state = current }
        guard
            let blocks = RemoteAudioRouter.route(
                mode: current.config.streamMode, left: left, right: right, dsp: current.dsp,
                subGainDb: current.config.subGainDb, phaseInvert: current.config.phaseInvert),
            startUs >= current.flushedAtUs
        else { return }
        let count = left.count
        let remoteUs = current.remoteOffset.advance()
        let remoteFrames = Self.stretchedFrames(
            count, fromUs: remoteUs, toUs: current.remoteOffset.peekNext(), sampleRate: current.sampleRate)
        let localUs = current.localOffset.advance()
        if blocks.hostOutput != .silent, let local = current.local {
            let channels = blocks.hostOutput == .mono ? 1 : 2
            let localFrames = Self.stretchedFrames(
                count, fromUs: localUs, toUs: current.localOffset.peekNext(), sampleRate: current.sampleRate)
            let host = BlockStretch.resample(blocks.host, channels: channels, toFrames: localFrames)
            if let buffer = Self.pcmBuffer(host, channels: channels, sampleRate: current.sampleRate) {
                let hostTime = RemoteAudioClock.machAbsoluteTime(forPlayoutUs: captureUs &+ Self.offsetUs(localUs))
                local.enqueue(buffer, hostTime: hostTime)
            }
        }
        if blocks.hostOutput == .mono {
            current.calibration?.appendReferences(mains: blocks.remoteLeft, sub: blocks.host)
        }
        let tier = current.quality
        let remoteSamples = RemoteAudioRouter.interleave(blocks.remoteLeft, blocks.remoteRight)
        let stretched = BlockStretch.resample(remoteSamples, channels: Int(tier.channels), toFrames: remoteFrames)
        let payload =
            tier.bitDepth == .int24
            ? RemoteAudioPCM.littleEndian24(stretched) : RemoteAudioPCM.littleEndian16(stretched)
        let frame = RemoteAudioWire.AudioFrame(
            flag: blocks.flag, channels: tier.channels, bitDepth: tier.bitDepth, sequenceNumber: current.sequence,
            hostCaptureTimeUs: captureUs, targetPlayoutHostUs: captureUs &+ Self.offsetUs(remoteUs),
            frameCount: UInt16(remoteFrames), payload: payload)
        // The sequence advances for every produced frame, so a Remote sees a gap for each frame the gate drops.
        current.sequence &+= 1
        current.deliver(frame)
    }

    /// by when the consumer drains it, so consecutive blocks stay one block apart however late they are read.
    private static func blockSpanUs(_ buffer: SingAudioBuffer, frames: Int) -> (start: UInt64, end: UInt64) {
        let durationUs = UInt64(Double(frames) / buffer.format.sampleRate * 1_000_000)
        guard buffer.hostTime != 0 else {
            let now = RemoteAudioClock.nowUs()
            return (now &- durationUs, now)
        }
        let start = RemoteAudioClock.continuousUs(forHostTime: buffer.hostTime)
        return (start, start &+ durationUs)
    }

    private func recordBusy(since started: UInt64) {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- started
        loadLock.withLock { busyNanoseconds &+= elapsed }
    }

    private static func stretchedFrames(_ frames: Int, fromUs: Double, toUs: Double, sampleRate: Double) -> Int {
        max(1, frames + Int(((toUs - fromUs) * sampleRate / 1_000_000).rounded()))
    }

    private static func offsetUs(_ offset: Double) -> UInt64 {
        UInt64(max(0, offset.rounded()))
    }

    /// Builds the non-interleaved Float32 buffer that `AVAudioSingOutput` schedules. Stereo input is interleaved.
    private static func pcmBuffer(_ samples: [Float], channels: Int, sampleRate: Double) -> SingAudioBuffer? {
        let frames = samples.count / channels
        guard frames > 0,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels), interleaved: false),
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
            let data = pcm.floatChannelData
        else { return nil }
        pcm.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            for channel in 0..<channels {
                data[channel][frame] = samples[frame * channels + channel]
            }
        }
        return SingAudioBuffer(
            format: SingAudioFormat(sampleRate: sampleRate, channelCount: channels), frameCount: frames, samples: pcm)
    }
}
