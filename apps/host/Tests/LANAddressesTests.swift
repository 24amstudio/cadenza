import Testing

@testable import CadenzaHost

struct LANAddressesTests {
    /// A Tailscale address sorts before a 192.168.x LAN address, so the TV must be given the LAN address instead.
    @Test func aDeviceOnTheLANIsGivenAPrivateAddressNotATailscaleOne() {
        #expect(LANAddresses.preferred(among: ["100.101.7.3", "192.168.1.25"]) == "192.168.1.25")
        #expect(LANAddresses.preferred(among: ["100.101.7.3"]) == "100.101.7.3")
        #expect(LANAddresses.preferred(among: []) == nil)
    }
}
