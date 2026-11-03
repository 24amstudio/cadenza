import Foundation

// The subset of HTTP/1.1 the web Remote needs: a bounded request head, one value per header, and one route decision.
struct WebRemoteRequest: Equatable {
    static let maximumHeadBytes = 8_192
    static let socketPath = "/v1/socket"

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
        case file(path: String, headOnly: Bool)
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

    // The browser must be the page served by this Host. `allowedHosts` holds lowercased host:port values for this Host's
    // local addresses, so a page from another site or a DNS-rebinding name cannot open the socket.
    static func route(_ request: WebRemoteRequest, allowedHosts: Set<String>) -> Route {
        let path = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        if path == socketPath {
            return socketRoute(request, allowedHosts: allowedHosts)
        }
        guard request.method == "GET" || request.method == "HEAD" else { return .reject(status: 405) }
        return .file(path: request.path, headOnly: request.method == "HEAD")
    }

    private static func socketRoute(_ request: WebRemoteRequest, allowedHosts: Set<String>) -> Route {
        guard request.method == "GET" else { return .reject(status: 405) }
        guard let host = request.headers["host"]?.lowercased(), allowedHosts.contains(host) else {
            return .reject(status: 403)
        }
        guard request.headers["origin"]?.lowercased() == "http://\(host)" else { return .reject(status: 403) }
        let upgrades = request.headers["upgrade"]?.lowercased() == "websocket"
        let connectionUpgrades = request.headers["connection"]?.lowercased().contains("upgrade") == true
        guard upgrades, connectionUpgrades, request.headers["sec-websocket-version"] == "13",
            let key = request.headers["sec-websocket-key"], WebSocketFraming.isValidKey(key)
        else { return .reject(status: 400) }
        return .socket(key: key)
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
