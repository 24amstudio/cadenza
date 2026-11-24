import Foundation

/// The Sing model this build expects. Release builds write these values into Info.plist from the pinned model and
/// the published archive. A build without them cannot download the model.
struct SingModelSpec: Equatable, Sendable {
    let version: String
    let sha256: String
    let sizeBytes: Int64
    let url: URL?

    static func current(bundle: Bundle = .main) -> SingModelSpec? {
        guard
            let version = bundle.object(forInfoDictionaryKey: "CadenzaSingModelVersion") as? String,
            version.range(of: #"^[a-z0-9][a-z0-9.-]{0,79}$"#, options: .regularExpression) != nil,
            let sha256 = bundle.object(forInfoDictionaryKey: "CadenzaSingModelSHA256") as? String,
            sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
            let sizeText = bundle.object(forInfoDictionaryKey: "CadenzaSingModelBytes") as? String,
            let sizeBytes = Int64(sizeText), sizeBytes > 0, sizeBytes <= 2_147_483_648
        else { return nil }
        let urlText = bundle.object(forInfoDictionaryKey: "CadenzaSingModelURL") as? String ?? ""
        let url = URL(string: urlText).flatMap { $0.scheme == "https" && $0.host == "github.com" ? $0 : nil }
        return SingModelSpec(version: version, sha256: sha256, sizeBytes: sizeBytes, url: url)
    }
}
