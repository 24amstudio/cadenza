import Foundation
import Network
import Synchronization

/// Proxies only lightweight HLS `.m3u8` playlist text and injects a `#EXT-X-MEDIA:TYPE=SUBTITLES` WebVTT karaoke
/// rendition (`lyrics.vtt`) so AirPlay 2 / Apple TV hardware decrypts FairPlay CDN video directly and renders synced
/// lyrics natively. Zero video segments pass through Host.
final class AirPlayHlsKaraokeProxy: @unchecked Sendable {
    struct Session: Sendable {
        let id: String
        let masterPlaylist: String
        let subtitlePlaylist: String
        let vttText: String
    }

    private let queue = DispatchQueue(label: "app.cadenza.host.airplay.hls")
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var activeSession: Session?

    func start() async throws -> UInt16 {
        if let listener, port != 0 {
            _ = listener
            return port
        }
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let boundPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let finished = Mutex(false)
            listener.stateUpdateHandler = { state in
                finished.withLock { done in
                    guard !done else { return }
                    switch state {
                    case .ready:
                        if let assigned = listener.port?.rawValue {
                            done = true
                            continuation.resume(returning: assigned)
                        }
                    case .failed(let error):
                        done = true
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
        }
        port = boundPort
        return boundPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        queue.async { [self] in activeSession = nil }
    }

    /// Registers a proxied FairPlay HLS master + WebVTT karaoke session and returns its local `master.m3u8` URL.
    func publish(
        sessionId: String,
        originalMaster: String,
        baseURL: URL,
        durationSeconds: Int,
        vttText: String,
        lanHost: String
    ) -> URL? {
        guard port != 0 else { return nil }
        let base = "http://\(lanHost):\(port)/airplay/karaoke/\(sessionId)"
        let subsURL = "\(base)/subs.m3u8"
        let vttURL = "\(base)/lyrics.vtt"
        let master = Self.injectSubtitles(
            masterPlaylist: originalMaster, baseURL: baseURL, subtitlesPlaylistURL: subsURL)
        let subs = Self.subtitlePlaylist(vttURL: vttURL, durationSeconds: durationSeconds)
        let session = Session(id: sessionId, masterPlaylist: master, subtitlePlaylist: subs, vttText: vttText)
        queue.async { [self] in activeSession = session }
        return URL(string: "\(base)/master.m3u8")
    }

    func updateVTT(_ vttText: String, for sessionId: String) {
        queue.async { [self] in
            guard let current = activeSession, current.id == sessionId else { return }
            activeSession = Session(
                id: current.id, masterPlaylist: current.masterPlaylist,
                subtitlePlaylist: current.subtitlePlaylist, vttText: vttText)
        }
    }

    func clear() {
        queue.async { [self] in activeSession = nil }
    }

    /// Rewrites relative media/variant URIs in an Apple CDN master playlist to absolute HTTPS URLs and injects the
    /// Cadenza WebVTT subtitle rendition (`cadenza-karaoke`) across all `#EXT-X-STREAM-INF` entries.
    static func injectSubtitles(masterPlaylist: String, baseURL: URL, subtitlesPlaylistURL: String) -> String {
        let subtitleLine =
            "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"cadenza-karaoke\",NAME=\"Cadenza Lyrics\","
            + "DEFAULT=YES,AUTOSELECT=YES,FORCED=YES,LANGUAGE=\"en\",URI=\"\(subtitlesPlaylistURL)\""
        let lines = masterPlaylist.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var result: [String] = []
        var insertedSubtitle = false
        var expectingStreamURI = false

        for line in lines {
            if line.hasPrefix("#EXT-X-MEDIA:") || line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") {
                result.append(rewritingURIAttr(line, baseURL: baseURL))
                continue
            }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                if !insertedSubtitle {
                    result.append(subtitleLine)
                    insertedSubtitle = true
                }
                result.append(withSubtitleGroup(line, groupId: "cadenza-karaoke"))
                expectingStreamURI = true
                continue
            }
            if expectingStreamURI, !line.isEmpty, !line.hasPrefix("#") {
                expectingStreamURI = false
                let resolved = URL(string: line, relativeTo: baseURL)?.absoluteString ?? line
                result.append(resolved)
                continue
            }
            expectingStreamURI = false
            result.append(line)
            if !insertedSubtitle && (line.hasPrefix("#EXTM3U") || line.hasPrefix("#EXT-X-VERSION:")) {
                result.append(subtitleLine)
                insertedSubtitle = true
            }
        }
        return result.joined(separator: "\n")
    }

    static func subtitlePlaylist(vttURL: String, durationSeconds: Int) -> String {
        let target = max(1, durationSeconds)
        return [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXTINF:\(target).0,",
            vttURL,
            "#EXT-X-ENDLIST",
            "",
        ].joined(separator: "\n")
    }

    private static func withSubtitleGroup(_ line: String, groupId: String) -> String {
        let stripped = line.replacingOccurrences(
            of: #",?SUBTITLES="[^"]*""#, with: "", options: .regularExpression)
        return stripped + ",SUBTITLES=\"\(groupId)\""
    }

    private static func rewritingURIAttr(_ line: String, baseURL: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"URI="([^"]+)""#) else { return line }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
            let uriRange = Range(match.range(at: 1), in: line)
        else { return line }
        let raw = String(line[uriRange])
        let absolute = URL(string: raw, relativeTo: baseURL)?.absoluteString ?? raw
        return line.replacingCharacters(in: uriRange, with: absolute)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            guard let session = activeSession else {
                Self.respond(connection, status: "404 Not Found", type: "text/plain", body: Data())
                return
            }
            let prefix = "/airplay/karaoke/\(session.id)/"
            switch path {
            case prefix + "master.m3u8":
                Self.respond(
                    connection, status: "200 OK", type: "application/vnd.apple.mpegurl",
                    body: Data(session.masterPlaylist.utf8))
            case prefix + "subs.m3u8":
                Self.respond(
                    connection, status: "200 OK", type: "application/vnd.apple.mpegurl",
                    body: Data(session.subtitlePlaylist.utf8))
            case prefix + "lyrics.vtt":
                Self.respond(
                    connection, status: "200 OK", type: "text/vtt; charset=utf-8",
                    body: Data(session.vttText.utf8))
            default:
                Self.respond(connection, status: "404 Not Found", type: "text/plain", body: Data())
            }
        }
    }

    private static func respond(_ connection: NWConnection, status: String, type: String, body: Data) {
        let head =
            "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Access-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(head.utf8) + body,
            completion: .contentProcessed { _ in connection.cancel() })
    }
}
