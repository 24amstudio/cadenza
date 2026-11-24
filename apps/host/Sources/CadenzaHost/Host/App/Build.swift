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
    // The build number is what Remotes compare, since it only ever increases.
    static var build: Int64 {
        Int64(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }
    static var updatesEnabled: Bool { profile == "production" }
}
