import Foundation

// One invitation has one native payload. With Cadenza Web on, the payload follows the web address in the URL fragment:
// a regular camera opens the browser Remote, and Cadenza Remote reads the native "CDZP:" data from the fragment. With
// Cadenza Web off, the code is the native payload alone, which a regular camera does not open as a link.
enum PairingQRCode {
    static let nativePrefix = "CDZP:"
    static let payloadVersion: UInt8 = 3

    static func text(for invitation: PairingInvitation) -> String? {
        guard let native = nativePayload(for: invitation) else { return nil }
        guard let address = webAddress(for: invitation) else { return native }
        return address + "#" + native
    }

    static func webAddress(for invitation: PairingInvitation) -> String? {
        guard let webPort = invitation.webPort else { return nil }
        return "http://\(urlHost(invitation.host)):\(webPort)/"
    }

    // Layout: "CDZP" magic, version 3, length-prefixed host, 2-byte control port, and length-prefixed one-use secret.
    // The payload is base64url without padding. Native Remotes connect without a certificate, so no key material
    // belongs in the invitation.
    static func nativePayload(for invitation: PairingInvitation) -> String? {
        let address = Data(invitation.host.utf8)
        let secret = Data(invitation.secret.utf8)
        guard !address.isEmpty, address.count <= 255, !secret.isEmpty, secret.count <= 255 else { return nil }
        var result = Data([0x43, 0x44, 0x5A, 0x50, payloadVersion])
        result.append(UInt8(address.count))
        result.append(address)
        result.append(UInt8((invitation.port >> 8) & 0xFF))
        result.append(UInt8(invitation.port & 0xFF))
        result.append(UInt8(secret.count))
        result.append(secret)
        let encoded = result.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return nativePrefix + encoded
    }

    private static func urlHost(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }
}
