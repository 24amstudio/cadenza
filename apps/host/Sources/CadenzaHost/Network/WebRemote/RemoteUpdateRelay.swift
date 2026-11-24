import Foundation

/// The HTTP answer the relay hands to a session. Headers are raw `Name: value` lines.
struct RemoteUpdateReply: Equatable {
    var status: Int
    var contentType: String?
    var headers: [String] = []
    var body: [UInt8] = []
}

/// Serves the cached Remote APK to paired Remotes on the LAN. A request must carry a paired Remote's id and token, the
/// same credentials the Remote uses on its control socket. Downloads go out in bounded ranges, so memory stays flat.
@MainActor
struct RemoteUpdateRelay {
    static let rangeLimit: Int64 = 8 * 1024 * 1024
    static let apkContentType = "application/vnd.android.package-archive"

    let current: () -> RemoteUpdateCache.Current?
    let authorize: (DeviceAuth) -> Bool

    func reply(to request: WebRemoteRequest) -> RemoteUpdateReply {
        let path = String(
            request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        guard let remoteId = request.headers["x-cadenza-remote-id"],
            let token = request.headers["x-cadenza-remote-token"],
            authorize(DeviceAuth(remoteId: remoteId, token: token, lastCreditSequence: 0))
        else {
            return RemoteUpdateReply(status: 401)
        }
        guard let current = current() else { return RemoteUpdateReply(status: 404) }
        switch path {
        case RemoteUpdateCache.manifestPath:
            return manifest(current.artifact)
        case RemoteUpdateCache.downloadPath:
            return apk(current, range: request.headers["range"])
        default:
            return RemoteUpdateReply(status: 404)
        }
    }

    private func manifest(_ artifact: RemoteUpdateCache.Artifact) -> RemoteUpdateReply {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let body = try? encoder.encode(RemoteUpdateCache.Offer(artifact: artifact)) else {
            return RemoteUpdateReply(status: 500)
        }
        return RemoteUpdateReply(status: 200, contentType: "application/json", body: [UInt8](body))
    }

    private func apk(_ current: RemoteUpdateCache.Current, range header: String?) -> RemoteUpdateReply {
        let size = current.artifact.sizeBytes
        let common = ["Accept-Ranges: bytes", "X-Cadenza-SHA256: \(current.artifact.sha256)"]
        switch ByteRange.parse(header, size: size) {
        case .unsatisfiable:
            return RemoteUpdateReply(
                status: 416, contentType: nil, headers: common + ["Content-Range: bytes */\(size)"])
        case .full:
            guard let bytes = Self.read(current.file, from: 0, count: Int(size)) else {
                return RemoteUpdateReply(status: 500)
            }
            return RemoteUpdateReply(status: 200, contentType: Self.apkContentType, headers: common, body: bytes)
        case .partial(let range):
            let end = min(range.upperBound, range.lowerBound + Self.rangeLimit - 1)
            guard let bytes = Self.read(current.file, from: range.lowerBound, count: Int(end - range.lowerBound + 1))
            else { return RemoteUpdateReply(status: 500) }
            return RemoteUpdateReply(
                status: 206, contentType: Self.apkContentType,
                headers: common + ["Content-Range: bytes \(range.lowerBound)-\(end)/\(size)"], body: bytes)
        }
    }

    private static func read(_ file: URL, from offset: Int64, count: Int) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return [UInt8](try handle.read(upToCount: count) ?? Data())
        } catch {
            return nil
        }
    }
}
