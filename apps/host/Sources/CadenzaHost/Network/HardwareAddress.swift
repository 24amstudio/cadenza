import Darwin
import Foundation

/// The hardware (MAC) address of the Mac's first Ethernet or Wi-Fi interface, for Wake-on-LAN. It is sent only in the
/// welcome to an authenticated Remote.
enum HardwareAddress {
    static func primary() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }
        defer { freeifaddrs(pointer) }
        var cursor = pointer
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let interface = current.pointee
            guard let address = interface.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en"), let bytes = linkBytes(address) else { continue }
            if let formatted = format(bytes) { return formatted }
        }
        return nil
    }

    /// Colon-separated lowercase hex. Nil unless there are six bytes and at least one is non-zero.
    static func format(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func linkBytes(_ address: UnsafeMutablePointer<sockaddr>) -> [UInt8]? {
        let link = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_dl.self).pointee
        let nameLength = Int(link.sdl_nlen)
        let addressLength = Int(link.sdl_alen)
        let capacity = MemoryLayout.size(ofValue: link.sdl_data)
        guard addressLength == 6, nameLength + addressLength <= capacity else { return nil }
        return withUnsafeBytes(of: link.sdl_data) { raw in
            Array(raw[nameLength..<(nameLength + addressLength)])
        }
    }
}
