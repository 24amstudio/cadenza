import CSQLite
import Darwin
import Foundation

private struct WatchdogArguments {
    let host: String
    let database: String
    let marker: String

    init() throws {
        let values = CommandLine.arguments
        guard values.count == 7,
            values[1] == "--host", values[3] == "--database", values[5] == "--marker"
        else { throw WatchdogError.invalidArguments }
        host = values[2]
        database = values[4]
        marker = values[6]
    }
}

private enum WatchdogError: LocalizedError {
    case invalidArguments
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "Invalid watchdog arguments."
        case .launchFailed: return "Cadenza Host could not be relaunched."
        }
    }
}

private struct Marker: Codable {
    let pid: Int32
    let startedAtMs: Int64
    let clean: Bool
}

private final class Watchdog {
    private let arguments: WatchdogArguments
    private let maxRestarts = 3
    private let restartWindowMs: Int64 = 60_000
    private var restarts: [Int64] = []

    init(arguments: WatchdogArguments) { self.arguments = arguments }

    func run() throws {
        while true {
            guard let marker = readMarker() else { return }
            while processExists(marker.pid) {
                Thread.sleep(forTimeInterval: 1)
                if let current = readMarker(), current.pid != marker.pid { break }
            }
            guard let stopped = readMarker(), stopped.pid == marker.pid, !stopped.clean else { return }
            let now = wallMs()
            restarts = restarts.filter { now - $0 < restartWindowMs }
            guard restarts.count < maxRestarts else {
                writeCrashLog(reason: "Host exited repeatedly; automatic restart limit reached.")
                return
            }
            writeCrashLog(reason: "Host exited unexpectedly before writing a clean shutdown record.")
            restarts.append(now)
            try launchHost()
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func launchHost() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments.host)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw WatchdogError.launchFailed }
    }

    private func readMarker() -> Marker? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: arguments.marker)) else { return nil }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }

    private func processExists(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    private func writeCrashLog(reason: String) {
        var handle: OpaquePointer?
        guard
            sqlite3_open_v2(
                arguments.database,
                &handle,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK,
            let handle
        else { return }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 2_000)
        let lastAction = latestAction(handle) ?? "unknown"
        let sql =
            "INSERT INTO system_logs(created_at_ms,unix_timestamp,host_version,remote_version,source,action,level,category,message,metadata_json) "
            + "VALUES(?,?,?,?,?,?,?,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        let now = wallMs()
        sqlite3_bind_int64(statement, 1, now)
        sqlite3_bind_int64(statement, 2, now / 1_000)
        bindText(statement, 3, "watchdog")
        sqlite3_bind_null(statement, 4)
        bindText(statement, 5, "host")
        bindText(statement, 6, "host.crash.detected")
        bindText(statement, 7, "error")
        bindText(statement, 8, "host.lifecycle")
        bindText(statement, 9, reason + " Last durable action: " + lastAction + ".")
        let safeAction = lastAction.replacingOccurrences(of: "\"", with: "'")
        bindText(
            statement, 10,
            "{\"source\":\"CadenzaWatchdog\",\"recovery\":\"automatic_restart\",\"last_action\":\"\(safeAction)\"}"
        )
        _ = sqlite3_step(statement)
    }

    private func latestAction(_ handle: OpaquePointer) -> String? {
        let sql = "SELECT action FROM system_logs WHERE action!='host.crash.detected' ORDER BY id DESC LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
}

private func wallMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

do {
    try Watchdog(arguments: WatchdogArguments()).run()
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(2)
}
