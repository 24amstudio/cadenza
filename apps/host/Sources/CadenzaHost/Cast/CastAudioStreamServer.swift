import Foundation
import Network

/// Serves the Cast audio as chunked HTTP on the LAN. Every encoded frame goes to each connected receiver, so a receiver
/// that joins late picks up the live stream at the next frame. A new URL nonce starts a fresh response on the device.
/// The codec of one Cast stream. AAC is the stereo path; AC-3 carries six-channel output.
enum CastAudioCodec: Sendable {
    case aac, ac3

    var path: String { self == .aac ? "/cast/audio.aac" : "/cast/audio.ac3" }
    var contentType: String { self == .aac ? "audio/aac" : "audio/ac3" }
}

final class CastAudioStreamServer: @unchecked Sendable {
    private let codec: CastAudioCodec
    private var head: String {
        "HTTP/1.1 200 OK\r\nContent-Type: \(codec.contentType)\r\nTransfer-Encoding: chunked\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    }

    init(codec: CastAudioCodec) {
        self.codec = codec
    }

    private let queue = DispatchQueue(label: "app.cadenza.host.cast.stream")
    private var listener: NWListener?
    private var receivers: [ObjectIdentifier: NWConnection] = [:]

    /// Starts listening on an ephemeral port and returns it once the listener is ready.
    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        return try await withCheckedThrowingContinuation { continuation in
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
        queue.async { [self] in
            for connection in receivers.values { connection.cancel() }
            receivers.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let wanted = request.hasPrefix("GET \(codec.path)?") || request.hasPrefix("GET \(codec.path) ")
            guard wanted else {
                connection.send(
                    content: Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8),
                    completion: .contentProcessed { _ in connection.cancel() })

                return
            }
            let key = ObjectIdentifier(connection)
            receivers[key] = connection
            connection.stateUpdateHandler = { [weak self] state in
                if case .cancelled = state { self?.drop(key) }
                if case .failed = state { self?.drop(key) }
            }
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        }
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
