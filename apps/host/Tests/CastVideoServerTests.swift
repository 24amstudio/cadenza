import Foundation
import Testing

@testable import CadenzaHost

struct CastVideoServerTests {
    private let suiteId = "0123456789abcdef01234567"

    @Test func servesTheKaraokeSubtitlesAsWebVTTForTheSameSuite() async throws {
        let server = CastAudioStreamServer(codec: .aac)
        let port = try await server.start()
        defer { server.stop() }
        server.setSubtitles("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello\n")
        try await Task.sleep(for: .milliseconds(50))

        let url = URL(string: "http://127.0.0.1:\(port)/api/v1/cast/video/\(suiteId)/lyrics.vtt")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/vtt") == true)
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("WEBVTT"))
    }

    @Test func servesLocalVideoFileWithAcceptRangesAndPartialContent() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cadenza-cast-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let videoFile = dir.appending(path: "clip.mp4")
        let bytes = Data((0..<128).map { UInt8($0) })
        try bytes.write(to: videoFile)

        let server = CastAudioStreamServer(codec: .aac)
        let port = try await server.start()
        defer { server.stop() }
        server.setMediaAssets(videoFile: videoFile)
        try await Task.sleep(for: .milliseconds(50))

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/v1/cast/video/\(suiteId)/video.mp4")!)
        req.setValue("bytes=10-29", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 206)
        #expect(http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(http.value(forHTTPHeaderField: "Content-Range") == "bytes 10-29/128")
        #expect(data == bytes[10...29])
    }
}
