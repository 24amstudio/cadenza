import CSQLite
import Foundation

@MainActor
final class Database {
    private var handle: OpaquePointer?
    let url: URL
    let wasCreated: Bool

    init(url: URL, role: DatabaseRole = .main) throws {
        self.url = url
        wasCreated = !FileManager.default.fileExists(atPath: url.path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard
            sqlite3_open_v2(
                url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
            ) == SQLITE_OK
        else { throw failure() }
        do {
            try execute("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=250;")
            let version = try query("PRAGMA user_version").first?["user_version"]?.integer ?? 0
            if role == .main {
                if version == 0 { try migrate("main/000-initial") }
            } else if role == .logs {
                if version == 0 { try migrate("system/000-initial") }
            }
            let expectedVersion: Int64 = 1
            guard try query("PRAGMA user_version").first?["user_version"]?.integer == expectedVersion else {
                throw CadenzaError.failure("database_version", "The database needs a newer Cadenza Host.")
            }
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
            guard try query("PRAGMA integrity_check").first?["integrity_check"]?.string == "ok" else {
                throw CadenzaError.failure("database_corrupt", "Cadenza Host storage failed its integrity check.")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? execute("ROLLBACK")
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    isolated deinit { sqlite3_close(handle) }

    private func failure() -> CadenzaError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open SQLite."
        return .failure("storage", message)
    }

    private func migrate(_ name: String) throws {
        let components = name.split(separator: "/", omittingEmptySubsequences: true)
        let file = components.last.map(String.init) ?? name
        let folder = components.dropLast().joined(separator: "/")
        guard let url = HostResources.bundle.url(
            forResource: file, withExtension: "sql", subdirectory: "storage/" + folder)
        else {
            throw CadenzaError.failure("storage", "The database migration is missing from this build.")
        }
        try execute(String(contentsOf: url, encoding: .utf8))
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    @discardableResult
    func run(_ sql: String, _ bindings: [SQLValue] = []) throws -> Int {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ bindings: [SQLValue] = []) throws -> [SQLRow] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        return try rows(statement)
    }

    func query(_ sql: String, named bindings: [String: SQLValue]) throws -> [SQLRow] {
        let statement = try prepare(sql, [])
        defer { sqlite3_finalize(statement) }
        let count = sqlite3_bind_parameter_count(statement)
        if count > 0 {
            for index in 1...count {
                guard let pointer = sqlite3_bind_parameter_name(statement, index),
                    let value = bindings[String(cString: pointer).dropFirst().description]
                else {
                    throw CadenzaError.failure("storage", "A database parameter is missing.")
                }
                try bind(value, to: index, in: statement)
            }
        }
        return try rows(statement)
    }

    private func rows(_ statement: OpaquePointer) throws -> [SQLRow] {
        var rows: [SQLRow] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw failure() }
            var row: SQLRow = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_NULL: row[name] = .null
                default:
                    if let value = sqlite3_column_text(statement, index) {
                        row[name] = .text(String(cString: value))
                    }
                }
            }
            rows.append(row)
        }
    }

    private func prepare(_ sql: String, _ bindings: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else { throw failure() }
        for (offset, binding) in bindings.enumerated() {
            do { try bind(binding, to: Int32(offset + 1), in: statement) } catch {
                sqlite3_finalize(statement)
                throw error
            }
        }
        return statement
    }

    private func bind(_ value: SQLValue, to index: Int32, in statement: OpaquePointer) throws {
        let status: Int32
        switch value {
        case .text(let text):
            // SQLITE_TRANSIENT copies the string before its temporary buffer expires.
            status = sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case .integer(let integer): status = sqlite3_bind_int64(statement, index, integer)
        case .null: status = sqlite3_bind_null(statement, index)
        }
        guard status == SQLITE_OK else { throw failure() }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func backup(to destination: URL) throws {
        var copy: OpaquePointer?
        guard sqlite3_open(destination.path, &copy) == SQLITE_OK else {
            sqlite3_close(copy)
            throw CadenzaError.failure("backup", "Cannot open the database backup.")
        }
        defer { sqlite3_close(copy) }
        guard let backup = sqlite3_backup_init(copy, "main", handle, "main") else { throw failure() }
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE && finish == SQLITE_OK else { throw failure() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    func maintain() throws {
        guard
            let url = HostResources.bundle.url(
                forResource: "maintenance", withExtension: "sql", subdirectory: "storage")
        else {
            throw CadenzaError.failure("storage", "The database maintenance script is missing.")
        }
        do { try execute(String(contentsOf: url, encoding: .utf8)) } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
