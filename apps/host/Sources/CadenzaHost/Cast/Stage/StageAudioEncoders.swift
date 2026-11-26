import AVFAudio
import Foundation

/// Encodes captured Music audio for each stage route. It runs on the capture thread and does no actor work. Each
/// route's encoder runs once, and the routes that are needed are set from the main actor under a lock.
final class StageAudioEncoders: @unchecked Sendable {
    static let aacSamplesPerFrame: UInt64 = 1_024
    static let ac3SamplesPerFrame: UInt64 = 1_536

    private let lock = NSLock()
    private var routes: Set<StageCodecPlan.Route> = []
    private let sourceChannels: Int
    private let sampleRate: Double
    private var aac: CastAACEncoder?
    private var ac3: CastAC3Encoder?
    private let ac3Helper: URL?
    private let onAC3: @Sendable (Data) -> Void

    init(sourceChannels: Int, sampleRate: Double, ac3Helper: URL?, onAC3: @escaping @Sendable (Data) -> Void) {
        self.sourceChannels = sourceChannels
        self.sampleRate = sampleRate
        self.ac3Helper = ac3Helper
        self.onAC3 = onAC3
    }

    func setRoutes(_ newRoutes: Set<StageCodecPlan.Route>) {
        lock.withLock { routes = newRoutes }
    }

    /// The encoded output for every active route. AAC returns raw access units, LPCM returns interleaved float32 PCM, and
    /// AC-3 is written to the helper, whose output arrives through `onAC3`.
    func encode(_ buffer: AVAudioPCMBuffer) -> [(StageCodecPlan.Route, [Data])] {
        let active = lock.withLock { routes }
        var output: [(StageCodecPlan.Route, [Data])] = []
        for route in active.sorted(by: Self.order) {
            switch route {
            case .lpcm(let channels):
                if let pcm = Self.interleaved(buffer, toChannels: channels, sourceChannels: sourceChannels) {
                    output.append((route, [pcm]))
                }
            case .aac:
                if let stereo = Self.stereo(buffer, sourceChannels: sourceChannels) {
                    output.append((route, aacFrames(stereo)))
                }
            case .ac3:
                if let six = Self.sixChannel(buffer, sourceChannels: sourceChannels) { ac3Encoder()?.encode(six) }
            }
        }
        return output
    }

    func stop() {
        ac3?.stop()
        ac3 = nil
        aac = nil
    }

    private func aacFrames(_ buffer: AVAudioPCMBuffer) -> [Data] {
        if aac == nil {
            aac = CastAACEncoder(sampleRate: sampleRate, channels: 2, inputFormat: buffer.format)
        }
        // ADTS headers are seven bytes with no CRC. Stage fragments carry only the raw access units.
        return (aac?.encode(buffer) ?? []).map { Data($0.dropFirst(7)) }
    }

    private func ac3Encoder() -> CastAC3Encoder? {
        if ac3 == nil, let ac3Helper {
            ac3 = CastAC3Encoder(helper: ac3Helper, sampleRate: sampleRate, onOutput: onAC3)
        }
        return ac3
    }

    private static func order(_ lhs: StageCodecPlan.Route, _ rhs: StageCodecPlan.Route) -> Bool {
        func rank(_ route: StageCodecPlan.Route) -> Int {
            switch route {
            case .lpcm: 0
            case .aac: 1
            case .ac3: 2
            }
        }
        return rank(lhs) < rank(rhs)
    }

    // MARK: Channel layout

    /// A stereo buffer from any supported source, folded from 5.1 and above when needed.
    static func stereo(_ buffer: AVAudioPCMBuffer, sourceChannels: Int) -> AVAudioPCMBuffer? {
        if sourceChannels == 2 { return buffer }
        guard let six = sixChannelInterleaved(buffer, sourceChannels: sourceChannels),
            let folded = try? SurroundDownmixer.stereo(fromFiveOne: six)
        else { return nil }
        return pcmBuffer(fromInterleaved: folded, channels: 2, sampleRate: buffer.format.sampleRate)
    }

    static func sixChannel(_ buffer: AVAudioPCMBuffer, sourceChannels: Int) -> AVAudioPCMBuffer? {
        if sourceChannels == 6 { return buffer }
        guard let six = sixChannelInterleaved(buffer, sourceChannels: sourceChannels) else { return nil }
        return pcmBuffer(fromInterleaved: six, channels: 6, sampleRate: buffer.format.sampleRate)
    }

    static func interleaved(_ buffer: AVAudioPCMBuffer, toChannels channels: Int, sourceChannels: Int) -> Data? {
        let samples: [Float]?
        switch channels {
        case sourceChannels: samples = interleave(buffer)
        case 6: samples = sixChannelInterleaved(buffer, sourceChannels: sourceChannels)
        case 2:
            samples = sixChannelInterleaved(buffer, sourceChannels: sourceChannels).flatMap {
                try? SurroundDownmixer.stereo(fromFiveOne: $0)
            }
        default: samples = nil
        }
        return samples.map { $0.withUnsafeBufferPointer { Data(buffer: $0) } }
    }

    private static func sixChannelInterleaved(_ buffer: AVAudioPCMBuffer, sourceChannels: Int) -> [Float]? {
        guard let samples = interleave(buffer) else { return nil }
        return try? SurroundDownmixer.downmixed(samples, channels: sourceChannels)
    }

    /// Non-interleaved float channels read as interleaved frames, in channel order.
    static func interleave(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: frames * channels)
        for channel in 0..<channels {
            let source = channelData[channel]
            for frame in 0..<frames { samples[frame * channels + channel] = source[frame] }
        }
        return samples
    }

    static func pcmBuffer(fromInterleaved samples: [Float], channels: Int, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frames = samples.count / channels
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
            let channelData = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channels {
            for frame in 0..<frames { channelData[channel][frame] = samples[frame * channels + channel] }
        }
        return buffer
    }
}
