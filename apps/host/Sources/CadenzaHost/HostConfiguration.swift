import Darwin
import Foundation

struct HostConfiguration: Codable {
    var name: String = Host.current().localizedName ?? "Cadenza Host"
    var port: UInt16 = 43127
    var storefront = "us"
    var advertisedAddress = ""
    var automaticUpdates = true
    var updates = UpdateConfiguration()

    static func load() -> HostConfiguration {
        if let data = UserDefaults.standard.data(forKey: "configuration"),
           let value = try? JSONDecoder().decode(HostConfiguration.self, from: data) {
            return value
        }
        var defaults = HostConfiguration()
        if let url = Bundle.main.url(forResource: "release-config", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let updates = try? Wire.decode(UpdateConfiguration.self, from: data) { defaults.updates = updates }
        return defaults
    }

    func save() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "configuration")
    }
}

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
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var value = value
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &value, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: buffer)
            if !ip.hasPrefix("169.254.") { addresses.append(ip) }
        }
        return Array(Set(addresses)).sorted()
    }
}
