import AVFAudio
import Foundation
import Hub
import MLX
import SwiftRoFormer

/// Apple Silicon Mel-RoFormer backend for live Sing processing.
///
/// The MIT-licensed MLX checkpoint is bundled in production archives and may
/// be downloaded into the local cache for development runs.
/// A one-second rolling window bounds steady-state processing latency; model
/// preparation and native real-time performance are measured separately.
final class MLXSingSeparator: SingStreamingSeparator, @unchecked Sendable {
    let backend = "mlx-mel-roformer"

    private static let modelRepository = "mlx-community/mel-roformer-kim-vocal-2-mlx"
    private static let modelCommit = "64cbfcb004e39430e5f584552c05949440ec39ce"
    var modelRevision: String { "\(Self.modelRepository)@\(Self.modelCommit)" }

    private let windowFrames = 44_100
    private let stepFrames = 22_050
    private var model: MelRoFormer?
    private var left: [Float] = []
    private var right: [Float] = []
    private var overlapLeft: [Float] = []
    private var overlapRight: [Float] = []
    private var streamFormat: AVAudioFormat?
    private var streamSingFormat: SingAudioFormat?
    private var lastVocalPercent = 0
    private var measuredPrimeLatencyMs: Int64?

    func prepare(format: SingAudioFormat) async throws -> Int64 {
        guard format.channelCount == 2 else {
            throw SingAudioError.unavailable("The MLX separator requires stereo Music output.")
        }
        guard format.sampleRate > 0 else {
            throw SingAudioError.unavailable("The MLX separator received an invalid Music sample rate.")
        }
        if model == nil {
            do {
                model = try await loadPinnedModel()
            } catch {
                throw SingAudioError.unavailable(
                    "The local Mel-RoFormer model could not be loaded: \(error.localizedDescription)")
            }
        }
        if measuredPrimeLatencyMs == nil {
            measuredPrimeLatencyMs = try measurePrimeLatency()
        }
        resetStream()
        return measuredPrimeLatencyMs ?? 0
    }

    private func loadPinnedModel() async throws -> MelRoFormer {
        if let bundledDirectory = bundledModelDirectory() {
            return try loadModel(from: bundledDirectory)
        }
        let hub = HubApi()
        let snapshot = try await hub.snapshot(
            from: Hub.Repo(id: Self.modelRepository), revision: Self.modelCommit,
            matching: ["model.safetensors", "config.json"])
        return try loadModel(from: snapshot)
    }

    private func loadModel(from directory: URL) throws -> MelRoFormer {
        let configURL = directory.appendingPathComponent("config.json")
        let weightsURL = directory.appendingPathComponent("model.safetensors")
        guard FileManager.default.fileExists(atPath: configURL.path),
            FileManager.default.fileExists(atPath: weightsURL.path)
        else {
            throw SingAudioError.unavailable("The pinned Sing model snapshot is incomplete.")
        }
        let configData = try Data(contentsOf: configURL)
        let manifest = try JSONDecoder().decode(ModelManifest.self, from: configData)
        guard manifest.checkpointFamily == "kim_vocal_2",
            manifest.sampleRate == 44_100,
            manifest.dim == 384,
            manifest.depth == 6,
            manifest.heads == 8,
            manifest.dimHead == 64,
            manifest.numBands == 60,
            manifest.nFFT == 2_048,
            manifest.hopLength == 441,
            manifest.maskEstimatorDepth == 2
        else {
            throw SingAudioError.unavailable("The pinned Sing model has an unsupported configuration.")
        }
        let loaded = MelRoFormer(config: .kimVocal2)
        try WeightLoader.loadWeights(into: loaded, from: weightsURL)
        return loaded
    }

    private func measurePrimeLatency() throws -> Int64 {
        let channel = [Float](repeating: 0, count: windowFrames)
        let started = CFAbsoluteTimeGetCurrent()
        _ = try infer(left: channel, right: channel)
        return Int64(max(1, ((CFAbsoluteTimeGetCurrent() - started) * 1_000).rounded()))
    }

    private func bundledModelDirectory() -> URL? {
        let roots = [HostResources.bundle.resourceURL, Bundle.main.resourceURL].compactMap { $0 }
        let candidates = roots.flatMap { root in
            [
                root.appendingPathComponent("Resources/SingModel", isDirectory: true),
                root.appendingPathComponent("SingModel", isDirectory: true),
            ]
        }
        return candidates.first { directory in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path)
                && FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent("model.safetensors").path)
        }
    }

    private struct ModelManifest: Decodable {
        let checkpointFamily: String
        let sampleRate: Double
        let dim: Int
        let depth: Int
        let heads: Int
        let dimHead: Int
        let numBands: Int
        let nFFT: Int
        let hopLength: Int
        let maskEstimatorDepth: Int

        enum CodingKeys: String, CodingKey {
            case checkpointFamily = "checkpoint_family"
            case sampleRate = "sample_rate"
            case dim
            case depth
            case heads
            case dimHead = "dim_head"
            case numBands = "num_bands"
            case nFFT = "n_fft"
            case hopLength = "hop_length"
            case maskEstimatorDepth = "mask_estimator_depth"
        }
    }

    func process(_ input: SingAudioBuffer, vocalPercent: Int) throws -> SingAudioBuffer {
        guard model != nil else {
            throw SingAudioError.unavailable("The MLX separator is not prepared.")
        }
        guard input.format.channelCount == 2, (0...100).contains(vocalPercent),
            let channels = input.samples.floatChannelData
        else {
            throw SingAudioError.unavailable("The MLX separator received an unsupported audio buffer.")
        }
        let count = input.frameCount
        let sourceLeft = Array(UnsafeBufferPointer(start: channels[0], count: count))
        let sourceRight = Array(UnsafeBufferPointer(start: channels[1], count: count))
        let sourceWindow = sourceWindowFrames(sampleRate: input.format.sampleRate)
        guard count <= sourceWindow else {
            throw SingAudioError.unavailable("The MLX separator received an oversized audio block.")
        }
        let paddedLeft = sourceLeft + Array(repeating: 0, count: sourceWindow - count)
        let paddedRight = sourceRight + Array(repeating: 0, count: sourceWindow - count)
        let vocals = try infer(
            left: resample(paddedLeft, to: windowFrames), right: resample(paddedRight, to: windowFrames))
        let sourceVocalsLeft = resample(vocals.left, to: sourceWindow)
        let sourceVocalsRight = resample(vocals.right, to: sourceWindow)
        return try makeBuffer(
            left: sourceVocalsLeft.prefix(count).enumerated().map { index, vocal in
                SingStemMixer.render(mix: sourceLeft[index], vocal: vocal, vocalPercent: vocalPercent)
            },
            right: sourceVocalsRight.prefix(count).enumerated().map { index, vocal in
                SingStemMixer.render(mix: sourceRight[index], vocal: vocal, vocalPercent: vocalPercent)
            },
            format: input.samples.format,
            singFormat: input.format)
    }

    func processStreaming(_ input: SingAudioBuffer, vocalPercent: Int) throws -> [SingAudioBuffer] {
        guard model != nil else {
            throw SingAudioError.unavailable("The MLX separator is not prepared.")
        }
        guard input.format.channelCount == 2, (0...100).contains(vocalPercent),
            let channels = input.samples.floatChannelData
        else {
            throw SingAudioError.unavailable("The MLX separator received an unsupported audio buffer.")
        }
        if let streamFormat,
            streamFormat.sampleRate != input.samples.format.sampleRate
                || streamFormat.channelCount != input.samples.format.channelCount
        {
            throw SingAudioError.unavailable("The MLX separator received a changing audio format.")
        }
        streamFormat = input.samples.format
        streamSingFormat = input.format
        lastVocalPercent = vocalPercent
        left.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: input.frameCount))
        right.append(contentsOf: UnsafeBufferPointer(start: channels[1], count: input.frameCount))

        var result: [SingAudioBuffer] = []
        let sourceWindow = sourceWindowFrames(sampleRate: input.format.sampleRate)
        let sourceStep = sourceStepFrames(sampleRate: input.format.sampleRate)
        while left.count >= sourceWindow {
            let sourceLeft = Array(left.prefix(sourceWindow))
            let sourceRight = Array(right.prefix(sourceWindow))
            let vocals = try infer(
                left: resample(sourceLeft, to: windowFrames),
                right: resample(sourceRight, to: windowFrames))
            let sourceVocalsLeft = resample(vocals.left, to: sourceWindow)
            let sourceVocalsRight = resample(vocals.right, to: sourceWindow)
            let outputLeft = mix(
                sourceVocalsLeft, source: sourceLeft, overlap: overlapLeft,
                count: sourceStep, vocalPercent: vocalPercent)
            let outputRight = mix(
                sourceVocalsRight, source: sourceRight, overlap: overlapRight,
                count: sourceStep, vocalPercent: vocalPercent)
            result.append(
                try makeBuffer(
                    left: outputLeft,
                    right: outputRight,
                    format: input.samples.format,
                    singFormat: input.format))
            overlapLeft = Array(sourceVocalsLeft.dropFirst(sourceStep))
            overlapRight = Array(sourceVocalsRight.dropFirst(sourceStep))
            left.removeFirst(sourceStep)
            right.removeFirst(sourceStep)
        }
        return result
    }

    func finishStreaming() throws -> [SingAudioBuffer] {
        guard let model, !left.isEmpty, let format = streamFormat, let singFormat = streamSingFormat else {
            resetStream()
            return []
        }
        let residualCount = left.count
        let sourceWindow = sourceWindowFrames(sampleRate: singFormat.sampleRate)
        let sourceStep = sourceStepFrames(sampleRate: singFormat.sampleRate)
        let paddedLeft = left + Array(repeating: 0, count: max(0, sourceWindow - residualCount))
        let paddedRight = right + Array(repeating: 0, count: max(0, sourceWindow - residualCount))
        var output: [SingAudioBuffer] = []
        let vocals = try infer(
            model: model, left: resample(paddedLeft, to: windowFrames),
            right: resample(paddedRight, to: windowFrames))
        let sourceVocalsLeft = resample(vocals.left, to: sourceWindow)
        let sourceVocalsRight = resample(vocals.right, to: sourceWindow)
        let firstCount = min(sourceStep, residualCount)
        let firstLeft = (0..<firstCount).map { index in
            let vocal =
                overlapLeft.isEmpty
                ? sourceVocalsLeft[index]
                : (overlapLeft[index] + sourceVocalsLeft[index]) * 0.5
            return SingStemMixer.render(
                mix: left[index], vocal: vocal, vocalPercent: lastVocalPercent)
        }
        let firstRight = (0..<firstCount).map { index in
            let vocal =
                overlapRight.isEmpty
                ? sourceVocalsRight[index]
                : (overlapRight[index] + sourceVocalsRight[index]) * 0.5
            return SingStemMixer.render(
                mix: right[index], vocal: vocal, vocalPercent: lastVocalPercent)
        }
        let remainingLeft = (firstCount..<residualCount).map { index in
            SingStemMixer.render(
                mix: left[index], vocal: sourceVocalsLeft[index], vocalPercent: lastVocalPercent)
        }
        let remainingRight = (firstCount..<residualCount).map { index in
            SingStemMixer.render(
                mix: right[index], vocal: sourceVocalsRight[index], vocalPercent: lastVocalPercent)
        }
        let finalLeft = firstLeft + remainingLeft
        let finalRight = firstRight + remainingRight
        output.append(
            try makeBuffer(
                left: finalLeft, right: finalRight, format: format, singFormat: singFormat))
        resetStream()
        return output
    }

    private func infer(left: [Float], right: [Float]) throws -> (left: [Float], right: [Float]) {
        guard let model else { throw SingAudioError.unavailable("The MLX separator is not prepared.") }
        return try infer(model: model, left: left, right: right)
    }

    private func infer(
        model: MelRoFormer, left: [Float], right: [Float]
    ) throws -> (left: [Float], right: [Float]) {
        let audio = stacked(
            [
                MLXArray(left), MLXArray(right),
            ],
            axis: 0
        ).expandedDimensions(axis: 0)
        let separated = model(audio)
        MLX.eval(separated)
        let outputLeft = separated[0, 0, 0..<left.count].asArray(Float.self)
        let outputRight = separated[0, 1, 0..<right.count].asArray(Float.self)
        return (outputLeft, outputRight)
    }

    private func mix(
        _ vocals: [Float], source: [Float], overlap: [Float], count: Int, vocalPercent: Int
    ) -> [Float] {
        return (0..<count).map { index in
            let vocal = vocals[index]
            let blended = overlap.isEmpty ? vocal : (overlap[index] + vocal) * 0.5
            return SingStemMixer.render(mix: source[index], vocal: blended, vocalPercent: vocalPercent)
        }
    }

    private func sourceWindowFrames(sampleRate: Double) -> Int {
        max(2, Int((Double(windowFrames) * sampleRate / 44_100).rounded()))
    }

    private func sourceStepFrames(sampleRate: Double) -> Int {
        max(1, Int((Double(stepFrames) * sampleRate / 44_100).rounded()))
    }

    private func resample(_ values: [Float], to count: Int) -> [Float] {
        guard values.count != count else { return values }
        guard count > 1, values.count > 1 else {
            return Array(repeating: values.first ?? 0, count: count)
        }
        let scale = Double(values.count - 1) / Double(count - 1)
        return (0..<count).map { index in
            let position = Double(index) * scale
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, values.count - 1)
            let fraction = Float(position - Double(lower))
            return values[lower] + (values[upper] - values[lower]) * fraction
        }
    }

    private func makeBuffer(
        left: [Float], right: [Float], format: AVAudioFormat, singFormat: SingAudioFormat
    ) throws -> SingAudioBuffer {
        guard left.count == right.count,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
            let channels = buffer.floatChannelData
        else { throw SingAudioError.unavailable("The MLX output format could not be created.") }
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: left.count) }
        right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: right.count) }
        return SingAudioBuffer(format: singFormat, frameCount: left.count, samples: buffer)
    }

    private func resetStream() {
        left.removeAll(keepingCapacity: true)
        right.removeAll(keepingCapacity: true)
        overlapLeft.removeAll(keepingCapacity: true)
        overlapRight.removeAll(keepingCapacity: true)
        streamFormat = nil
        streamSingFormat = nil
        lastVocalPercent = 0
    }
}
