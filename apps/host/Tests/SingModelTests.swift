import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import CadenzaHost

@MainActor
struct SingModelTests {
    private let currentSha = String(repeating: "a", count: 64)
    private let oldSha = String(repeating: "b", count: 64)

    private func workspace() throws -> SingModelLocation {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadenza-sing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return SingModelLocation(modelsDirectory: root)
    }

    private func spec(sha: String, bytes: Int64 = 1) -> SingModelSpec {
        SingModelSpec(
            version: "kim-test", sha256: sha, sizeBytes: bytes,
            url: URL(string: "https://github.com/example/cadenza/releases/download/v0.3.4/model.tar.gz"))
    }

    private func installModel(_ location: SingModelLocation, version: String, sha: String) throws {
        let directory = location.installedDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in SingModelLocation.files {
            try Data("placeholder".utf8).write(to: directory.appendingPathComponent(file))
        }
        let receipt = SingModelReceipt(version: version, sha256: sha, sizeBytes: 1, installedAt: Date())
        try SingModelLocation.encode(receipt).write(
            to: directory.appendingPathComponent(SingModelLocation.receiptName))
    }

    @Test func aModelThatWasNeverInstalledStaysIdleAndDownloadsNothing() throws {
        let fetches = Mutex(0)
        let manager = SingModelManager(
            spec: spec(sha: currentSha), location: try workspace(),
            fetch: { _, _ in
                fetches.withLock { $0 += 1 }
                throw CancellationError()
            })

        manager.reconcileOnLaunch()

        #expect(manager.state == .notInstalled)
        #expect(fetches.withLock { $0 } == 0)
    }

    @Test func aReceiptThatMatchesThisBuildIsReadyWithoutADownload() throws {
        let location = try workspace()
        try installModel(location, version: "kim-test", sha: currentSha)
        let manager = SingModelManager(
            spec: spec(sha: currentSha), location: location, fetch: { _, _ in throw CancellationError() })

        manager.reconcileOnLaunch()

        #expect(manager.state == .ready(version: "kim-test", sizeBytes: 1))
    }

    @Test func anOutdatedReceiptIsReplacedSilentlyInTheBackground() throws {
        let location = try workspace()
        try installModel(location, version: "kim-old", sha: oldSha)
        let manager = SingModelManager(
            spec: spec(sha: currentSha), location: location, fetch: { _, _ in throw CancellationError() })

        manager.reconcileOnLaunch()

        #expect(manager.state == .downloading(progress: 0, isAutoUpdate: true))
        manager.cancel()
    }

    @Test func aChecksumMismatchNeverReplacesTheInstalledModel() async throws {
        let location = try workspace()
        try installModel(location, version: "kim-old", sha: oldSha)
        let archive = location.modelsDirectory.appendingPathComponent("download.tar.gz")
        try Data("not the model".utf8).write(to: archive)

        await #expect(throws: (any Error).self) {
            try await SingModelInstaller.install(
                archive: archive, spec: spec(sha: currentSha, bytes: 12), location: location)
        }
        #expect(location.installedReceipt()?.version == "kim-old")
    }

    @Test func aVerifiedArchiveReplacesTheModelAndWritesItsReceipt() async throws {
        let location = try workspace()
        let source = try workspace().modelsDirectory
        for file in SingModelLocation.files {
            try Data("payload-\(file)".utf8).write(to: source.appendingPathComponent(file))
        }
        let archive = source.deletingLastPathComponent().appendingPathComponent("model.tar.gz")
        try tar(["-czf", archive.path, "-C", source.path] + SingModelLocation.files)
        let data = try Data(contentsOf: archive)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let receipt = try await SingModelInstaller.install(
            archive: archive, spec: spec(sha: sha, bytes: Int64(data.count)), location: location)

        #expect(receipt.version == "kim-test")
        #expect(location.installedReceipt()?.sha256 == sha)
    }

    @Test func anArchiveMayHoldOnlyTheExpectedFiles() throws {
        try SingModelInstaller.validateListing("./model.safetensors\nconfig.json\nLICENSE\n")
        #expect(throws: (any Error).self) {
            try SingModelInstaller.validateListing("model.safetensors\nconfig.json\nLICENSE\nsecret.txt\n")
        }
        #expect(throws: (any Error).self) {
            try SingModelInstaller.validateListing("../model.safetensors\nconfig.json\nLICENSE\n")
        }
    }

    private func tar(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
