import Foundation
import Testing

@testable import CadenzaHost

struct ByteRangeTests {
    @Test func aBoundedRangeIsClampedToTheFile() {
        #expect(ByteRange.parse("bytes=0-99", size: 1_000) == .partial(0...99))
        #expect(ByteRange.parse("bytes=900-", size: 1_000) == .partial(900...999))
        #expect(ByteRange.parse("bytes=-100", size: 1_000) == .partial(900...999))
        #expect(ByteRange.parse("bytes=990-5000", size: 1_000) == .partial(990...999))
    }

    @Test func aStartPastTheEndIsUnsatisfiable() {
        #expect(ByteRange.parse("bytes=2000-", size: 1_000) == .unsatisfiable)
    }

    @Test func multipleOrMalformedRangesFallBackToTheWholeFile() {
        #expect(ByteRange.parse("bytes=0-1,4-5", size: 1_000) == .full)
        #expect(ByteRange.parse("bytes=9-3", size: 1_000) == .full)
        #expect(ByteRange.parse("items=0-1", size: 1_000) == .full)
        #expect(ByteRange.parse(nil, size: 1_000) == .full)
    }
}

@MainActor
struct RemoteUpdateRelayTests {
    private func cachedApk(_ bytes: [UInt8]) throws -> RemoteUpdateCache.Current {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadenza-relay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Cadenza-Remote-0.3.4.apk")
        try Data(bytes).write(to: file)
        let artifact = RemoteUpdateCache.Artifact(
            version: "0.3.4", buildNumber: 12, sha256: String(repeating: "a", count: 64),
            sizeBytes: Int64(bytes.count), filename: "Cadenza-Remote-0.3.4.apk")
        return RemoteUpdateCache.Current(artifact: artifact, file: file)
    }

    private func relay(_ current: RemoteUpdateCache.Current?) -> RemoteUpdateRelay {
        RemoteUpdateRelay(
            current: { current },
            authorize: { $0.remoteId == "remote-1" && $0.token == "secret" })
    }

    private func request(_ path: String, range: String? = nil, paired: Bool = true) -> WebRemoteRequest {
        var headers: [String: String] = [:]
        if paired {
            headers["x-cadenza-remote-id"] = "remote-1"
            headers["x-cadenza-remote-token"] = "secret"
        }
        if let range { headers["range"] = range }
        return WebRemoteRequest(method: "GET", path: path, headers: headers)
    }

    @Test func aPairedRemoteReceivesOnlyTheRequestedRange() throws {
        let reply = relay(try cachedApk(Array(0..<10))).reply(
            to: request(RemoteUpdateCache.downloadPath, range: "bytes=2-4"))

        #expect(reply.status == 206)
        #expect(reply.body == [2, 3, 4])
        #expect(reply.headers.contains("Content-Range: bytes 2-4/10"))
        #expect(reply.headers.contains("X-Cadenza-SHA256: " + String(repeating: "a", count: 64)))
    }

    @Test func aRequestWithoutPairedCredentialsGetsNothing() throws {
        let reply = relay(try cachedApk(Array(0..<10))).reply(
            to: request(RemoteUpdateCache.downloadPath, paired: false))

        #expect(reply.status == 401)
        #expect(reply.body.isEmpty)
    }

    @Test func theManifestTellsTheRemoteWhereToDownloadTheApk() throws {
        let reply = relay(try cachedApk([1, 2, 3])).reply(to: request(RemoteUpdateCache.manifestPath))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.body)) as? [String: Any])

        #expect(object["version"] as? String == "0.3.4")
        #expect(object["build_number"] as? Int == 12)
        #expect(object["size_bytes"] as? Int == 3)
        #expect(object["lan_download_path"] as? String == RemoteUpdateCache.downloadPath)
    }

    @Test func noCachedApkMeansNotFound() {
        #expect(relay(nil).reply(to: request(RemoteUpdateCache.manifestPath)).status == 404)
    }
}
