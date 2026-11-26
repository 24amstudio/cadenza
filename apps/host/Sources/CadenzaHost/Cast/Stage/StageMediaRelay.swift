import Foundation

/// The media paths that stage receivers request. Suite IDs are opaque hex, so no catalog identity reaches a receiver.
enum StageMediaPath: Equatable {
    case artwork(suiteId: String)
    case motion(suiteId: String)
    case lyrics(suiteId: String)
    case video(suiteId: String)

    init?(_ requestPath: String) {
        let path = requestPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5, parts[0].isEmpty, parts[1] == "api", parts[2] == "v1", parts[3] == "cast" else {
            return nil
        }
        let kind = parts[4]
        switch (kind, parts.count) {
        case ("artwork", 6), ("motion", 6):
            let name = parts[5]
            guard let id = Self.suiteId(from: name, suffix: kind == "artwork" ? ".jpg" : ".mp4") else { return nil }
            self = kind == "artwork" ? .artwork(suiteId: id) : .motion(suiteId: id)
        case ("video", 7):
            guard Self.isSuiteId(parts[5]) else { return nil }
            switch parts[6] {
            case "lyrics.vtt": self = .lyrics(suiteId: parts[5])
            case "video.mp4": self = .video(suiteId: parts[5])
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func suiteId(from name: String, suffix: String) -> String? {
        guard name.hasSuffix(suffix) else { return nil }
        let id = String(name.dropLast(suffix.count))
        return isSuiteId(id) ? id : nil
    }

    static func isSuiteId(_ value: String) -> Bool {
        value.count == 24 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

/// Serves stage media from the suite store. Video is read in bounded ranges, so a request never loads a whole file.
@MainActor
struct StageMediaRelay {
    static let maximumRangeBytes: Int64 = 8 * 1024 * 1024

    let store: StageSuiteStore

    func reply(to path: String, rangeHeader: String?) -> WebRemoteReply? {
        guard let media = StageMediaPath(path) else { return nil }
        switch media {
        case .artwork(let id):
            guard let data = store.entry(id)?.artwork else { return missing() }
            return bytes(data, contentType: data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg")
        case .motion(let id):
            guard let data = store.entry(id)?.motion else { return missing() }
            return bytes(data, contentType: "video/mp4")
        case .lyrics(let id):
            guard let text = store.lyricsText(for: id) else { return missing() }
            return bytes(Data(text.utf8), contentType: "text/vtt; charset=utf-8")
        case .video(let id):
            guard let url = store.entry(id)?.videoFile else { return missing() }
            return video(at: url, rangeHeader: rangeHeader)
        }
    }

    private func missing() -> WebRemoteReply {
        WebRemoteReply(status: 404)
    }

    private func bytes(_ data: Data, contentType: String) -> WebRemoteReply {
        WebRemoteReply(status: 200, contentType: contentType, headers: ["Accept-Ranges: none"], body: [UInt8](data))
    }

    private func video(at url: URL, rangeHeader: String?) -> WebRemoteReply {
        guard let handle = try? FileHandle(forReadingFrom: url), let size = try? handle.seekToEnd() else {
            return missing()
        }
        defer { try? handle.close() }
        let total = Int64(size)
        let headers = ["Accept-Ranges: bytes"]
        switch ByteRange.parse(rangeHeader, size: total) {
        case .unsatisfiable:
            return WebRemoteReply(status: 416, headers: headers + ["Content-Range: bytes */\(total)"])
        case .full where total <= Self.maximumRangeBytes:
            return read(handle, from: 0, through: total - 1, total: total, status: 200, headers: headers)
        case .full:
            return read(
                handle, from: 0, through: Self.maximumRangeBytes - 1, total: total, status: 206, headers: headers)
        case .partial(let range):
            let end = min(range.upperBound, range.lowerBound + Self.maximumRangeBytes - 1)
            return read(handle, from: range.lowerBound, through: end, total: total, status: 206, headers: headers)
        }
    }

    private func read(
        _ handle: FileHandle, from start: Int64, through end: Int64, total: Int64, status: Int, headers: [String]
    ) -> WebRemoteReply {
        do {
            try handle.seek(toOffset: UInt64(start))
            let data = try handle.read(upToCount: Int(end - start + 1)) ?? Data()
            var extra = headers + ["Content-Length: \(data.count)"]
            if status == 206 { extra.append("Content-Range: bytes \(start)-\(start + Int64(data.count) - 1)/\(total)") }
            return WebRemoteReply(status: status, contentType: "video/mp4", headers: extra, body: [UInt8](data))
        } catch {
            return missing()
        }
    }
}
