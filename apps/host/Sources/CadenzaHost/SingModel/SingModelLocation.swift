import Foundation

/// Record written beside an installed model. Its version and checksum decide whether the model is current.
struct SingModelReceipt: Codable, Equatable, Sendable {
    var version: String
    var sha256: String
    var sizeBytes: Int64
    var installedAt: Date
}

/// Where the downloaded Sing model lives. It is outside the app bundle, so replacing Cadence Host.app keeps it.
/// The directory keeps the existing "Cadence Host" name, because it is a preserved install identifier.
struct SingModelLocation: Sendable {
    static let files = ["model.safetensors", "config.json", "LICENSE"]
    static let receiptName = "installed_model.json"

    /// `Cadence Host/models`. Tests point this at a temporary directory.
    let modelsDirectory: URL

    static func standard() -> SingModelLocation {
        let support =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return SingModelLocation(
            modelsDirectory: support.appendingPathComponent("Cadence Host", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true))
    }

    var installedDirectory: URL { modelsDirectory.appendingPathComponent("sing", isDirectory: true) }
    var stagingDirectory: URL { modelsDirectory.appendingPathComponent("sing.staging", isDirectory: true) }

    /// The receipt of a complete installation, or nil when the model is missing, partial, or unreadable.
    func installedReceipt() -> SingModelReceipt? {
        Self.receipt(in: installedDirectory)
    }

    static func receipt(in directory: URL) -> SingModelReceipt? {
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }),
            let data = try? Data(contentsOf: directory.appendingPathComponent(receiptName))
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SingModelReceipt.self, from: data)
    }

    static func encode(_ receipt: SingModelReceipt) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(receipt)
    }
}
