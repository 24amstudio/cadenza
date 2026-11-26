import Darwin
import Foundation

enum LANAddresses {
    static func all() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return [] }
        defer { freeifaddrs(pointer) }
        var cursor = pointer
        var addresses: [String] = []
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let interface = current.pointee
            guard let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET),
                interface.ifa_flags & UInt32(IFF_UP) != 0,
                interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0
            else { continue }
            var value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &value, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let ip = String(decoding: bytes, as: UTF8.self)
            if !ip.hasPrefix("169.254.") { addresses.append(ip) }
        }
        return Array(Set(addresses)).sorted()
    }

    /// The address a LAN device such as a Cast TV can reach. Carrier-grade NAT (100.64.0.0/10, which Tailscale uses) is
    /// not on the LAN, so it is chosen only when no other address exists.
    static func lanAddress() -> String? {
        preferred(among: all())
    }

    static func preferred(among addresses: [String]) -> String? {
        addresses.first { !isCarrierNAT($0) } ?? addresses.first
    }

    private static func isCarrierNAT(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 100 && (64...127).contains(octets[1])
    }
}
