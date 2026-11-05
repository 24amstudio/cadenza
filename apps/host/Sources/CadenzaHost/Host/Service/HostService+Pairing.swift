import Foundation

// The pairing window: an invitation with a QR secret and a PIN that rolls over while the window is open.
extension HostService {
    func createInvitation() throws -> PairingInvitation {
        let address =
            configuration.advertisedAddress.isEmpty ? LANAddresses.all().first : configuration.advertisedAddress
        guard let address else {
            throw CadenzaError.failure("network", "Connect Cadenza Host to your local network first.")
        }
        let invitation = PairingInvitation(
            host: address, port: Int(configuration.port),
            secret: try CredentialFile.randomToken(), hostName: configuration.name,
            pin: Self.newPin(),
            webPort: configuration.webEnabled ? Int(configuration.webPort) : nil
        )
        self.invitation = invitation
        invitationDeadline = monotonicMs() + 300_000
        invitationPinDeadline = monotonicMs() + Self.pinLifetimeMs
        invitationPinAttempts = 0
        startPinRotation()
        return invitation
    }

    // Rolls the PIN over whenever one expires, so the pairing window stays usable without reopening it. The window
    // closes when its invitation expires or a Remote pairs.
    private func startPinRotation() {
        pinRotation?.cancel()
        pinRotation = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(Self.pinLifetimeMs))
                guard let self, !Task.isCancelled else { return }
                guard var invitation = self.invitation, monotonicMs() < self.invitationDeadline else {
                    self.endInvitation()
                    return
                }
                invitation.pin = Self.newPin()
                self.invitation = invitation
                self.invitationPinDeadline = monotonicMs() + Self.pinLifetimeMs
                self.invitationPinAttempts = 0
                self.onInvitationChanged?(invitation)
            }
        }
    }

    func endInvitation() {
        pinRotation?.cancel()
        pinRotation = nil
        invitation = nil
        onInvitationChanged?(nil)
    }

    private static func newPin() -> String {
        String(format: "%04d", Int.random(in: 0...9_999))
    }
}
