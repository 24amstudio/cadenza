import Foundation

@MainActor
final class HostCache: Sendable {
    private let database: Database
    private let mediaDirectory: URL
    private var limitBytes: Int64

    init(database: Database, mediaDirectory: URL, limitBytes: Int64) throws {
        self.database = database
        self.mediaDirectory = mediaDirectory
        self.limitBytes = Self.clamp(limitBytes)
        try FileManager.default.createDirectory(
            at: mediaDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try repair()
        try evictIfNeeded()
    }

    func setLimit(_ bytes: Int64) throws {
        limitBytes = Self.clamp(bytes)
        try evictIfNeeded()
    }

    func data(for key: String) throws -> Data? {
        let hashed = Self.key(key)
        guard
            let row = try database.query(
                "SELECT payload,file_path FROM cache_entries WHERE cache_key=?", [.text(hashed)]
            ).first
        else { return nil }
        let data: Data?
        if let payload = row["payload"]?.string {
            data = Data(payload.utf8)
        } else if let path = row["file_path"]?.string {
            data = try? Data(contentsOf: mediaDirectory.appendingPathComponent(path))
        } else {
            data = nil
        }
        guard let data else {
            try removeEntry(hashed, filePath: row["file_path"]?.string)
            return nil
        }
        try database.run(
            "UPDATE cache_entries SET accessed_at_ms=? WHERE cache_key=?", [.integer(wallMs()), .text(hashed)])
        return data
    }

    func put(_ data: Data, for key: String, kind: String) throws {
        guard ["lyrics", "artwork", "animated_artwork", "provider"].contains(kind),
            data.count <= Int(limitBytes)
        else { return }
        let hashed = Self.key(key)
        let isMedia = kind == "artwork" || kind == "animated_artwork"
        guard isMedia || String(data: data, encoding: .utf8) != nil else { return }
        let filename = isMedia ? hashed + ".media" : nil
        if let filename {
            let temporary = mediaDirectory.appendingPathComponent(filename + ".part-" + identifier())
            try data.write(to: temporary, options: [.atomic])
            let destination = mediaDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        }
        try database.transaction {
            try database.run("DELETE FROM cache_entries WHERE cache_key=?", [.text(hashed)])
            try database.run(
                "INSERT INTO cache_entries(cache_key,kind,payload,file_path,byte_count,accessed_at_ms) VALUES(?,?,?,?,?,?)",
                [
                    .text(hashed), .text(kind), isMedia ? .null : .text(String(decoding: data, as: UTF8.self)),
                    filename.map(SQLValue.text) ?? .null,
                    .integer(Int64(data.count)), .integer(wallMs()),
                ])
            try evictIfNeeded()
        }
    }

    func remove(_ key: String) throws {
        let hashed = Self.key(key)
        let row = try database.query(
            "SELECT file_path FROM cache_entries WHERE cache_key=?", [.text(hashed)]
        ).first
        try removeEntry(hashed, filePath: row?["file_path"]?.string)
    }

    func removeAll() throws {
        try database.run("DELETE FROM cache_entries")
        for url in try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stats() throws -> HostCacheStats {
        let row = try database.query(
            "SELECT count(*) AS entries, coalesce(sum(byte_count),0) AS bytes FROM cache_entries"
        ).first
        return HostCacheStats(
            bytes: row?["bytes"]?.integer ?? 0, entries: Int(row?["entries"]?.integer ?? 0), limitBytes: limitBytes)
    }

    private func evictIfNeeded() throws {
        while try stats().bytes > limitBytes {
            guard
                let row = try database.query(
                    """
                    SELECT cache_key,file_path FROM cache_entries
                    ORDER BY CASE kind
                        WHEN 'artwork' THEN 0
                        WHEN 'animated_artwork' THEN 0
                        WHEN 'provider' THEN 1
                        ELSE 2
                    END, accessed_at_ms ASC LIMIT 1
                    """
                ).first,
                let key = row["cache_key"]?.string
            else { return }
            try removeEntry(key, filePath: row["file_path"]?.string)
        }
    }

    private func repair() throws {
        let rows = try database.query("SELECT cache_key,file_path FROM cache_entries WHERE file_path IS NOT NULL")
        var referenced = Set<String>()
        for row in rows {
            guard let key = row["cache_key"]?.string, let path = row["file_path"]?.string else { continue }
            referenced.insert(path)
            if !FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent(path).path) {
                try removeEntry(key, filePath: path)
            }
        }
        for url in try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil)
        where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeEntry(_ key: String, filePath: String?) throws {
        if let filePath { try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(filePath)) }
        try database.run("DELETE FROM cache_entries WHERE cache_key=?", [.text(key)])
    }

    private static func clamp(_ bytes: Int64) -> Int64 { min(max(bytes, 64 * 1_048_576), 1_024 * 1_048_576) }

    private static func key(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
