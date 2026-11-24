import Foundation
import Testing

@testable import CadenzaHost

struct HardwareAddressTests {
    @Test func aSixByteAddressIsLowercaseColonHexAndEmptyOrShortAddressesAreRefused() {
        #expect(HardwareAddress.format([0x0A, 0x1B, 0x2C, 0x3D, 0x4E, 0x5F]) == "0a:1b:2c:3d:4e:5f")
        #expect(HardwareAddress.format([0, 0, 0, 0, 0, 0]) == nil)
        #expect(HardwareAddress.format([0x0A, 0x1B]) == nil)
    }

    @Test func thisMacsPrimaryInterfaceReportsAWellFormedAddress() throws {
        let mac = try #require(HardwareAddress.primary())

        #expect(mac.count == 17)
        #expect(mac.split(separator: ":").count == 6)
    }
}
