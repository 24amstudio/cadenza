import CadenzaSecurity
import Darwin
import Foundation

func run(_ executable: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ReleaseFailure.invalid("The update system command failed.") }
    return data
}

func install(_ request: InstallRequest) throws {
    let manager = FileManager.default
    let application = URL(fileURLWithPath: request.applicationPath).standardizedFileURL
    let archive = URL(fileURLWithPath: request.archivePath).standardizedFileURL
    guard application.pathExtension == "app",
        ["Cadenza Host.app", "Cadence Host.app"].contains(application.lastPathComponent),
        application.path != "/", request.parentPid > 1,
        try application.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
        Bundle(url: application)?.bundleIdentifier == "app.cadence.host",
        let key = Data(base64Encoded: request.publicKeySpkiBase64)
    else {
        throw ReleaseFailure.invalid("Invalid update target or verification identity.")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: request.manifestPath))
    let signature = try Data(contentsOf: URL(fileURLWithPath: request.signaturePath))
    let (manifest, asset) = try ReleaseValidation.verify(
        manifest: data, signature: signature, publicKeySPKI: key, repository: request.repository,
        currentBuild: request.currentBuild, platform: "macos-arm64"
    )
    try ReleaseValidation.verifyFile(archive, asset: asset)
    try ArchiveInspection.validate(Data(contentsOf: archive, options: .mappedIfSafe))
    let stage = application.deletingLastPathComponent().appendingPathComponent(".cadenza-update-\(UUID().uuidString)")
    try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? manager.removeItem(at: stage) }
    _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, stage.path])
    let replacement = stage.appendingPathComponent("Cadenza Host.app")
    let contents = manager.enumerator(at: replacement, includingPropertiesForKeys: [.isSymbolicLinkKey])
    while let file = contents?.nextObject() as? URL {
        if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw ReleaseFailure.invalid("Symbolic links are not allowed in this native update archive.")
        }
    }
    guard let bundle = Bundle(url: replacement), bundle.bundleIdentifier == "app.cadence.host",
        Int64(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") == manifest.build
    else {
        throw ReleaseFailure.invalid("The app identity or build differs from the signed manifest.")
    }
    _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", replacement.path])
    let executable = replacement.appendingPathComponent("Contents/MacOS/CadenzaHost")
    let handle = try FileHandle(forReadingFrom: executable)
    defer { try? handle.close() }
    try ArchiveInspection.validateExecutable(handle.read(upToCount: 32) ?? Data())
    for _ in 0..<100 {
        if kill(request.parentPid, 0) != 0 { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard kill(request.parentPid, 0) != 0 else { throw ReleaseFailure.invalid("Cadenza Host did not exit in time.") }
    let backup = ".Cadenza-Host-previous-\(UUID().uuidString).app"
    let backupURL = application.deletingLastPathComponent().appendingPathComponent(backup)
    do {
        _ = try manager.replaceItemAt(
            application, withItemAt: replacement, backupItemName: backup, options: .withoutDeletingBackupItem)
        try Data(#"{"success":true}"#.utf8).write(to: URL(fileURLWithPath: request.resultPath), options: .atomic)
        _ = try run("/usr/bin/open", [application.path])
        try? manager.removeItem(at: backupURL)
    } catch {
        if manager.fileExists(atPath: backupURL.path) {
            if manager.fileExists(atPath: application.path) {
                _ = try? manager.replaceItemAt(application, withItemAt: backupURL)
            } else {
                try? manager.moveItem(at: backupURL, to: application)
            }
        }
        throw error
    }
}

let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
do {
    guard CommandLine.arguments.count == 2 else { throw ReleaseFailure.invalid("An installation request is required.") }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let request = try decoder.decode(InstallRequest.self, from: Data(contentsOf: url))
    do {
        try install(request)
    } catch {
        let result = try JSONSerialization.data(withJSONObject: [
            "success": false, "message": error.localizedDescription,
        ])
        try? result.write(to: URL(fileURLWithPath: request.resultPath), options: .atomic)
        _ = try? run("/usr/bin/open", [request.applicationPath])
        throw error
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
