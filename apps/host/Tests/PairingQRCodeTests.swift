import Foundation
import XCTest

@testable import CadenzaHost

final class PairingQRCodeTests: XCTestCase {
    private func invitation(
        host: String = "192.168.1.20", secret: String = String(repeating: "S", count: 43), webPort: Int?
    )
        -> PairingInvitation
    {
        PairingInvitation(host: host, port: 43127, secret: secret, hostName: "Mac", webPort: webPort)
    }

    private func decodeNative(_ text: String) -> Data? {
        guard text.hasPrefix(PairingQRCode.nativePrefix) else { return nil }
        var encoded = String(text.dropFirst(PairingQRCode.nativePrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        return Data(base64Encoded: encoded)
    }

    func testWithCadenzaWebOffTheCodeIsTheNativePayloadAlone() throws {
        let text = try XCTUnwrap(PairingQRCode.text(for: invitation(webPort: nil)))

        XCTAssertTrue(text.hasPrefix("CDZP:"))
        XCTAssertNil(PairingQRCode.webAddress(for: invitation(webPort: nil)))
    }

    func testWithCadenzaWebOnTheCodeOpensTheWebRemoteAndCarriesTheNativePayload() throws {
        let text = try XCTUnwrap(PairingQRCode.text(for: invitation(webPort: 43129)))

        XCTAssertTrue(text.hasPrefix("http://192.168.1.20:43129/#CDZP:"))
        let native = try XCTUnwrap(text.split(separator: "#", maxSplits: 1).last).description
        XCTAssertEqual(native, try XCTUnwrap(PairingQRCode.nativePayload(for: invitation(webPort: nil))))
    }

    func testTheNativePayloadHoldsTheControlPortAndSecretWithoutKeyMaterial() throws {
        let native = try XCTUnwrap(PairingQRCode.nativePayload(for: invitation(webPort: nil)))
        let bytes = try XCTUnwrap(decodeNative(native))
        let hostLength = Int(bytes[5])
        let portIndex = 6 + hostLength
        let secretLength = Int(bytes[portIndex + 2])

        XCTAssertEqual(Array(bytes.prefix(5)), [0x43, 0x44, 0x5A, 0x50, PairingQRCode.payloadVersion])
        XCTAssertEqual(String(decoding: bytes[6..<portIndex], as: UTF8.self), "192.168.1.20")
        XCTAssertEqual(Int(bytes[portIndex]) << 8 | Int(bytes[portIndex + 1]), 43127)
        XCTAssertEqual(
            String(decoding: bytes[(portIndex + 3)..<(portIndex + 3 + secretLength)], as: UTF8.self),
            String(repeating: "S", count: 43))
        XCTAssertEqual(bytes.count, portIndex + 3 + secretLength)
    }

    func testIPv6HostsAreBracketedInTheWebAddress() throws {
        let text = try XCTUnwrap(PairingQRCode.text(for: invitation(host: "fd00::1", webPort: 43129)))

        XCTAssertTrue(text.hasPrefix("http://[fd00::1]:43129/#CDZP:"))
    }

    func testAnEmptySecretProducesNoCode() {
        XCTAssertNil(PairingQRCode.text(for: invitation(secret: "", webPort: 43129)))
    }
}
