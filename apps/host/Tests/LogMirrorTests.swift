import Foundation
import Testing

@testable import CadenzaHost

struct LogMirrorTests {
    private func entry(_ index: Int) -> HostLogger.Entry {
        HostLogger.Entry(
            createdAtMs: 1_700_000_000_000 + Int64(index), unixTimestamp: 1_700_000_000, remoteVersion: nil,
            source: "host", action: "test.entry", level: .info, category: "test",
            message: "entry \(index) " + String(repeating: "x", count: 60), metadataJSON: nil)
    }

    @Test func rotationBoundsDiskUseAndExportKeepsTheNewestEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogMirrorTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mirror = try LogMirror(directory: directory, maximumBytes: 400)

        for index in 0..<20 {
            mirror.record(entry(index))
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == LogMirror.retainedGenerations)
        let exported = String(decoding: mirror.diagnosticsData(), as: UTF8.self)
        #expect(exported.contains("entry 19 "))
        #expect(!exported.contains("entry 0 "))
    }
}
