import CryptoKit
import Foundation

/// Verifies a downloaded archive, extracts it beside the installed model, and swaps it in only after every check passes.
/// A failed check leaves the installed model untouched.
enum SingModelInstaller {
    static func install(
        archive: URL, spec: SingModelSpec, location: SingModelLocation
    ) async throws -> SingModelReceipt {
        defer { try? FileManager.default.removeItem(at: archive) }
        try verify(archive, spec: spec)
        let listing = try await Subprocess.run("/usr/bin/tar", ["-tzf", archive.path], timeout: 60)
        try validateListing(String(decoding: listing, as: UTF8.self))

        let staging = location.stagingDirectory
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        _ = try await Subprocess.run("/usr/bin/tar", ["-xzf", archive.path, "-C", staging.path], timeout: 900)
        for file in SingModelLocation.files
        where !FileManager.default.fileExists(atPath: staging.appendingPathComponent(file).path) {
            throw CadenzaError.failure("sing_model", "The Sing model archive is missing \(file).")
        }

        let receipt = SingModelReceipt(
            version: spec.version, sha256: spec.sha256, sizeBytes: spec.sizeBytes, installedAt: Date())
        try SingModelLocation.encode(receipt).write(
            to: staging.appendingPathComponent(SingModelLocation.receiptName), options: .atomic)
        let installed = location.installedDirectory
        if FileManager.default.fileExists(atPath: installed.path) {
            _ = try FileManager.default.replaceItemAt(installed, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: installed)
        }
        return receipt
    }

    static func verify(_ archive: URL, spec: SingModelSpec) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == spec.sizeBytes else {
            throw CadenzaError.failure("sing_model", "The Sing model download is incomplete.")
        }
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == spec.sha256 else {
            throw CadenzaError.failure("sing_model", "The Sing model checksum does not match this release.")
        }
    }

    /// The archive may contain only the expected files, so it cannot write anywhere else in the model folder.
    static func validateListing(_ listing: String) throws {
        let names = listing.split(whereSeparator: \.isNewline).map { line -> String in
            line.hasPrefix("./") ? String(line.dropFirst(2)) : String(line)
        }
        guard names.count == SingModelLocation.files.count, Set(names) == Set(SingModelLocation.files) else {
            throw CadenzaError.failure("sing_model", "The Sing model archive has unexpected contents.")
        }
    }
}
