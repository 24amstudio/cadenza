import CryptoKit
import Foundation

/// Which stage receivers the listener has approved, and which are waiting for a PIN. Approval gives a receiver a token.
/// The Host keeps only a hash of that token, so a copied file cannot open a stage. A corrupt file is ignored, and the
/// receivers pair again.
@MainActor
final class StageReceivers {
    struct Approved: Codable, Equatable {
        let receiverId: String
        var name: String
        let tokenHash: String
    }

    struct Pending: Equatable {
        let sessionId: String
        let receiverId: String
        let name: String
        let pin: String
        let expiresAt: Date
    }

    static let pinLifetime: TimeInterval = 300
    static let maximumPending = 4

    private(set) var approved: [Approved] = []
    private(set) var pending: [Pending] = []
    private let file: URL?

    init(file: URL?) {
        self.file = file
        approved = Self.load(file)
    }

    /// A PIN for one socket. A socket that asks again keeps its PIN until it expires.
    func issuePIN(sessionId: String, receiverId: String, name: String, now: Date) -> Pending {
        prune(now: now)
        if let existing = pending.first(where: { $0.sessionId == sessionId }) { return existing }
        let entry = Pending(
            sessionId: sessionId, receiverId: receiverId, name: name, pin: Self.randomPIN(),
            expiresAt: now.addingTimeInterval(Self.pinLifetime))
        pending.append(entry)
        if pending.count > Self.maximumPending { pending.removeFirst(pending.count - Self.maximumPending) }
        return entry
    }

    /// Approves one pending receiver. Returns its token once, for the socket that asked for it.
    func approve(sessionId: String, now: Date) -> String? {
        prune(now: now)
        guard let index = pending.firstIndex(where: { $0.sessionId == sessionId }) else { return nil }
        let request = pending.remove(at: index)
        let token = Self.randomToken()
        approved.removeAll { $0.receiverId == request.receiverId }
        approved.append(Approved(receiverId: request.receiverId, name: request.name, tokenHash: Self.hash(token)))
        save()
        return token
    }

    func isAuthorized(receiverId: String, token: String) -> Bool {
        guard let receiver = approved.first(where: { $0.receiverId == receiverId }) else { return false }
        return receiver.tokenHash == Self.hash(token)
    }

    func forget(receiverId: String) {
        approved.removeAll { $0.receiverId == receiverId }
        save()
    }

    func dropPending(sessionId: String) {
        pending.removeAll { $0.sessionId == sessionId }
    }

    private func prune(now: Date) {
        pending.removeAll { $0.expiresAt <= now }
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(approved) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func load(_ file: URL?) -> [Approved] {
        guard let file, let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode([Approved].self, from: data)
        else { return [] }
        return decoded.filter { isId($0.receiverId) && $0.tokenHash.count == 64 }
    }

    static func isId(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80
    }

    static func randomPIN() -> String {
        String(format: "%04d", Int.random(in: 0...9_999))
    }

    static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
