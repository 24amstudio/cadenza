import Foundation
import Network

// One browser connection. It serves a static file, or upgrades to a WebSocket that carries Remote protocol messages.
@MainActor
final class WebRemoteSession {
    // Outbound bytes waiting on the socket. Beyond this, the Host disconnects the Remote rather than buffer without limit.
    static let maximumQueuedBytes = 4_194_304

    private enum Phase {
        case head
        case socket
        case finished
    }

    private let connection: NWConnection
    private let bundle: WebRemoteBundle
    private let allowedHosts: () -> Set<String>
    private var phase: Phase = .head
    private var buffer: [UInt8] = []
    private var queuedBytes = 0
    var onSocketOpened: ((WebRemoteSession) -> Void)?
    var onText: (([UInt8]) -> Void)?
    var onSocketClosed: (() -> Void)?
    var onFinished: (() -> Void)?

    init(connection: NWConnection, bundle: WebRemoteBundle, allowedHosts: @escaping () -> Set<String>) {
        self.connection = connection
        self.bundle = bundle
        self.allowedHosts = allowedHosts
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionStateChanged(state) }
        }
        connection.start(queue: queue)
    }

    // Queues one protocol message as a text frame. Returns false when the Remote is gone or too far behind.
    func send(_ payload: Data) -> Bool {
        guard phase == .socket else { return false }
        let frame = WebSocketFraming.textFrame([UInt8](payload))
        guard queuedBytes + frame.count <= Self.maximumQueuedBytes else { return false }
        queuedBytes += frame.count
        let size = frame.count
        connection.send(
            content: frame, contentContext: .defaultMessage, isComplete: true,
            completion: .contentProcessed { [weak self] error in
                Task { @MainActor in self?.frameWritten(size: size, failed: error != nil) }
            })
        return true
    }

    // Ends the connection and notifies the owner once.
    func close() {
        finish(writing: nil)
    }

    private func connectionStateChanged(_ state: NWConnection.State) {
        switch state {
        case .ready:
            receive()
        case .failed, .cancelled:
            finish(writing: nil)
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                self?.received(data: data, isComplete: isComplete, failed: error != nil)
            }
        }
    }

    private func received(data: Data?, isComplete: Bool, failed: Bool) {
        guard phase != .finished else { return }
        if let data { buffer.append(contentsOf: data) }
        if failed || (isComplete && data == nil) {
            finish(writing: nil)
            return
        }
        switch phase {
        case .head:
            handleHead()
        case .socket:
            handleFrames()
        case .finished:
            return
        }
        if phase != .finished { receive() }
    }

    private func handleHead() {
        switch WebRemoteRequest.parse(buffer) {
        case .incomplete:
            return
        case .invalid:
            finish(writing: response(status: 400, contentType: nil, body: []))
        case .complete(let request, let consumed):
            buffer.removeFirst(consumed)
            route(request)
        }
    }

    private func route(_ request: WebRemoteRequest) {
        switch WebRemoteRequest.route(request, allowedHosts: allowedHosts()) {
        case .socket(let key):
            openSocket(key: key)
        case .file(let path, let headOnly):
            serveFile(path: path, headOnly: headOnly)
        case .reject(let status):
            finish(writing: response(status: status, contentType: nil, body: []))
        }
    }

    private func serveFile(path: String, headOnly: Bool) {
        guard let file = bundle.file(forRequestPath: path), let body = try? Data(contentsOf: file.url) else {
            finish(writing: response(status: 404, contentType: nil, body: []))
            return
        }
        let cacheControl = file.isHashedAsset ? "public, max-age=31536000, immutable" : "no-cache"
        let data = response(
            status: 200, contentType: file.contentType, body: headOnly ? [] : [UInt8](body), cacheControl: cacheControl,
            contentLength: body.count)
        finish(writing: data)
    }

    private func openSocket(key: String) {
        phase = .socket
        connection.send(
            content: WebSocketFraming.handshakeResponse(forKey: key), contentContext: .defaultMessage, isComplete: true,
            completion: .contentProcessed { _ in })
        onSocketOpened?(self)
        handleFrames()
    }

    private func handleFrames() {
        do {
            for event in try WebSocketFraming.parseFrames(&buffer) {
                guard phase == .socket else { return }
                switch event {
                case .text(let bytes):
                    onText?(bytes)
                case .ping(let payload):
                    writeControl(WebSocketFraming.pongFrame(payload))
                case .pong:
                    continue
                case .close:
                    finish(writing: WebSocketFraming.closeFrame(code: 1000))
                    return
                }
            }
        } catch let violation as WebSocketFraming.ProtocolViolation {
            finish(writing: WebSocketFraming.closeFrame(code: violation.closeCode))
        } catch {
            finish(writing: nil)
        }
    }

    private func writeControl(_ frame: Data) {
        connection.send(
            content: frame, contentContext: .defaultMessage, isComplete: true,
            completion: .contentProcessed { _ in })
    }

    private func frameWritten(size: Int, failed: Bool) {
        queuedBytes -= size
        if failed { finish(writing: nil) }
    }

    // Sends an optional final write, then cancels. Callers never reuse the connection after this.
    private func finish(writing final: Data?) {
        guard phase != .finished else { return }
        let wasSocket = phase == .socket
        phase = .finished
        buffer.removeAll()
        if let final {
            connection.send(
                content: final, contentContext: .defaultMessage, isComplete: true,
                completion: .contentProcessed { [weak self] _ in
                    Task { @MainActor in self?.connection.cancel() }
                })
        } else {
            connection.cancel()
        }
        if wasSocket { onSocketClosed?() }
        onFinished?()
    }

    private func response(
        status: Int, contentType: String?, body: [UInt8], cacheControl: String = "no-store", contentLength: Int? = nil
    ) -> Data {
        var lines = ["HTTP/1.1 \(status) \(Self.reason(for: status))"]
        lines.append("Content-Length: \(contentLength ?? body.count)")
        if let contentType { lines.append("Content-Type: \(contentType)") }
        lines.append("Cache-Control: \(cacheControl)")
        lines.append("Content-Security-Policy: \(bundle.contentSecurityPolicy)")
        lines.append("Referrer-Policy: no-referrer")
        lines.append("X-Content-Type-Options: nosniff")
        lines.append("Connection: close")
        var data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        data.append(contentsOf: body)
        return data
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Error"
        }
    }
}
