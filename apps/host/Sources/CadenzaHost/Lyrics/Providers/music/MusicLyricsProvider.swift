import Foundation

struct MusicLyricsProvider: LyricsProvider {
    let id = "music"

    func document(song: Song, occurrence: String) async throws -> LyricDocument? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.apple.Music/fsCachedData", isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let candidates: ArraySlice<URL>
        if let listed = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) {
            // Prefer the newest cache entries and keep this read small enough
            // that an unavailable Music cache does not block LRCLIB fallback.
            candidates = listed.sorted { left, right in
                let leftDate =
                    (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let rightDate =
                    (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return leftDate > rightDate
            }.prefix(512)
        } else {
            candidates = [URL]().prefix(0)
        }
        let files = candidates.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true, values.isSymbolicLink != true,
                let size = values.fileSize, size <= 4_194_304
            else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 > $1.2 }
        var bytes = 0
        for (url, size, _) in files {
            bytes += size
            if bytes > 8_388_608 { break }
            guard var data = try? Data(contentsOf: url) else { continue }
            while data.last == 0 { data.removeLast() }
            guard data.range(of: Data("ttmlLocalizations".utf8)) != nil,
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = root["data"] as? [[String: Any]]
            else { continue }
            for item in items where matches(item, song: song) {
                guard let relationships = item["relationships"] as? [String: Any] else { continue }
                for kind in ["syllable-lyrics", "lyrics"] {
                    guard let relationship = relationships[kind] as? [String: Any],
                        let records = relationship["data"] as? [[String: Any]],
                        let attributes = records.first?["attributes"] as? [String: Any],
                        let ttml = attributes["ttmlLocalizations"] as? String
                    else { continue }
                    return try TTMLDocument.parse(Data(ttml.utf8), occurrence: occurrence)
                }
            }
        }
        return nil
    }

    private func matches(_ item: [String: Any], song: Song) -> Bool {
        if song.source == "catalog" { return item["id"] as? String == song.id }
        guard let attributes = item["attributes"] as? [String: Any],
            attributes["name"] as? String == song.title,
            attributes["artistName"] as? String == song.artist,
            attributes["albumName"] as? String == song.album,
            let duration = (attributes["durationInMillis"] as? NSNumber)?.int64Value,
            let expected = song.durationMs, abs(duration - expected) < 1_000
        else { return false }
        return true
    }
}
