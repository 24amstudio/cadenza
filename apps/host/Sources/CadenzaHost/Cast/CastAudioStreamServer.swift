import Foundation
import Network

/// The codec of one Cast audio stream. AAC is the stereo path, and AC-3 carries six-channel output.
enum CastAudioCodec: Sendable, Equatable {
    case aac, ac3

    /// Stereo always takes AAC, and six channels take AC-3. Other channel counts have no Cast route.
    static func forChannelCount(_ channels: Int) -> CastAudioCodec? {
        switch channels {
        case 2: .aac
        case 6: .ac3
        default: nil
        }
    }

    var path: String {
        switch self {
        case .aac: return "/cast/audio.aac"
        case .ac3: return "/cast/audio.ac3"
        }
    }
    var contentType: String {
        switch self {
        case .aac: return "audio/aac"
        case .ac3: return "audio/ac3"
        }
    }
}

/// Serves live chunked Cast audio and optional LAN media assets (byte-range DRM-free `.mp4`/`.m4v` files, still
/// artwork, and motion artwork loops) to the Cast receiver.
final class CastAudioStreamServer: @unchecked Sendable {
    private let codec: CastAudioCodec
    private var head: String {
        "HTTP/1.1 200 OK\r\nContent-Type: \(codec.contentType)\r\nTransfer-Encoding: chunked\r\n"
            + "Access-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
    }

    init(codec: CastAudioCodec) {
        self.codec = codec
    }

    private let queue = DispatchQueue(label: "app.cadenza.host.cast.stream")
    private var listener: NWListener?
    private var receivers: [ObjectIdentifier: NWConnection] = [:]
    private(set) var port: UInt16 = 0
    private var localVideoFile: URL?
    private var subtitles: String?
    private var artworkBytes: Data?
    private var motionBytes: Data?

    /// Starts listening on an ephemeral port and returns it once the listener is ready.
    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        let boundPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.claim(), let port = listener.port?.rawValue {
                        continuation.resume(returning: port)
                    }
                case .failed(let error):
                    if resumed.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        port = boundPort
        return boundPort
    }

    func setMediaAssets(videoFile: URL? = nil, artwork: Data? = nil, motion: Data? = nil) {
        queue.async { [self] in
            localVideoFile = videoFile
            artworkBytes = artwork
            motionBytes = motion
        }
    }

    /// The karaoke WebVTT that the receiver shows as a native subtitle track. Nil removes the track.
    func setSubtitles(_ vtt: String?) {
        queue.async { [self] in subtitles = vtt }
    }

    /// Sends one encoded frame to every receiver. Receivers that have gone away are dropped.
    func publish(_ frame: [UInt8]) {
        let chunk = Array(String(frame.count, radix: 16).utf8) + Array("\r\n".utf8) + frame + Array("\r\n".utf8)
        queue.async { [self] in
            for (key, connection) in receivers {
                connection.send(
                    content: Data(chunk),
                    completion: .contentProcessed { [weak self] error in
                        if error != nil { self?.drop(key) }
                    })
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        queue.async { [self] in
            for connection in receivers.values { connection.cancel() }
            receivers.removeAll()
            localVideoFile = nil
            artworkBytes = nil
            motionBytes = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let lines = request.split(whereSeparator: \.isNewline).map(String.init)
            let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let path = target.split(separator: "?").first.map(String.init) ?? target
            let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
                .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }

            if path == codec.path {
                let key = ObjectIdentifier(connection)
                receivers[key] = connection
                connection.stateUpdateHandler = { [weak self] state in
                    if case .cancelled = state { self?.drop(key) }
                    if case .failed = state { self?.drop(key) }
                }
                connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
                return
            }

            // The contract's paths: `/api/v1/cast/video/<suite>/video.mp4` and `/lyrics.vtt`. The suite ID is opaque.
            if let media = StageMediaPath(path) {
                if case .video = media, let videoURL = localVideoFile {
                    Self.sendFile(videoURL, rangeHeader: rangeHeader, contentType: "video/mp4", on: connection)
                    return
                }
                if case .lyrics = media, let subtitles {
                    Self.sendBytes(
                        Data(subtitles.utf8), rangeHeader: nil, contentType: "text/vtt; charset=utf-8", on: connection)
                    return
                }
            }
            if path == "/cast/motion.mp4", let motion = motionBytes {
                Self.sendBytes(motion, rangeHeader: rangeHeader, contentType: "video/mp4", on: connection)
                return
            }
            if path == "/cast/artwork", let artwork = artworkBytes {
                let mime = artwork.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
                Self.sendBytes(artwork, rangeHeader: rangeHeader, contentType: mime, on: connection)
                return
            }

            connection.send(
                content: Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8),
                completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func sendBytes(
        _ data: Data, rangeHeader: String?, contentType: String, on connection: NWConnection
    ) {
        // Split across two lines for length limit
        let size = Int64(data.count)
        switch ByteRange.parse(rangeHeader, size: size) {
        case .unsatisfiable:
            let head =
                "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(size)\r\n"
                + "Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in connection.cancel() })
        case .full:
            let head =
                "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(size)\r\n"
                + "Accept-Ranges: bytes\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Data(head.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
        case .partial(let range):
            let length = range.upperBound - range.lowerBound + 1
            let head =
                "HTTP/1.1 206 Partial Content\r\nContent-Type: \(contentType)\r\nContent-Length: \(length)\r\n"
                + "Content-Range: bytes \(range.lowerBound)-\(range.upperBound)/\(size)\r\n"
                + "Accept-Ranges: bytes\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            let slice = data[Int(range.lowerBound)...Int(range.upperBound)]
            connection.send(
                content: Data(head.utf8) + slice,
                completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func sendFile(_ url: URL, rangeHeader: String?, contentType: String, on connection: NWConnection) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let sizeNumber = attributes[.size] as? NSNumber,
            let handle = try? FileHandle(forReadingFrom: url)
        else {
            connection.send(
                content: Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8),
                completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let size = sizeNumber.int64Value
        let range: ClosedRange<Int64>
        let statusLine: String
        let extraHeaders: String
        switch ByteRange.parse(rangeHeader, size: size) {
        case .unsatisfiable:
            try? handle.close()
            let head =
                "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(size)\r\n"
                + "Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in connection.cancel() })
            return
        case .full:
            range = 0...(size - 1)
            statusLine = "HTTP/1.1 200 OK"
            extraHeaders = ""
        case .partial(let bounded):
            range = bounded
            statusLine = "HTTP/1.1 206 Partial Content"
            extraHeaders = "Content-Range: bytes \(bounded.lowerBound)-\(bounded.upperBound)/\(size)\r\n"
        }

        let total = range.upperBound - range.lowerBound + 1
        let head =
            "\(statusLine)\r\nContent-Type: \(contentType)\r\nContent-Length: \(total)\r\n"
            + "\(extraHeaders)Accept-Ranges: bytes\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        try? handle.seek(toOffset: UInt64(range.lowerBound))
        connection.send(
            content: Data(head.utf8),
            completion: .contentProcessed { error in
                if error != nil {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                streamFileChunks(handle: handle, remaining: total, on: connection)
            })
    }

    private static func streamFileChunks(handle: FileHandle, remaining: Int64, on connection: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            connection.cancel()
            return
        }
        let chunkLimit = Int(min(remaining, 65_536))
        let chunk = (try? handle.read(upToCount: chunkLimit)) ?? Data()
        guard !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(
            content: chunk,
            completion: .contentProcessed { error in
                if error != nil {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                streamFileChunks(handle: handle, remaining: remaining - Int64(chunk.count), on: connection)
            })
    }

    private func drop(_ key: ObjectIdentifier) {
        queue.async { [self] in
            receivers[key]?.cancel()
            receivers[key] = nil
        }
    }
}

/// Lets a continuation resume once, even when the listener reports ready and then fails.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true

        return true
    }
}
