import Foundation
import Testing

@testable import CadenzaHost

struct WebRemoteManifestTests {
    @Test func theManifestIsServedAsAWebManifestAndOtherUnlistedTypesStayRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("web-manifest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("manifest.webmanifest"))
        try Data("exe".utf8).write(to: root.appendingPathComponent("tool.exe"))
        let bundle = WebRemoteBundle(root: root)

        let manifest = try #require(bundle.file(forRequestPath: "/manifest.webmanifest"))

        #expect(manifest.contentType == "application/manifest+json; charset=utf-8")
        #expect(bundle.file(forRequestPath: "/tool.exe") == nil)
    }
}
