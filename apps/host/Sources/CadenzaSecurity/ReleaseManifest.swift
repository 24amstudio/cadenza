import CryptoKit
import Foundation

public struct ReleaseAsset: Codable, Sendable {
    public var platform: String
    public var filename: String
    public var sha256: String
    public var size: Int64
    public var minimumOs: Int

    public init(platform: String, filename: String, sha256: String, size: Int64, minimumOS: Int) {
        self.platform = platform
        self.filename = filename
        self.sha256 = sha256
        self.size = size
        self.minimumOs = minimumOS
    }
}

public struct ReleaseManifest: Codable, Sendable {
    public var schema: Int = 1
    public var repository: String
    public var version: String
    public var build: Int64
    public var tag: String
    public var protocolMajor: Int = 1
    public var assets: [ReleaseAsset]
    public var buildId: String? = nil
    public var changelog: [ReleaseNote]? = nil

    public init(repository: String, version: String, build: Int64, assets: [ReleaseAsset]) {
        self.repository = repository
        self.version = version
        self.build = build
        tag = "v" + version
        self.assets = assets
    }
}

public struct ReleaseNote: Codable, Sendable {
    public var version: String
    public var build: Int64
    public var changes: [String]
}

public enum ReleaseFailure: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case let .invalid(message): return message }
    }
}

public enum ReleaseValidation {
    public static func verify(
        manifest data: Data, signature: Data, publicKeySPKI: Data,
        repository: String, currentBuild: Int64, platform: String
    ) throws -> (ReleaseManifest, ReleaseAsset) {
        guard data.count <= 65_536, signature.count <= 128,
              validRepository(repository) else { throw ReleaseFailure.invalid("Invalid release configuration.") }
        let key = try P256.Signing.PublicKey(derRepresentation: publicKeySPKI)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signature)
        guard key.isValidSignature(signature, for: data) else {
            throw ReleaseFailure.invalid("The update signature does not match the configured release key.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(ReleaseManifest.self, from: data)
        if let identity = manifest.buildId, identity.range(of: #"^([0-9a-f]{40}|source-[0-9a-f]{64})$"#, options: .regularExpression) == nil {
            throw ReleaseFailure.invalid("Invalid release build identity.")
        }
        if let history = manifest.changelog {
            guard history.count <= 100, Set(history.map(\.build)).count == history.count,
                  history.allSatisfy({ entry in
                    entry.build > 0 && entry.build <= manifest.build && entry.changes.count <= 100
                        && entry.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
                        && entry.changes.allSatisfy { !$0.isEmpty && $0.count <= 1000 }
                  }) else { throw ReleaseFailure.invalid("Invalid signed changelog.") }
        }
        guard manifest.schema == 1, manifest.protocolMajor == 1,
              manifest.repository == repository,
              manifest.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              manifest.tag == "v" + manifest.version,
              manifest.build > currentBuild,
              manifest.build <= 9_007_199_254_740_991,
              manifest.assets.filter({ $0.platform == platform }).count == 1,
              let asset = manifest.assets.first(where: { $0.platform == platform }),
              asset.minimumOs >= 26,
              asset.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              asset.size > 0, asset.size <= 134_217_728 else {
            throw ReleaseFailure.invalid("The update is incompatible, invalid, or not newer than this installation.")
        }
        let expected = platform == "macos-arm64"
            ? "Cadenza-Host-\(manifest.version)-arm64.zip"
            : "Cadenza-Remote-\(manifest.version).apk"
        guard asset.filename == expected else { throw ReleaseFailure.invalid("Unexpected release filename.") }
        return (manifest, asset)
    }

    public static func validRepository(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_\-]{0,38}/[A-Za-z0-9][A-Za-z0-9_.\-]{0,99}$"#, options: .regularExpression) != nil
            && !value.contains("..")
    }

    public static func verifyFile(_ file: URL, asset: ReleaseAsset) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == asset.size else {
            throw ReleaseFailure.invalid("The update download is incomplete.")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 262_144), !chunk.isEmpty { digest.update(data: chunk) }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == asset.sha256 else { throw ReleaseFailure.invalid("The update checksum does not match its signed manifest.") }
    }

    public static func encode(_ manifest: ReleaseManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }
}
