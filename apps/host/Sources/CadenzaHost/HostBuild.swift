import Foundation

enum HostBuild {
    static var profile: String {
        Bundle.main.object(forInfoDictionaryKey: "CadenzaBuildProfile") as? String ?? "development"
    }
    static var identity: String {
        Bundle.main.object(forInfoDictionaryKey: "CadenzaBuildID") as? String ?? "unpackaged-development"
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
    static var updatesEnabled: Bool { profile == "production" }
}
