import AVFoundation
import CoreImage
import Foundation

// Re-encodes a motion video at 256 by 256 pixels and a fixed bitrate. Apple's rendition can be larger, so every album's
// motion reaches the Remote at the same small size, which a Bluetooth link carries within the motion deadline.
enum MotionTranscoder {
    static let side = 256
    static let bitrate = 250_000

    fileprivate static let failure = CadenzaError.failure("motion_unavailable", "Motion artwork is unavailable.")

    static func transcode(_ source: Data) async throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "source.mp4")
        let output = folder.appending(path: "motion.mp4")
        try source.write(to: input)

        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw failure }
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(readerOutput) else { throw failure }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: side,
                AVVideoHeightKey: side,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                ],
            ])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: side,
                kCVPixelBufferHeightKey as String: side,
            ])
        writer.add(writerInput)
        guard reader.startReading(), writer.startWriting() else { throw failure }
        writer.startSession(atSourceTime: .zero)

        try await copyFrames(reader: reader, output: readerOutput, input: writerInput, adaptor: adaptor)
        await finish(writer)
        guard writer.status == .completed else { throw failure }
        return try Data(contentsOf: output)
    }

    // The writer asks for frames when it can take them, so no frame is read before the writer has room for it.
    private static func copyFrames(
        reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws {
        let copy = FrameCopy(reader: reader, output: output, input: input, adaptor: adaptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            copy.run(continuation)
        }
    }

    private static func finish(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
    }
}

// Holds the AVFoundation objects of one copy. AVFoundation calls the writer's block on this copy's queue, and nothing else
// holds these objects, so the copy can cross into that block.
private final class FrameCopy: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let context = CIContext()
    private let queue = DispatchQueue(label: "cadenza.motion.transcode")

    init(
        reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) {
        self.reader = reader
        self.output = output
        self.input = input
        self.adaptor = adaptor
    }

    func run(_ continuation: CheckedContinuation<Void, Error>) {
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    if reader.status == .failed {
                        continuation.resume(throwing: reader.error ?? MotionTranscoder.failure)
                    } else {
                        continuation.resume()
                    }
                    return
                }
                guard let frame = scaled(sample),
                    adaptor.append(frame, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample))
                else {
                    input.markAsFinished()
                    reader.cancelReading()
                    continuation.resume(throwing: MotionTranscoder.failure)
                    return
                }
            }
        }
    }

    private func scaled(_ sample: CMSampleBuffer) -> CVPixelBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool else { return nil }
        var target: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target) == kCVReturnSuccess, let target else {
            return nil
        }
        let image = CIImage(cvPixelBuffer: source)
        let side = CGFloat(MotionTranscoder.side)
        let scale = CGAffineTransform(scaleX: side / image.extent.width, y: side / image.extent.height)
        context.render(image.transformed(by: scale), to: target)
        return target
    }
}
