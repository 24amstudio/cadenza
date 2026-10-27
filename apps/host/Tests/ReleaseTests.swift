import CadenzaSecurity
import CryptoKit
import Foundation
import Testing

struct ReleaseTests {
    @Test func signedReleaseRejectsTamperingWrongRepositoryAndDowngrades() throws {
        let key = P256.Signing.PrivateKey()
        let asset = ReleaseAsset(
            platform: "macos-arm64", filename: "Cadenza-Host-0.2.0-arm64.zip",
            sha256: String(repeating: "a", count: 64), size: 100, minimumOS: 26
        )
        let manifest = ReleaseManifest(repository: "example/cadenza", version: "0.2.0", build: 2, assets: [asset])
        let data = try ReleaseValidation.encode(manifest)
        let signature = try key.signature(for: data).derRepresentation
        let verified = try ReleaseValidation.verify(
            manifest: data, signature: signature, publicKeySPKI: key.publicKey.derRepresentation,
            repository: "example/cadenza", currentBuild: 1, platform: "macos-arm64"
        )
        #expect(verified.0.build == 2)
        #expect(verified.1.filename == "Cadenza-Host-0.2.0-arm64.zip")
        #expect(throws: (any Error).self) {
            try ReleaseValidation.verify(
                manifest: data + Data(" ".utf8), signature: signature, publicKeySPKI: key.publicKey.derRepresentation,
                repository: "example/cadenza", currentBuild: 1, platform: "macos-arm64"
            )
        }
        #expect(throws: (any Error).self) {
            try ReleaseValidation.verify(
                manifest: data, signature: signature, publicKeySPKI: key.publicKey.derRepresentation,
                repository: "someone/else", currentBuild: 1, platform: "macos-arm64"
            )
        }
        #expect(throws: (any Error).self) {
            try ReleaseValidation.verify(
                manifest: data, signature: signature, publicKeySPKI: key.publicKey.derRepresentation,
                repository: "example/cadenza", currentBuild: 2, platform: "macos-arm64"
            )
        }
    }

    @Test func archiveRejectsTraversalLinksAndNonAppleSiliconExecutables() throws {
        try ArchiveInspection.validate(zip(name: "Cadenza Host.app/Contents/Info.plist", mode: 0x8000))
        #expect(throws: (any Error).self) {
            try ArchiveInspection.validate(zip(name: "Cadenza Host.app/../../outside", mode: 0x8000))
        }
        #expect(throws: (any Error).self) {
            try ArchiveInspection.validate(zip(name: "Cadenza Host.app/Contents/link", mode: 0xa000))
        }
        #expect(throws: (any Error).self) { try ArchiveInspection.validate(Data([0x50, 0x4b])) }
        var executable = Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1])
        executable.append(Data(repeating: 0, count: 24))
        try ArchiveInspection.validateExecutable(executable)
        executable[4] = 7
        #expect(throws: (any Error).self) { try ArchiveInspection.validateExecutable(executable) }
    }

    // Minimal ZIP fixture with an empty regular file. Values follow the ZIP record
    // layout; no extractor or application validation code is substituted.
    private func zip(name: String, mode: UInt32) -> Data {
        let name = Data(name.utf8)
        var result = Data()
        func short(_ value: UInt16) { result.append(contentsOf: [UInt8(value & 255), UInt8(value >> 8)]) }
        func word(_ value: UInt32) {
            short(UInt16(value & 65_535))
            short(UInt16(value >> 16))
        }
        word(0x0403_4b50)
        short(20)
        short(0)
        short(0)
        short(0)
        short(0)
        word(0)
        word(0)
        word(0)
        short(UInt16(name.count))
        short(0)
        result.append(name)
        let central = result.count
        word(0x0201_4b50)
        short(0x0314)
        short(20)
        short(0)
        short(0)
        short(0)
        short(0)
        word(0)
        word(0)
        word(0)
        short(UInt16(name.count))
        short(0)
        short(0)
        short(0)
        short(0)
        word(mode << 16)
        word(0)
        result.append(name)
        let length = result.count - central
        word(0x0605_4b50)
        short(0)
        short(0)
        short(1)
        short(1)
        word(UInt32(length))
        word(UInt32(central))
        short(0)
        return result
    }
}
