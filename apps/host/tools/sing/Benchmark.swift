import Foundation
import MLX
import SwiftRoFormer
import Darwin

@main
struct CadenzaSingBenchmark {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let modelPath = arguments.first else {
            print("Usage: CadenzaSingBenchmark <model-directory> [duration-seconds] [iterations]")
            exit(2)
        }
        let durationSeconds = try argument(arguments, index: 1, defaultValue: 1.0)
        let iterations = Int(try argument(arguments, index: 2, defaultValue: 3.0))
        guard durationSeconds > 0, iterations > 0 else {
            print("Duration and iterations must be positive.")
            exit(2)
        }

        let modelDirectory = URL(fileURLWithPath: modelPath, isDirectory: true)
        let configURL = modelDirectory.appendingPathComponent("config.json")
        let weightsURL = modelDirectory.appendingPathComponent("model.safetensors")
        guard FileManager.default.fileExists(atPath: configURL.path),
            FileManager.default.fileExists(atPath: weightsURL.path)
        else {
            print("The model directory must contain config.json and model.safetensors.")
            exit(2)
        }

        let loadStarted = CFAbsoluteTimeGetCurrent()
        let model = MelRoFormer(config: .kimVocal2)
        try WeightLoader.loadWeights(into: model, from: weightsURL)
        let loadMs = (CFAbsoluteTimeGetCurrent() - loadStarted) * 1_000

        let frames = Int(44_100 * durationSeconds)
        let samples = [Float](repeating: 0, count: frames * 2)
        let input = MLXArray(samples).reshaped([1, 2, frames])
        var elapsed: [Double] = []
        elapsed.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let started = CFAbsoluteTimeGetCurrent()
            let separated = model(input)
            MLX.eval(separated)
            elapsed.append((CFAbsoluteTimeGetCurrent() - started) * 1_000)
        }

        let meanMs = elapsed.reduce(0, +) / Double(elapsed.count)
        let minimumMs = elapsed.min() ?? meanMs
        let maximumMs = elapsed.max() ?? meanMs
        let realtimeFactor = durationSeconds / (meanMs / 1_000)
        print("model_directory=\(modelDirectory.path)")
        print("model_load_ms=\(format(loadMs))")
        print("audio_duration_seconds=\(format(durationSeconds))")
        print("iterations=\(iterations)")
        print("inference_mean_ms=\(format(meanMs))")
        print("inference_min_ms=\(format(minimumMs))")
        print("inference_max_ms=\(format(maximumMs))")
        print("realtime_factor=\(format(realtimeFactor))")
    }

    private static func argument(
        _ arguments: [String], index: Int, defaultValue: Double
    ) throws -> Double {
        guard let value = arguments[safe: index] else { return defaultValue }
        guard let parsed = Double(value) else {
            throw BenchmarkError.invalidArgument(value)
        }
        return parsed
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private enum BenchmarkError: LocalizedError {
        case invalidArgument(String)

        var errorDescription: String? {
            switch self {
            case .invalidArgument(let value): return "Invalid numeric argument: \(value)"
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
