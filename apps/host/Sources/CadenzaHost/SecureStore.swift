import CryptoKit
import Foundation
import Security

enum SecureStore {
    static let service = "app.cadence.host"

    static func read(_ account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw error(status) }
        return data
    }

    static func write(_ account: String, _ value: Data) throws {
        let query =
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ] as [CFString: Any]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: value] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = value
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw CadenzaError.failure("secure_storage", "Cannot save Cadenza credentials in Keychain.")
            }
        } else if status != errSecSuccess {
            throw error(status)
        }
    }

    static func delete(_ account: String) throws {
        let status = SecItemDelete(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }

    private static func error(_ status: OSStatus) -> CadenzaError {
        .failure("secure_storage", SecCopyErrorMessageString(status, nil) as String? ?? "Keychain access failed.")
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
}

struct TLSIdentity {
    let identity: SecIdentity
    let fingerprint: String
    let certificateDerBase64: String

    @MainActor static func loadOrCreate(hostId: String) async throws -> TLSIdentity {
        let account = "tls.\(hostId)"
        let record: IdentityRecord
        if let data = try SecureStore.read(account) {
            record = try JSONDecoder().decode(IdentityRecord.self, from: data)
        } else {
            record = try await generate(hostId: hostId)
            try SecureStore.write(account, JSONEncoder().encode(record))
        }
        var imported: CFArray?
        let options = [kSecImportExportPassphrase: record.password] as CFDictionary
        guard SecPKCS12Import(record.pkcs12 as CFData, options, &imported) == errSecSuccess,
            let items = imported as? [[String: Any]],
            let value = items.first?[kSecImportItemIdentity as String]
        else {
            throw CadenzaError.failure(
                "secure_storage", "Cannot load Host's TLS identity. Restore Keychain access and retry.")
        }
        // SecPKCS12Import guarantees kSecImportItemIdentity has SecIdentity's CF type.
        let identity = value as! SecIdentity
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
            throw CadenzaError.failure("secure_storage", "The Host certificate is unavailable.")
        }
        let certificateData = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: certificateData)
        return TLSIdentity(
            identity: identity, fingerprint: digest.map { String(format: "%02x", $0) }.joined(),
            certificateDerBase64: certificateData.base64EncodedString()
        )
    }

    private struct IdentityRecord: Codable {
        let pkcs12: Data
        let password: String
    }

    private static func generate(hostId: String) async throws -> IdentityRecord {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = directory.appendingPathComponent("key.pem").path
        let certificate = directory.appendingPathComponent("certificate.pem").path
        let archive = directory.appendingPathComponent("identity.p12").path
        _ = try await Subprocess.run(
            "/usr/bin/openssl",
            [
                "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650",
                "-keyout", key, "-out", certificate, "-subj", "/CN=Cadenza-\(hostId)",
            ], timeout: 15)
        let password = try SecureStore.randomToken()
        var environment = ProcessInfo.processInfo.environment
        environment["CADENZA_IDENTITY_PASSWORD"] = password
        _ = try await Subprocess.run(
            "/usr/bin/openssl",
            [
                "pkcs12", "-export", "-inkey", key, "-in", certificate, "-out", archive,
                "-passout", "env:CADENZA_IDENTITY_PASSWORD",
            ], timeout: 5, environment: environment)
        return IdentityRecord(pkcs12: try Data(contentsOf: URL(fileURLWithPath: archive)), password: password)
    }
}
