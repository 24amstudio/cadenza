import AppKit
import CadenzaSecurity
import Foundation

@MainActor
final class HostUpdater {
    let directory: URL
    private let http = GitHubHTTP()
    private(set) var staged: (URL, ReleaseManifest)?
    var onProgress: ((Double) -> Void)?

    init(directory: URL) { self.directory = directory.appendingPathComponent("Updates", isDirectory: true) }

    var currentBuild: Int64 {
        Int64(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1
    }

    func check(configuration: UpdateConfiguration) async throws -> String {
        guard HostBuild.updatesEnabled else {
            throw CadenzaError.failure("update", "Updates are disabled in this build.")
        }
        guard ReleaseValidation.validRepository(configuration.repository),
            let key = Data(base64Encoded: configuration.publicKeySpkiBase64)
        else {
            throw CadenzaError.failure("update", "Set a GitHub repository and public release key in Host settings.")
        }
        let metadata = try await http.bytes(
            "https://api.github.com/repos/\(configuration.repository)/releases/latest", maximum: 65_536
        )
        guard let release = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
            release["draft"] as? Bool == false, release["prerelease"] as? Bool == false,
            let tag = release["tag_name"] as? String,
            tag.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
        else {
            throw CadenzaError.failure("update", "The repository has no compatible stable release.")
        }
        let base = "https://github.com/\(configuration.repository)/releases/download/\(tag)/"
        let data = try await http.bytes(base + "cadenza-release.json", maximum: 65_536)
        let signature = try await http.bytes(base + "cadenza-release.sig", maximum: 128)
        let (manifest, asset) = try ReleaseValidation.verify(
            manifest: data, signature: signature, publicKeySPKI: key,
            repository: configuration.repository, currentBuild: 0, platform: "macos-arm64"
        )
        guard manifest.tag == tag, asset.minimumOs <= ProcessInfo.processInfo.operatingSystemVersion.majorVersion else {
            throw CadenzaError.failure("update", "This update needs a different macOS version.")
        }
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        if manifest.build <= currentBuild { return "No newer release is available." }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let archive = directory.appendingPathComponent(asset.filename)
        let partial = directory.appendingPathComponent("download.part")
        defer { try? FileManager.default.removeItem(at: partial) }
        if !FileManager.default.fileExists(atPath: archive.path) {
            try await http.download(base + asset.filename, to: partial, expectedSize: asset.size) { [weak self] value in
                Task { @MainActor in self?.onProgress?(value) }
            }
            try ReleaseValidation.verifyFile(partial, asset: asset)
            try FileManager.default.moveItem(at: partial, to: archive)
        } else {
            try ReleaseValidation.verifyFile(archive, asset: asset)
        }
        try data.write(to: directory.appendingPathComponent("cadenza-release.json"), options: .atomic)
        try signature.write(to: directory.appendingPathComponent("cadenza-release.sig"), options: .atomic)
        staged = (archive, manifest)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "zip" && file != archive {
            try FileManager.default.removeItem(at: file)
        }
        return "Cadenza \(manifest.version) is ready to install."
    }

    func install(configuration: UpdateConfiguration, store: HostStore) throws {
        guard HostBuild.updatesEnabled else {
            throw CadenzaError.failure("update", "Updates are disabled in this build.")
        }
        guard let (archive, _) = staged, Bundle.main.bundleURL.pathExtension == "app",
            let executable = Bundle.main.executableURL
        else {
            throw CadenzaError.failure("update", "Install the bundled Cadenza Host.app before using self-updates.")
        }
        guard try store.database.query("SELECT command_id FROM command_intents WHERE phase!='complete' LIMIT 1").isEmpty
        else {
            throw CadenzaError.failure("update", "Resolve unconfirmed Music actions before restarting Host.")
        }
        try store.database.backup(to: directory.appendingPathComponent("before-update.sqlite"))
        let request = InstallRequest(
            applicationPath: Bundle.main.bundleURL.path, archivePath: archive.path,
            manifestPath: directory.appendingPathComponent("cadenza-release.json").path,
            signaturePath: directory.appendingPathComponent("cadenza-release.sig").path,
            publicKeySpkiBase64: configuration.publicKeySpkiBase64, repository: configuration.repository,
            parentPid: ProcessInfo.processInfo.processIdentifier, currentBuild: currentBuild,
            resultPath: directory.appendingPathComponent("install-result.json").path
        )
        let requestURL = directory.appendingPathComponent("install-request.json")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        try encoder.encode(request).write(to: requestURL, options: .atomic)
        let helper = executable.deletingLastPathComponent().appendingPathComponent("CadenzaUpdater")
        let process = Process()
        process.executableURL = helper
        process.arguments = [requestURL.path]
        try process.run()
        NSApplication.shared.terminate(nil)
    }
}
