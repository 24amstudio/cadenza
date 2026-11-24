import CadenzaSecurity
import Foundation

/// The Remote APK that matches this Host's own release. Remotes on the LAN download it from this Host, so an update does
/// not need the internet. The APK is checked against the signed release manifest before it is stored or served.
enum RemoteUpdateCache {
    struct Artifact: Codable, Equatable, Sendable {
        let version: String
        let buildNumber: Int64
        let sha256: String
        let sizeBytes: Int64
        let filename: String
    }

    /// The offer a Host makes to Remotes: in the welcome, and as the body of the manifest endpoint. Keys are snake case
    /// like the rest of the protocol.
    struct Offer: Codable, Equatable, Sendable {
        let version: String
        let buildNumber: Int64
        let sha256: String
        let sizeBytes: Int64
        let lanDownloadPath: String

        init(artifact: Artifact) {
            version = artifact.version
            buildNumber = artifact.buildNumber
            sha256 = artifact.sha256
            sizeBytes = artifact.sizeBytes
            lanDownloadPath = RemoteUpdateCache.downloadPath
        }
    }

    struct Current {
        let artifact: Artifact
        let file: URL
    }

    static let updatesPrefix = "/api/v1/updates/"
    static let manifestPath = "/api/v1/updates/manifest"
    static let downloadPath = "/api/v1/updates/remote/android.apk"
    private static let receiptName = "artifact.json"

    /// `updates/<hostVersion>` inside the Host's support directory. Older versions are removed on refresh.
    static func root(hostVersion: String, supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("updates", isDirectory: true)
            .appendingPathComponent(hostVersion, isDirectory: true)
    }

    static func current(root: URL) -> Current? {
        let receipt = root.appendingPathComponent(receiptName)
        guard let data = try? Data(contentsOf: receipt),
            let artifact = try? JSONDecoder().decode(Artifact.self, from: data)
        else { return nil }
        let file = root.appendingPathComponent(artifact.filename)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return Current(artifact: artifact, file: file)
    }

    /// Fetches the APK for `hostVersion` from its GitHub release when the stored copy is missing or stale.
    static func refresh(
        hostVersion: String, configuration: UpdateConfiguration, supportDirectory: URL
    ) async throws -> Artifact {
        let tag = "v" + hostVersion
        guard
            tag.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+(_[0-9]{8}\.[0-9]+-[0-9a-f]{12})?$"#, options: .regularExpression)
                != nil,
            ReleaseValidation.validRepository(configuration.repository),
            let key = Data(base64Encoded: configuration.publicKeySpkiBase64)
        else {
            throw CadenzaError.failure("remote_update", "This Host has no release to take the Remote update from.")
        }
        let base = "https://github.com/\(configuration.repository)/releases/download/\(tag)/"
        let http = GitHubHTTP()
        let data = try await http.bytes(base + "cadenza-release.json", maximum: 65_536)
        let signature = try await http.bytes(base + "cadenza-release.sig", maximum: 128)
        let (manifest, asset) = try ReleaseValidation.verify(
            manifest: data, signature: signature, publicKeySPKI: key,
            repository: configuration.repository, currentBuild: 0, platform: "android")
        guard manifest.tag == tag else {
            throw CadenzaError.failure("remote_update", "The signed release does not match this Host's tag.")
        }
        let root = root(hostVersion: hostVersion, supportDirectory: supportDirectory)
        let artifact = Artifact(
            version: manifest.version, buildNumber: manifest.build, sha256: asset.sha256,
            sizeBytes: asset.size, filename: asset.filename)
        if let existing = current(root: root), existing.artifact == artifact { return artifact }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let partial = root.appendingPathComponent("download.part")
        defer { try? FileManager.default.removeItem(at: partial) }
        try await http.download(base + asset.filename, to: partial, expectedSize: asset.size) { _ in }
        try ReleaseValidation.verifyFile(partial, asset: asset)
        let destination = root.appendingPathComponent(asset.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: destination)
        }
        try JSONEncoder().encode(artifact).write(to: root.appendingPathComponent(receiptName), options: .atomic)
        removeOtherVersions(keeping: root)
        return artifact
    }

    private static func removeOtherVersions(keeping root: URL) {
        let updates = root.deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(at: updates, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.standardizedFileURL != root.standardizedFileURL {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
