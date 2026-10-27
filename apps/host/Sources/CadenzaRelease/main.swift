import CadenzaSecurity
import CryptoKit
import Darwin
import Foundation

func fileDigest(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let chunk = try handle.read(upToCount: 262_144), !chunk.isEmpty { digest.update(data: chunk) }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
}

func keygen(_ path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
    )
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { throw ReleaseFailure.invalid("Choose a new private-key filename. Existing keys are never overwritten.") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    let key = P256.Signing.PrivateKey()
    try handle.write(contentsOf: Data(key.pemRepresentation.utf8))
    try handle.synchronize()
    try handle.close()
    print(key.publicKey.derRepresentation.base64EncodedString())
}

func manifest(_ arguments: [String]) throws {
    guard arguments.count == 9, let build = Int64(arguments[2]), build > 0,
          ReleaseValidation.validRepository(arguments[0]),
          arguments[1].range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else {
        throw ReleaseFailure.invalid("manifest requires repository, version, build, Host zip, Remote APK, private PEM, and output directory.")
    }
    let host = URL(fileURLWithPath: arguments[3])
    let remote = URL(fileURLWithPath: arguments[4])
    let privateKey = URL(fileURLWithPath: arguments[5])
    let output = URL(fileURLWithPath: arguments[6], isDirectory: true)
    let attributes = try FileManager.default.attributesOfItem(atPath: privateKey.path)
    guard let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
        throw ReleaseFailure.invalid("The private signing key must have mode 600.")
    }
    let key = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOf: privateKey, encoding: .utf8))
    let hostAsset = ReleaseAsset(
        platform: "macos-arm64", filename: "Cadenza-Host-\(arguments[1])-arm64.zip",
        sha256: try fileDigest(host), size: Int64(try host.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), minimumOS: 26
    )
    let remoteAsset = ReleaseAsset(
        platform: "android", filename: "Cadenza-Remote-\(arguments[1]).apk",
        sha256: try fileDigest(remote), size: Int64(try remote.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), minimumOS: 26
    )
    var release = ReleaseManifest(repository: arguments[0], version: arguments[1], build: build, assets: [hostAsset, remoteAsset])
    guard arguments[7].range(of: #"^([0-9a-f]{40}|source-[0-9a-f]{64})$"#, options: .regularExpression) != nil else {
        throw ReleaseFailure.invalid("Invalid source identity.")
    }
    struct History: Decodable { var releases: [ReleaseNote] }
    let historyData = try Data(contentsOf: URL(fileURLWithPath: arguments[8]))
    guard historyData.count <= 65_536 else { throw ReleaseFailure.invalid("Changelog exceeds its limit.") }
    release.buildId = arguments[7]
    release.changelog = try JSONDecoder().decode(History.self, from: historyData).releases.filter { $0.build <= build }
    let data = try ReleaseValidation.encode(release)
    let signature = try key.signature(for: data).derRepresentation
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try data.write(to: output.appendingPathComponent("cadenza-release.json"), options: .atomic)
    try signature.write(to: output.appendingPathComponent("cadenza-release.sig"), options: .atomic)
    print("Signed release metadata written to \(output.path)")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "keygen":
        guard arguments.count == 2 else { throw ReleaseFailure.invalid("keygen requires a new private PEM path.") }
        try keygen(arguments[1])
    case "manifest": try manifest(Array(arguments.dropFirst()))
    default: throw ReleaseFailure.invalid("Usage: CadenzaRelease keygen <private.pem> | manifest <repo> <version> <build> <Host.zip> <Remote.apk> <private.pem> <output> <source-id> <changelog.json>")
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
