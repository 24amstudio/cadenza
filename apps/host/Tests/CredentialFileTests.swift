import Foundation
import Testing

@testable import CadenzaHost

struct CredentialFileTests {
    private func credentialURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-credentials-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("secrets.json")
    }

    @Test func credentialsPersistWithOwnerOnlyPermissions() throws {
        let url = try credentialURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = CredentialFile(url: url)
        try file.write("remote.a", Data("first".utf8))
        try file.write("remote.a", Data("second".utf8))
        try file.write("remote.b", Data("other".utf8))

        let reopened = CredentialFile(url: url)
        #expect(try reopened.read("remote.a") == Data("second".utf8))
        #expect(try reopened.read("remote.b") == Data("other".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        try reopened.delete("remote.a")
        #expect(try reopened.read("remote.a") == nil)
        #expect(try reopened.read("remote.b") == Data("other".utf8))
    }

    @Test func damagedCredentialFileIsRefusedAndNotOverwritten() throws {
        let url = try credentialURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let damaged = Data("not json".utf8)
        try damaged.write(to: url)

        let file = CredentialFile(url: url)
        #expect(throws: CadenzaError.self) { try file.read("tls.host") }
        #expect(throws: CadenzaError.self) { try file.write("remote.a", Data("token".utf8)) }
        #expect(try Data(contentsOf: url) == damaged)
    }
}
