import Foundation

// Apple's motion artwork is an HLS playlist whose rendition is one fragmented MP4. The Host keeps only that file, so the
// Remote plays a single local file and never reads Apple's playlist or segments.
enum MotionPlaylist {
    static let host = "mvod.itunes.apple.com"
    // A loop this size is enough for artwork on a phone or tablet and keeps the LAN transfer small.
    static let bitrateCeiling = 1_000_000

    /// The highest-bitrate H.264 rendition under the ceiling. H.264 decodes on every supported Remote.
    static func h264Rendition(_ master: String, base: URL) -> URL? {
        let lines = master.split(whereSeparator: \.isNewline).map(String.init)
        var best: (bandwidth: Int, url: URL)?
        for (index, line) in lines.enumerated()
        where line.hasPrefix("#EXT-X-STREAM-INF:") && line.contains("CODECS=\"avc1") {
            guard let bandwidth = bandwidth(of: line), bandwidth <= bitrateCeiling,
                index + 1 < lines.count,
                let url = secureURL(lines[index + 1], base: base)
            else { continue }
            if best.map({ $0.bandwidth < bandwidth }) ?? true { best = (bandwidth, url) }
        }
        return best?.url
    }

    // Only the exact BANDWIDTH attribute counts; AVERAGE-BANDWIDTH and _AVG-BANDWIDTH are different measurements.
    private static func bandwidth(of line: String) -> Int? {
        line.dropFirst("#EXT-X-STREAM-INF:".count).split(separator: ",").lazy.compactMap { field in
            field.hasPrefix("BANDWIDTH=") ? Int(field.dropFirst("BANDWIDTH=".count)) : nil
        }.first
    }

    /// The one file holding every segment of a finished rendition, or nil when segments are spread across files.
    static func mediaFile(_ playlist: String, base: URL) -> URL? {
        guard playlist.contains("#EXT-X-PLAYLIST-TYPE:VOD"), playlist.contains("#EXT-X-ENDLIST") else { return nil }
        let lines = playlist.split(whereSeparator: \.isNewline).map(String.init)
        guard let mapLine = lines.first(where: { $0.hasPrefix("#EXT-X-MAP:") }),
            let mapURI = mapLine.firstMatch(of: #/URI="([^"]+)"/#)?.1,
            let file = secureURL(String(mapURI), base: base)
        else { return nil }
        let segments = lines.filter { !$0.hasPrefix("#") && !$0.isEmpty }
        guard !segments.isEmpty, segments.allSatisfy({ secureURL($0, base: base) == file }) else { return nil }
        return file
    }

    static func isMP4(_ data: Data) -> Bool {
        data.dropFirst(4).prefix(4).elementsEqual("ftyp".utf8)
    }

    private static func secureURL(_ value: String, base: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL, url.scheme == "https", url.host == host
        else {
            return nil
        }
        return url
    }
}
