import XCTest
@testable import CadenzaHost

final class SSDPResponderTests: XCTestCase {
    private let request = Data(
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nST: urn:cadenza:host:1\r\n\r\n".utf8)

    func testResponderAcceptsOnlyCadenzaSearches() {
        XCTAssertTrue(SSDPResponder.requestMatches(request))
        let unrelated = Data(
            String(decoding: request, as: UTF8.self)
                .replacingOccurrences(of: "urn:cadenza:host:1", with: "ssdp:all")
                .utf8)
        XCTAssertFalse(SSDPResponder.requestMatches(unrelated))
    }

    func testResponseContainsOnlyPublicDiscoveryHints() throws {
        let response = try XCTUnwrap(
            SSDPResponder.response(
                for: request,
                hostId: "11111111-1111-1111-1111-111111111111",
                location: "https://192.168.1.10:43127/"))
        let text = try XCTUnwrap(String(data: response, encoding: .utf8))
        XCTAssertTrue(text.contains("HTTP/1.1 200 OK"))
        XCTAssertTrue(text.contains("HOST-ID: 11111111-1111-1111-1111-111111111111"))
        XCTAssertTrue(text.contains("LOCATION: https://192.168.1.10:43127/"))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("token"))
        XCTAssertNil(SSDPResponder.response(for: request, hostId: "bad", location: "https://192.168.1.10:43127/"))
        XCTAssertNil(
            SSDPResponder.response(
                for: request,
                hostId: "11111111-1111-1111-1111-111111111111",
                location: "https://host/\r\nX-Evil: 1"))
    }
}
