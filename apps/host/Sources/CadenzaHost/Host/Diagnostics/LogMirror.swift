import Foundation
import os

/// Mirrors Host log entries to os.Logger and to a rotating text file under Application Support. The file survives a
/// crash, and Export Diagnostic Logs copies it. Each line is written with one write call, so no buffered tail is lost
/// when the process dies. Logging stays best effort: a failed write never reaches the caller.
final class LogMirror: @unchecked Sendable {
    static let fileName = "cadenza-host.log"
    static let retainedGenerations = 3

    private static let osLog = Logger(subsystem: "app.cadence.host", category: "host")

    private let directory: URL
    private let maximumBytes: UInt64
    private let lock = NSLock()
    private var handle: FileHandle?
    private var bytes: UInt64 = 0

    init(directory: URL, maximumBytes: UInt64 = 2_000_000) throws {
        self.directory = directory
        self.maximumBytes = maximumBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lock.withLock { try openCurrent() }
    }

    deinit { try? handle?.close() }

    func record(_ entry: HostLogger.Entry) {
        let line = Self.line(for: entry)
        Self.osLog.log(level: Self.osLevel(entry.level), "\(line, privacy: .private)")
        lock.withLock { write(Data(line.utf8)) }
    }

    /// Every retained generation, oldest first, for Export Diagnostic Logs.
    func diagnosticsData() -> Data {
        lock.withLock {
            var combined = Data()
            for index in stride(from: Self.retainedGenerations - 1, through: 0, by: -1) {
                if let data = try? Data(contentsOf: url(generation: index)) { combined.append(data) }
            }
            return combined
        }
    }

    private func url(generation: Int) -> URL {
        generation == 0
            ? directory.appendingPathComponent(Self.fileName)
            : directory.appendingPathComponent("cadenza-host.\(generation).log")
    }

    private func openCurrent() throws {
        let url = url(generation: 0)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let file = try FileHandle(forWritingTo: url)
        bytes = try file.seekToEnd()
        handle = file
    }

    private func write(_ data: Data) {
        if bytes + UInt64(data.count) > maximumBytes { rotate() }
        guard let handle, (try? handle.write(contentsOf: data)) != nil else { return }
        bytes += UInt64(data.count)
    }

    /// Shifts every generation down by one and drops the oldest, so disk use stays bounded.
    private func rotate() {
        try? handle?.close()
        handle = nil
        let manager = FileManager.default
        try? manager.removeItem(at: url(generation: Self.retainedGenerations - 1))
        for index in stride(from: Self.retainedGenerations - 2, through: 0, by: -1) {
            let source = url(generation: index)
            guard manager.fileExists(atPath: source.path) else { continue }
            try? manager.moveItem(at: source, to: url(generation: index + 1))
        }
        try? openCurrent()
        bytes = 0
    }

    private static func line(for entry: HostLogger.Entry) -> String {
        let time = Date(timeIntervalSince1970: Double(entry.createdAtMs) / 1_000).formatted(.iso8601)
        let metadata = entry.metadataJSON.map { " " + $0 } ?? ""
        return "\(time) \(entry.level.rawValue) [\(entry.category)] \(entry.action) \(entry.message)\(metadata)\n"
    }

    private static func osLevel(_ level: HostLogLevel) -> OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}
