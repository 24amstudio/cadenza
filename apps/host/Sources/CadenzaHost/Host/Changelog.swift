import CadenzaSecurity
import Foundation

enum HostChangelog {
    private struct History: Decodable { var releases: [ReleaseNote] }

    static func bundled() -> String {
        guard let url = Bundle.main.url(forResource: "changelog", withExtension: "json"),
            let data = try? Data(contentsOf: url), data.count <= 65_536,
            let history = try? JSONDecoder().decode(History.self, from: data),
            let current = history.releases.first(where: {
                String($0.build) == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            })
        else {
            return "Bundled changelog is unavailable. No release comparison was performed."
        }
        return current.changes.joined(separator: "\n\n")
    }

    static func compare(configuration: UpdateConfiguration) async throws -> String {
        guard ReleaseValidation.validRepository(configuration.repository),
            let key = Data(base64Encoded: configuration.publicKeySpkiBase64)
        else {
            throw CadenzaError.failure("changelog", "No release source is configured. No newer release was checked.")
        }
        let http = GitHubHTTP()
        let metadata = try await http.bytes(
            "https://api.github.com/repos/\(configuration.repository)/releases/latest", maximum: 65_536)
        guard let object = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
            object["draft"] as? Bool == false, object["prerelease"] as? Bool == false,
            let tag = object["tag_name"] as? String,
            tag.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+(_[0-9]{8}\.[0-9]+-[0-9a-f]{12})?$"#, options: .regularExpression) != nil
        else {
            throw CadenzaError.failure("changelog", "A compatible stable release is unavailable.")
        }
        let base = "https://github.com/\(configuration.repository)/releases/download/\(tag)/"
        let data = try await http.bytes(base + "cadenza-release.json", maximum: 65_536)
        let signature = try await http.bytes(base + "cadenza-release.sig", maximum: 128)
        let (release, _) = try ReleaseValidation.verify(
            manifest: data, signature: signature, publicKeySPKI: key, repository: configuration.repository,
            currentBuild: 0, platform: "macos-arm64")
        guard release.tag == tag else {
            throw CadenzaError.failure("changelog", "The signed release does not match its tag.")
        }
        let installed = Int64(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        if release.build < installed {
            return "This installation is ahead of the published release. No newer release was found."
        }
        if release.build == installed {
            return release.buildId == HostBuild.identity
                ? "This build matches the published release."
                : "The release number matches, but its build identity differs or is unavailable. No newer release was established."
        }
        let relevant =
            release.changelog?.filter { $0.build > installed && $0.build <= release.build }.sorted {
                $0.build > $1.build
            } ?? []
        let notes = relevant.map { $0.version + "\n" + $0.changes.joined(separator: "\n") }.joined(separator: "\n\n")
        return "Changes from \(HostBuild.version) to \(release.version):\n\n"
            + (notes.isEmpty ? "The publisher did not include signed change notes." : notes)
    }
}
