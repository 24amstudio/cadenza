import Foundation

// The subset of HTTP/1.1 the web Remote needs: a bounded request head, one value per header, and one route decision.
struct WebRemoteRequest: Equatable {
    static let maximumHeadBytes = 8_192
    static let socketPath = "/v1/socket"
    static let stageSocketPath = "/cast/live"
    static let singSocketPath = "/sing/live"
    static let stageMediaPrefix = "/api/v1/cast/"
    static let stageRoles: Set<String> = ["tv_stage", "android_tv_receiver"]
    /// The Wi-Fi Remote audio socket shares `/cast/live`. It takes the Remote's paired token, not a stage PIN.
    static let remoteAudioRole = "remote_audio"
    /// Cadenza Web's GitHub Pages origin. Only the Remote socket and the Remote audio socket accept it, so a paired browser
    /// on that site can reach the Host over the LAN. The Origin must match exactly, and the Remote's token still
    /// authenticates the session.
    static let hostedPageOrigin = "https://24amstudio.github.io"

    let method: String
    let path: String
    let headers: [String: String]

    enum Parse: Equatable {
        case incomplete
        case invalid
        case complete(WebRemoteRequest, consumed: Int)
    }

    enum Route: Equatable {
        case socket(key: String)
        /// A stage receiver's socket on `/cast/live`, identified by its `role` query value.
        case stageSocket(key: String, role: String)
        /// A paired Web Remote's Wi-Fi audio socket. The handshake authenticates it.
        case remoteAudioSocket(key: String)
        case singSocket(key: String)
        case file(path: String, headOnly: Bool)
        case update
        /// Read-only media for stage receivers, under `/api/v1/cast/`.
        case stageMedia
        case reject(status: Int)
    }

    static func parse(_ bytes: [UInt8]) -> Parse {
        guard let terminator = headerTerminator(in: bytes) else {
            return bytes.count > maximumHeadBytes ? .invalid : .incomplete
        }
        guard terminator + 4 <= maximumHeadBytes else { return .invalid }
        let head = String(decoding: bytes[0..<terminator], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1", !parts[0].isEmpty, parts[1].hasPrefix("/") else {
            return .invalid
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // A repeated Host or Origin header is ambiguous, so the request is refused instead of choosing one.
            guard headers[name] == nil else { return .invalid }
            headers[name] = value
        }
        let request = WebRemoteRequest(method: String(parts[0]), path: String(parts[1]), headers: headers)
        return .complete(request, consumed: terminator + 4)
    }

    // The browser must be the page served by this Host, or the hosted Cadenza Web page on the Remote socket. `allowedHosts`
    // holds lowercased host:port values for this Host's local addresses, so a DNS-rebinding name cannot open the socket.
    static func route(_ request: WebRemoteRequest, allowedHosts: Set<String>, singPageToken: String? = nil) -> Route {
        let path = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        if path == socketPath {
            return socketRoute(request, allowedHosts: allowedHosts)
        }
        if path == stageSocketPath {
            return stageSocketRoute(request, allowedHosts: allowedHosts)
        }
        if path == singSocketPath {
            return singSocketRoute(request, allowedHosts: allowedHosts, token: singPageToken)
        }
        guard request.method == "GET" || request.method == "HEAD" else { return .reject(status: 405) }
        // Update routes are answered by the relay, which checks the Remote's credentials before it serves anything.
        if path.hasPrefix(RemoteUpdateCache.updatesPrefix) { return .update }
        if path.hasPrefix(stageMediaPrefix) { return .stageMedia }
        return .file(path: request.path, headOnly: request.method == "HEAD")
    }

    private static func socketRoute(_ request: WebRemoteRequest, allowedHosts: Set<String>) -> Route {
        switch upgradeKey(request, allowedHosts: allowedHosts, acceptsHostedPage: true) {
        case .success(let key): .socket(key: key)
        case .failure(let failure): .reject(status: failure.status)
        }
    }

    /// The `/cast/live` channel takes its role from the query string. The stage roles and the Remote audio role are the
    /// only ones accepted. The Remote audio socket also accepts the hosted Cadenza Web page, like the Remote socket.
    private static func stageSocketRoute(_ request: WebRemoteRequest, allowedHosts: Set<String>) -> Route {
        guard let role = queryValue("role", in: request.path), stageRoles.contains(role) || role == remoteAudioRole
        else {
            return .reject(status: 400)
        }
        if role == remoteAudioRole {
            switch upgradeKey(request, allowedHosts: allowedHosts, acceptsHostedPage: true) {
            case .success(let key): return .remoteAudioSocket(key: key)
            case .failure(let failure): return .reject(status: failure.status)
            }
        }
        switch upgradeKey(request, allowedHosts: allowedHosts, acceptsHostedPage: false) {
        case .success(let key): return .stageSocket(key: key, role: role)
        case .failure(let failure): return .reject(status: failure.status)
        }
    }

    private static func singSocketRoute(
        _ request: WebRemoteRequest, allowedHosts: Set<String>, token: String?
    ) -> Route {
        guard let token, queryValue("token", in: request.path) == token else {
            return .reject(status: 403)
        }
        switch upgradeKey(request, allowedHosts: allowedHosts, acceptsHostedPage: false) {
        case .success(let key): return .singSocket(key: key)
        case .failure(let failure): return .reject(status: failure.status)
        }
    }

    private static func upgradeKey(
        _ request: WebRemoteRequest, allowedHosts: Set<String>, acceptsHostedPage: Bool
    ) -> Result<String, UpgradeFailure> {
        guard request.method == "GET" else { return .failure(UpgradeFailure(status: 405)) }
        guard let host = request.headers["host"]?.lowercased(), allowedHosts.contains(host) else {
            return .failure(UpgradeFailure(status: 403))
        }
        let origin = request.headers["origin"]?.lowercased()
        guard origin == "http://\(host)" || (acceptsHostedPage && origin == hostedPageOrigin) else {
            return .failure(UpgradeFailure(status: 403))
        }
        let upgrades = request.headers["upgrade"]?.lowercased() == "websocket"
        let connectionUpgrades = request.headers["connection"]?.lowercased().contains("upgrade") == true
        guard upgrades, connectionUpgrades, request.headers["sec-websocket-version"] == "13",
            let key = request.headers["sec-websocket-key"], WebSocketFraming.isValidKey(key)
        else { return .failure(UpgradeFailure(status: 400)) }
        return .success(key)
    }

    private struct UpgradeFailure: Error {
        let status: Int
    }

    private static func queryValue(_ name: String, in target: String) -> String? {
        guard let query = target.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.first == name, parts.count == 2 { return parts[1] }
        }
        return nil
    }

    private static func headerTerminator(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 0...(bytes.count - 4)
        where bytes[index] == 0x0D && bytes[index + 1] == 0x0A && bytes[index + 2] == 0x0D && bytes[index + 3] == 0x0A {
            return index
        }
        return nil
    }
}
