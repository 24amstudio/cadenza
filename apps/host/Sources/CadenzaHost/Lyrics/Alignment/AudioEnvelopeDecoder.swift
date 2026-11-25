import AVFoundation
import Foundation

/// Decodes a studio track's public AAC preview (.m4a) into a 100 Hz mono RMS loudness envelope off the main actor.
enum AudioEnvelopeDecoder {
    static let targetSampleRate: Double = 16_000
    static let previewSizeLimit = 4 * 1_048_576

    static func envelope(fromAudioData data: Data) async throws -> [Float] {
        try await Task.detached(priority: .utility) {
            let tempDir = FileManager.default.temporaryDirectory.appending(
                path: "cadenza-env-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            let fileURL = tempDir.appending(path: "preview.m4a")
            try data.write(to: fileURL)
            return try await decodeFile(at: fileURL)
        }.value
    }

    static func decodeFile(at url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CadenzaError.failure("alignment_unavailable", "Preview audio track is missing.")
        }
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        guard reader.canAdd(output) else {
            throw CadenzaError.failure("alignment_unavailable", "Cannot decode preview audio.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw CadenzaError.failure("alignment_unavailable", "Failed to start decoding preview audio.")
        }
        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer(),
            let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        {
            let byteLength = CMBlockBufferGetDataLength(blockBuffer)
            let floatCount = byteLength / MemoryLayout<Float>.size
            guard floatCount > 0 else { continue }
            var chunk = [Float](repeating: 0, count: floatCount)
            chunk.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress {
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteLength, destination: base)
                }
            }
            samples.append(contentsOf: chunk)
        }
        return VideoEnvelopeAlignment.envelope(samples: samples, sampleRate: targetSampleRate)
    }
}
