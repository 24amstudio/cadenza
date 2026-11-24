import AVFoundation
import CoreVideo
import Foundation
import Testing

@testable import CadenzaHost

struct MotionTranscoderSizeTests {
    // A short solid-colour MP4 at the Wi-Fi size, so the transcoder re-encodes a real file.
    private func sourceVideo(side: Int) async throws -> Data {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: side,
                kCVPixelBufferHeightKey as String: side,
            ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 20), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return try Data(contentsOf: url)
    }

    private func naturalSide(of data: Data) async throws -> CGSize {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await track.load(.naturalSize)
    }

    @Test func aBluetoothRenditionIs96PixelsAndSmallerThanTheWiFiRendition() async throws {
        let source = try await sourceVideo(side: 256)

        let bluetooth = try await MotionTranscoder.transcode(
            source, side: HostService.bluetoothMotionSide, bitrate: HostService.bluetoothMotionBitrate)
        let wifi = try await MotionTranscoder.transcode(source, side: MotionTranscoder.side)

        #expect(try await naturalSide(of: bluetooth) == CGSize(width: 96, height: 96))
        #expect(try await naturalSide(of: wifi) == CGSize(width: 256, height: 256))
        #expect(bluetooth.count < wifi.count)
    }
}
