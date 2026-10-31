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

    /// Rewrites an item so its access list trusts the running signature. macOS asks for each item whose list
    /// still names an older signature, so callers run this once per signing identity.
    static func reauthorize(_ account: String) throws {
        guard let value = try read(account) else { return }
        try delete(account)
        try write(account, value)
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
