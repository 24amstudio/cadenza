import Foundation

struct HostConfiguration: Codable {
    var name: String = Host.current().localizedName ?? "Cadenza Host"
    var port: UInt16 = 43127
    var storefront = "us"
    var advertisedAddress = ""
    var automaticUpdates = true
    var lyricsProviderEnabled = true
    var cacheLimitBytes: Int64 = 256 * 1_048_576
    var updates = UpdateConfiguration()

    enum CodingKeys: String, CodingKey {
        case name, port, storefront, advertisedAddress, automaticUpdates, lyricsProviderEnabled, cacheLimitBytes, updates
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? (Host.current().localizedName ?? "Cadenza Host")
        port = try values.decodeIfPresent(UInt16.self, forKey: .port) ?? 43127
        storefront = try values.decodeIfPresent(String.self, forKey: .storefront) ?? "us"
        advertisedAddress = try values.decodeIfPresent(String.self, forKey: .advertisedAddress) ?? ""
        automaticUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? true
        lyricsProviderEnabled = try values.decodeIfPresent(Bool.self, forKey: .lyricsProviderEnabled) ?? true
        cacheLimitBytes = try values.decodeIfPresent(Int64.self, forKey: .cacheLimitBytes) ?? 256 * 1_048_576
        updates = try values.decodeIfPresent(UpdateConfiguration.self, forKey: .updates) ?? UpdateConfiguration()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(port, forKey: .port)
        try values.encode(storefront, forKey: .storefront)
        try values.encode(advertisedAddress, forKey: .advertisedAddress)
        try values.encode(automaticUpdates, forKey: .automaticUpdates)
        try values.encode(lyricsProviderEnabled, forKey: .lyricsProviderEnabled)
        try values.encode(cacheLimitBytes, forKey: .cacheLimitBytes)
        try values.encode(updates, forKey: .updates)
    }

    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.utf8.count <= 63
            && storefront.range(of: "^[a-z]{2}$", options: .regularExpression) != nil
            && port in 1024...65_535
            && cacheLimitBytes >= 64 * 1_048_576
            && cacheLimitBytes <= 1_024 * 1_048_576
    }

    static func load() -> HostConfiguration {
        if let data = UserDefaults.standard.data(forKey: "configuration"),
            let value = try? JSONDecoder().decode(HostConfiguration.self, from: data)
        {
            if value.isUsable { return value }
        }
        var defaults = HostConfiguration()
        if let url = Bundle.main.url(forResource: "release-config", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let updates = try? Wire.decode(UpdateConfiguration.self, from: data)
        {
            defaults.updates = updates
        }
        return defaults
    }

    func save() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "configuration")
    }
}
