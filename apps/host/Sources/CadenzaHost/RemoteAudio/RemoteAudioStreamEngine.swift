import AVFAudio
import Foundation

/// Captures Music's output and turns each block into the Host's own output and one Remote audio frame. Music is always
/// muted by the process tap while the stream runs, so the Host plays its part itself. A Remote frame plays at the
/// jitter cushion after capture. The Host's own output plays at its alignment offset, which glides in over 500 ms. The
/// Host block is scheduled at its playout instant, so the player holds it. The DSP and the frame sequence live on one
/// serial queue. Frames leave through `deliver`.
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

    private struct State {
        var config: RemoteAudioStreamConfig
        var sampleRate: Double
        var dsp: CrossoverDspEngine?
        var local: AVAudioSingOutput?
        var remoteOffsetUs: UInt64
        var localOffset: OffsetSlew
        var blockMs: Double
        var calibration: RoomCalibrationWindow?
        var sequence: UInt32 = 0
        let deliver: Deliver
    }

    init(capture: SingCaptureRoute = CoreAudioSingRoute()) {
        self.capture = capture
    }

    /// Starts the capture. A Remote frame plays at `capture time + remoteOffsetUs`. The Host's own output plays at
    /// `capture time + localOffsetUs`, and the glide reaches that value from the first block.
    func start(
        config: RemoteAudioStreamConfig, remoteOffsetUs: UInt64, localOffsetUs: Double,
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
            remoteOffsetUs: remoteOffsetUs, localOffset: OffsetSlew(current: localOffsetUs), blockMs: blockMs,
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

    /// Drops the local player's scheduled blocks, so a transport change is heard at once.
    func flush() {
        queue.async { [self] in
            state?.local?.flush()
        }
    }

    /// Applies gain, polarity, crossover, and timing changes. The local output glides to a new goal over 500 ms. A
    /// change of stream mode needs a new engine instead.
    func update(config: RemoteAudioStreamConfig, remoteOffsetUs: UInt64, localGoalUs: Double) {
        queue.async { [self] in
            guard var current = state else { return }
            if config.crossoverHz != current.config.crossoverHz, let dsp = current.dsp {
                try? dsp.setCrossover(hz: config.crossoverHz)
            }
            current.config = config
            current.remoteOffsetUs = remoteOffsetUs
            current.localOffset.setGoal(localGoalUs, blockMs: current.blockMs)
            state = current
        }
    }

    /// Feeds the sub and mains references into a room calibration window from the next block on.
    func beginCalibration(_ window: RoomCalibrationWindow) {
        queue.async { [self] in
            state?.calibration = window
        }
    }

    private func receive(_ buffer: SingAudioBuffer) {
        let captureUs = RemoteAudioClock.nowUs()
        defer { buffer.release() }
        let count = Int(buffer.frameCount)
        guard count > 0, count <= Self.maximumBlockFrames, buffer.format.channelCount == 2,
            let channels = buffer.samples.floatChannelData
        else { return }
        // The pooled buffer is released as soon as its samples are copied, so the queue never reads it.
        let left = Array(UnsafeBufferPointer(start: channels[0], count: count))
        let right = Array(UnsafeBufferPointer(start: channels[1], count: count))
        queue.async { [self] in process(left: left, right: right, captureUs: captureUs) }
    }

    private func process(left: [Float], right: [Float], captureUs: UInt64) {
        guard var current = state else { return }
        defer { state = current }
        guard
            let blocks = RemoteAudioRouter.route(
                mode: current.config.streamMode, left: left, right: right, dsp: current.dsp,
                subGainDb: current.config.subGainDb, phaseInvert: current.config.phaseInvert)
        else { return }
        let remotePlayoutUs = captureUs &+ current.remoteOffsetUs
        if blocks.hostOutput != .silent, let local = current.local {
            let localOffset = UInt64(max(0, current.localOffset.advance().rounded()))
            let channels = blocks.hostOutput == .mono ? 1 : 2
            if let buffer = Self.pcmBuffer(blocks.host, channels: channels, sampleRate: current.sampleRate) {
                let hostTime = RemoteAudioClock.machAbsoluteTime(forPlayoutUs: captureUs &+ localOffset)
                local.enqueue(buffer, hostTime: hostTime)
            }
        }
        if blocks.hostOutput == .mono {
            current.calibration?.appendReferences(mains: blocks.remoteLeft, sub: blocks.host)
        }
        let payload = RemoteAudioRouter.interleave(blocks.remoteLeft, blocks.remoteRight).withUnsafeBufferPointer {
            RemoteAudioWire.littleEndianPayload(float: $0)
        }
        let frame = RemoteAudioWire.AudioFrame(
            flag: blocks.flag, channels: 2, bitDepth: .float32, sequenceNumber: current.sequence,
            hostCaptureTimeUs: captureUs, targetPlayoutHostUs: remotePlayoutUs, frameCount: UInt16(left.count),
            payload: payload)
        // The sequence advances for every produced frame, so a Remote sees a gap for each frame the gate drops.
        current.sequence &+= 1
        current.deliver(frame)
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
