import Foundation

/// The subwoofer setup the Host keeps across launches, in the same defaults domain as the Host's other settings.
enum RemoteAudioSetupStorage {
    static let key = "remoteAudioSetup"

    static func load(_ defaults: UserDefaults = .standard) -> RemoteAudioStreamConfig? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? RemoteAudioStreamConfig.decode(data)
    }

    static func save(_ config: RemoteAudioStreamConfig, defaults: UserDefaults = .standard) {
        defaults.set(config.message(), forKey: key)
    }
}
