import Foundation
import Testing

@testable import CadenzaHost

struct CastVideoServerTests {
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

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/cast/video.mp4")!)
        req.setValue("bytes=10-29", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 206)
        #expect(http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(http.value(forHTTPHeaderField: "Content-Range") == "bytes 10-29/128")
        #expect(data == bytes[10...29])
    }

    @Test func loadAudioCarriesWidevineCustomDataWhenProvided() throws {
        let message = CastProtocolMessages.loadAudio(
            url: "https://mvod.itunes.apple.com/widevine/master.m3u8",
            transportId: "transport-1",
            sessionId: "session-1",
            title: "Song Video",
            requestId: 7,
            contentType: "application/x-mpegurl",
            streamType: "BUFFERED",
            customData: ["licenseUrl": "https://play.itunes.apple.com/license"])

        let json = try #require(JSONSerialization.jsonObject(with: Data(message.payload.utf8)) as? [String: Any])
        let media = try #require(json["media"] as? [String: Any])
        let customData = try #require(media["customData"] as? [String: Any])
        #expect(media["contentType"] as? String == "application/x-mpegurl")
        #expect(media["streamType"] as? String == "BUFFERED")
        #expect(customData["licenseUrl"] as? String == "https://play.itunes.apple.com/license")
    }
}
