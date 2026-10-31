import AVFAudio
import CoreML
import Foundation

/// Runs a bundled waveform-to-vocals Core ML model. The model contract is:
/// `audio` and `vocals` are Float32 tensors shaped [1, 2, frames].
final class CoreMLSingSeparator: SingStreamingSeparator, @unchecked Sendable {
    let backend = "coreml-waveform"
    let modelRevision = "coreml-1"

    private let modelURL: URL?
    private var model: MLModel?
    private var modelFrames = 352_800
    private var windowLeft: [Float] = []
    private var windowRight: [Float] = []
    private var overlapLeft: [Float] = []
    private var overlapRight: [Float] = []
    private var streamFormat: AVAudioFormat?
    private var streamSingFormat: SingAudioFormat?
    private var lastVocalPercent = 0

    init(modelURL: URL? = nil) {
        self.modelURL = modelURL
    }

    static var bundledModelURL: URL? {
        HostResources.bundle.url(
            forResource: "SingSeparator", withExtension: "mlmodelc", subdirectory: "Resources")
    }

    func prepare(format: SingAudioFormat) async throws -> Int64 {
        guard format.channelCount == 2 else {
            throw SingAudioError.unavailable("The Core ML separator requires stereo Music output.")
        }
        guard abs(format.sampleRate - 44_100) < 1 else {
            throw SingAudioError.unavailable("The Core ML separator requires a 44.1 kHz Music output.")
        }
        guard let url = modelURL ?? Self.bundledModelURL else {
            throw SingAudioError.unavailable("The Core ML Sing model is not installed on this Host.")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        guard let input = loaded.modelDescription.inputDescriptionsByName["audio"],
            input.type == .multiArray,
            let output = loaded.modelDescription.outputDescriptionsByName["vocals"],
            output.type == .multiArray
        else {
            throw SingAudioError.unavailable("The Core ML Sing model has no audio tensor interface.")
        }
        if let shape = input.multiArrayConstraint?.shape,
            let frames = shape.last?.intValue,
            frames > 0
        {
            modelFrames = frames
        }
        guard modelFrames >= 2 else {
            throw SingAudioError.unavailable("The Core ML Sing model window is too short.")
        }
        model = loaded
        resetStream()
        return Int64(max(180, modelFrames * 1_000 / 44_100))
    }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer {
        guard model != nil else {
            throw SingAudioError.unavailable("The Core ML Sing model is not prepared.")
        }
        guard input.format.channelCount == 2, (0...100).contains(vocalPercent) else {
            throw SingAudioError.unavailable("The Core ML separator received an unsupported audio buffer.")
        }
        guard let channels = input.samples.floatChannelData else {
            throw SingAudioError.unavailable("The Core ML separator received non-float audio.")
        }
        let frames = input.frameCount
        guard frames <= modelFrames else {
            throw SingAudioError.unavailable("The Core ML separator received a buffer larger than its model window.")
        }
        var left = Array(repeating: Float.zero, count: modelFrames)
        var right = Array(repeating: Float.zero, count: modelFrames)
        left.replaceSubrange(0..<frames, with: UnsafeBufferPointer(start: channels[0], count: frames))
        right.replaceSubrange(0..<frames, with: UnsafeBufferPointer(start: channels[1], count: frames))
        let stems = try infer(left: left, right: right, vocalPercent: vocalPercent)
        return try makeBuffer(
            left: Array(stems.left.prefix(frames)),
            right: Array(stems.right.prefix(frames)),
            format: input.samples.format,
            singFormat: input.format)
    }

    func processStreaming(_ input: SingAudioBuffer, vocalPercent: Int) throws -> [SingAudioBuffer] {
        guard model != nil else {
            throw SingAudioError.unavailable("The Core ML Sing model is not prepared.")
        }
        guard input.format.channelCount == 2, (0...100).contains(vocalPercent),
            let channels = input.samples.floatChannelData
        else {
            throw SingAudioError.unavailable("The Core ML separator received an unsupported audio buffer.")
        }
        if let streamFormat,
            streamFormat.sampleRate != input.samples.format.sampleRate
                || streamFormat.channelCount != input.samples.format.channelCount
        {
            throw SingAudioError.unavailable("The Core ML separator received a changing audio format.")
        }
        streamFormat = input.samples.format
        streamSingFormat = input.format
        lastVocalPercent = vocalPercent
        windowLeft.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: input.frameCount))
        windowRight.append(contentsOf: UnsafeBufferPointer(start: channels[1], count: input.frameCount))
        let step = modelFrames / 2
        var output: [SingAudioBuffer] = []
        while windowLeft.count >= modelFrames {
            let stems = try infer(
                left: Array(windowLeft.prefix(modelFrames)),
                right: Array(windowRight.prefix(modelFrames)),
                vocalPercent: vocalPercent)
            let left = blendedPrefix(stems.left, overlap: overlapLeft, count: step)
            let right = blendedPrefix(stems.right, overlap: overlapRight, count: step)
            output.append(try makeBuffer(left: left, right: right, format: input.samples.format, singFormat: input.format))
            overlapLeft = Array(stems.left.dropFirst(step))
            overlapRight = Array(stems.right.dropFirst(step))
            windowLeft = Array(windowLeft.dropFirst(step))
            windowRight = Array(windowRight.dropFirst(step))
        }
        return output
    }

    func finishStreaming() throws -> [SingAudioBuffer] {
        guard model != nil, !windowLeft.isEmpty, let format = streamFormat,
            let singFormat = streamSingFormat
        else {
            resetStream()
            return []
        }
        let residualCount = windowLeft.count
        let paddedLeft = windowLeft + Array(repeating: 0, count: max(0, modelFrames - residualCount))
        let paddedRight = windowRight + Array(repeating: 0, count: max(0, modelFrames - residualCount))
        let stems = try infer(
            left: paddedLeft, right: paddedRight, vocalPercent: lastVocalPercent)
        let count = min(modelFrames / 2, residualCount)
        let firstLeft = (0..<count).map { index in
            overlapLeft.isEmpty ? stems.left[index] : (overlapLeft[index] + stems.left[index]) * 0.5
        }
        let firstRight = (0..<count).map { index in
            overlapRight.isEmpty ? stems.right[index] : (overlapRight[index] + stems.right[index]) * 0.5
        }
        let remainingLeft = Array(stems.left[count..<residualCount])
        let remainingRight = Array(stems.right[count..<residualCount])
        let output = try makeBuffer(
            left: firstLeft + remainingLeft, right: firstRight + remainingRight,
            format: format, singFormat: singFormat)
        resetStream()
        return [output]
    }

    private func infer(left: [Float], right: [Float], vocalPercent: Int) throws -> (left: [Float], right: [Float]) {
        let audio = try MLMultiArray(shape: [1, 2, NSNumber(value: modelFrames)], dataType: .float32)
        for frame in 0..<modelFrames {
            audio[linearIndex(audio, [0, 0, frame])] = NSNumber(value: left[frame])
            audio[linearIndex(audio, [0, 1, frame])] = NSNumber(value: right[frame])
        }
        guard let model else { throw SingAudioError.unavailable("The Core ML Sing model is not prepared.") }
        let features = try MLDictionaryFeatureProvider(
            dictionary: ["audio": MLFeatureValue(multiArray: audio)])
        let prediction = try model.prediction(from: features)
        guard let vocals = prediction.featureValue(for: "vocals")?.multiArrayValue,
            vocals.count >= modelFrames * 2
        else {
            throw SingAudioError.unavailable("The Core ML Sing model returned no complete vocal tensor.")
        }
        var outputLeft = Array(repeating: Float.zero, count: modelFrames)
        var outputRight = Array(repeating: Float.zero, count: modelFrames)
        for frame in 0..<modelFrames {
            outputLeft[frame] = SingStemMixer.render(
                mix: left[frame], vocal: vocals[linearIndex(vocals, [0, 0, frame])].floatValue,
                vocalPercent: vocalPercent)
            outputRight[frame] = SingStemMixer.render(
                mix: right[frame], vocal: vocals[linearIndex(vocals, [0, 1, frame])].floatValue,
                vocalPercent: vocalPercent)
        }
        return (outputLeft, outputRight)
    }

    private func blendedPrefix(_ values: [Float], overlap: [Float], count: Int) -> [Float] {
        guard !overlap.isEmpty else { return Array(values.prefix(count)) }
        return (0..<count).map { index in (overlap[index] + values[index]) * 0.5 }
    }

    private func makeBuffer(
        left: [Float],
        right: [Float],
        format: AVAudioFormat,
        singFormat: SingAudioFormat
    ) throws -> SingAudioBuffer {
        guard left.count == right.count,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
            let channels = buffer.floatChannelData
        else { throw SingAudioError.unavailable("The Core ML output format could not be created.") }
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: left.count) }
        right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: right.count) }
        return SingAudioBuffer(format: singFormat, frameCount: left.count, samples: buffer)
    }

    private func resetStream() {
        windowLeft.removeAll(keepingCapacity: true)
        windowRight.removeAll(keepingCapacity: true)
        overlapLeft.removeAll(keepingCapacity: true)
        overlapRight.removeAll(keepingCapacity: true)
        streamFormat = nil
        streamSingFormat = nil
        lastVocalPercent = 0
    }

    private func linearIndex(_ array: MLMultiArray, _ coordinates: [Int]) -> Int {
        zip(coordinates, array.strides).reduce(0) { partial, pair in
            partial + pair.0 * pair.1.intValue
        }
    }
}
