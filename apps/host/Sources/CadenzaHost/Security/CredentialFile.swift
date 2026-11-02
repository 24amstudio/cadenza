import CryptoKit
import Foundation

/// Host credentials in one owner-only file beside the database. Keychain items are not used: macOS asks again for
/// every item after each re-signed release, which interrupted each Host update.
final class CredentialFile: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    func read(_ account: String) throws -> Data? {
        try lock.withLock { try load()[account] }
    }

    func write(_ account: String, _ value: Data) throws {
        try lock.withLock {
            var values = try load()
            values[account] = value
            try save(values)
        }
    }

    func delete(_ account: String) throws {
        try lock.withLock {
            var values = try load()
            guard values.removeValue(forKey: account) != nil else { return }
            try save(values)
        }
    }

    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CadenzaError.failure("secure_storage", "Cannot generate a device credential.")
        }
        return Data(bytes).base64EncodedString()
    }

    static func equal(_ first: String, _ second: String) -> Bool {
        let a = SHA256.hash(data: Data(first.utf8))
        let b = SHA256.hash(data: Data(second.utf8))
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private var saveFailure: CadenzaError {
        .failure("secure_storage", "Cannot save Cadenza credentials.")
    }

    private func load() throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url),
            let values = try? JSONDecoder().decode([String: Data].self, from: data)
        else {
            // A damaged file stays in place: replacing it would discard the only copy of the credentials.
            throw CadenzaError.failure(
                "secure_storage", "Cadenza Host's credential file cannot be read. Restore it from a backup and retry.")
        }
        return values
    }

    private func save(_ values: [String: Data]) throws {
        let data = try JSONEncoder().encode(values)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard
            FileManager.default.createFile(
                atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw saveFailure }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw saveFailure
        }
    }
}
