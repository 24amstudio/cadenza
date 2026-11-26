import Foundation

/// The stage channel's sessions. A receiver must present a profile, then either a valid token or an approved PIN before
/// it gets track data or audio. The hub owns no audio: the audio transmitter asks it which sessions to feed.
@MainActor
final class StageHub {
    /// One socket. `send` writes a text or binary frame and reports false when the socket cannot take it now.
    final class Session {
        let id: String
        /// The socket's role: `tv_stage` for a Tier-2 browser, or `android_tv_receiver` for a Tier-3 Android TV.
        let role: String
        let send: (Data, Bool) -> Bool
        let close: () -> Void
        var profile: StageReceiverProfile?
        var isApproved = false
        var isTransmitting = false

        init(id: String, role: String, send: @escaping (Data, Bool) -> Bool, close: @escaping () -> Void) {
            self.id = id
            self.role = role
            self.send = send
            self.close = close
        }
    }

    private(set) var sessions: [String: Session] = [:]
    let receivers: StageReceivers
    /// The latest suite message, sent to a receiver as soon as it becomes approved.
    private(set) var currentSuite: Data?
    /// Called when a receiver's state or the pending PIN list changes, so the next snapshot carries it.
    var onChange: () -> Void = {}
    /// Called with the playback kind of each command an approved receiver sends.
    var onCommand: (Session, String) -> Void = { _, _ in }

    init(receivers: StageReceivers) {
        self.receivers = receivers
    }

    var approvedSessions: [Session] {
        sessions.values.filter(\.isApproved).sorted { $0.id < $1.id }
    }

    func attach(_ session: Session) {
        sessions[session.id] = session
        onChange()
    }

    func detach(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        receivers.dropPending(sessionId: sessionId)
        onChange()
    }

    /// Handles one JSON text frame. Anything that is not a valid profile closes the socket, so no state is left half-set.
    func receive(_ text: Data, from sessionId: String, now: Date = Date()) {
        guard let session = sessions[sessionId] else { return }
        if session.isApproved {
            if let kind = StageCommand.kind(text) { onCommand(session, kind) }
            return
        }
        guard let profile = StageReceiverProfile.parse(text), profile.matches(role: session.role) else {
            session.close()
            return
        }
        session.profile = profile
        if let token = profile.receiverToken, receivers.isAuthorized(receiverId: profile.receiverId, token: token) {
            approve(session)
            return
        }
        let pending = receivers.issuePIN(
            sessionId: sessionId, receiverId: profile.receiverId, name: profile.displayName, now: now)
        let remaining = max(1_000, Int(pending.expiresAt.timeIntervalSince(now) * 1_000))
        _ = session.send(StageMessage.pairing(pin: pending.pin, expiresInMs: remaining), false)
        onChange()
    }

    /// Approves the receiver whose unexpired PIN matches. Returns false when no pending receiver has that PIN.
    @discardableResult
    func approve(pin: String, now: Date = Date()) -> Bool {
        guard let request = receivers.pending.first(where: { $0.pin == pin && $0.expiresAt > now }),
            let session = sessions[request.sessionId],
            let token = receivers.approve(sessionId: request.sessionId, now: now)
        else { return false }
        _ = session.send(StageMessage.accepted(token: token), false)
        approve(session)
        return true
    }

    private func approve(_ session: Session) {
        session.isApproved = true
        if let currentSuite { _ = session.send(currentSuite, false) }
        onChange()
    }

    /// Replaces the current suite and sends it to every approved receiver.
    func publishSuite(_ message: Data) {
        currentSuite = message
        broadcast(message)
    }

    func broadcast(_ message: Data, binary: Bool = false) {
        for session in approvedSessions {
            _ = session.send(message, binary)
        }
    }

    /// The approved receivers as the state snapshot lists them, in a stable order.
    func snapshot() -> [CastSnapshot.Stage] {
        approvedSessions.compactMap { session in
            guard let profile = session.profile else { return nil }
            return CastSnapshot.Stage(
                receiverId: profile.receiverId, name: profile.displayName,
                transport: profile.transport.rawValue, transmitting: session.isTransmitting)
        }
    }

    func setTransmitting(sessionId: String, _ transmitting: Bool) {
        sessions[sessionId]?.isTransmitting = transmitting
        onChange()
    }

    func forget(receiverId: String) {
        receivers.forget(receiverId: receiverId)
        for session in sessions.values where session.profile?.receiverId == receiverId {
            session.isApproved = false
            session.isTransmitting = false
            session.close()
        }
        onChange()
    }
}
