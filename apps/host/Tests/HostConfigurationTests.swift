import Foundation
import XCTest

@testable import CadenzaHost

final class HostConfigurationTests: XCTestCase {
    func testAConfigurationWithoutTheWebSettingTurnsCadenzaWebOn() throws {
        let encoded = try JSONEncoder().encode(HostConfiguration())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "webEnabled")
        let decoded = try JSONDecoder().decode(
            HostConfiguration.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertTrue(decoded.webEnabled)
    }
}
