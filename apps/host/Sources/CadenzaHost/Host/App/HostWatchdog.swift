import Foundation

/// Leaves the running marker behind so a separate process can record and recover an
/// unclean Host exit. The watchdog never receives credentials or audio data.
@MainActor
final class HostWatchdog {
    private struct Marker: Codable {
        var pid: Int32
        var startedAtMs: Int64
        var clean: Bool
    }

    private let markerURL: URL
    private var process: Process?
    private var heartbeat: Task<Void, Never>?

    init() throws {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Cadence Host", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        markerURL = directory.appendingPathComponent("host-watchdog.json")
    }

    func start() {
        heartbeat?.cancel()
        write(clean: false)
        launch()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.write(clean: false)
            }
        }
    }

    func markCleanShutdown() {
        heartbeat?.cancel()
        heartbeat = nil
        write(clean: true)
    }

    private func launch() {
        guard process == nil else { return }
        let hostURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let watchdogURL = hostURL.deletingLastPathComponent().appendingPathComponent("CadenzaWatchdog")
        guard FileManager.default.isExecutableFile(atPath: watchdogURL.path) else { return }
        let database = markerURL.deletingLastPathComponent().appendingPathComponent("database/logs.sqlite")
        let child = Process()
        child.executableURL = watchdogURL
        child.arguments = [
            "--host", hostURL.path,
            "--database", database.path,
            "--marker", markerURL.path,
        ]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
            process = child
        } catch {
            process = nil
        }
    }

    private func write(clean: Bool) {
        let marker = Marker(pid: ProcessInfo.processInfo.processIdentifier, startedAtMs: wallMs(), clean: clean)
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: markerURL, options: .atomic)
    }
}
