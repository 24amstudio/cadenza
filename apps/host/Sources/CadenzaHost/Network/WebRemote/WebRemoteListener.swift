import Foundation
import Network

// Serves the browser Remote over plain HTTP on the LAN. The app and its socket share one origin, and no certificate is
// involved, so browsers show no warning. Traffic on this listener is not encrypted. Native Remotes use the same plain
// listener on the control port.
@MainActor
final class WebRemoteListener {
    static let maximumSessions = 16

    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: WebRemoteSession] = [:]
    private var bundle: WebRemoteBundle?
    private var allowedHosts: () -> Set<String> = { [] }
    private let queue = DispatchQueue(label: "app.cadenza.web-remote", qos: .userInitiated)
    private(set) var ready = false
    private var startResult: CheckedContinuation<Void, Error>?
    var onSocket: ((WebRemoteSession) -> Void)?

    func start(port: UInt16, bundle: WebRemoteBundle, allowedHosts: @escaping () -> Set<String>) async throws {
        stop()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw CadenzaError.failure("network", "Invalid Cadenza Web port.")
        }
        let listener = try NWListener(using: Self.parameters(), on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        self.bundle = bundle
        self.allowedHosts = allowedHosts
        self.listener = listener
        try await withCheckedThrowingContinuation { continuation in
            startResult = continuation
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in self?.listenerStateChanged(state, from: listener) }
            }
            listener.start(queue: queue)
        }
    }

    private func listenerStateChanged(_ state: NWListener.State, from source: NWListener?) {
        guard let source, listener === source else { return }
        switch state {
        case .ready:
            ready = true
            startResult?.resume()
            startResult = nil
        case .failed(let error):
            ready = false
            startResult?.resume(throwing: error)
            startResult = nil
        case .cancelled:
            ready = false
            startResult?.resume(throwing: CancellationError())
            startResult = nil
        default:
            break
        }
    }

    func stop() {
        ready = false
        startResult?.resume(throwing: CancellationError())
        startResult = nil
        listener?.cancel()
        listener = nil
        bundle = nil
        let active = Array(sessions.values)
        sessions.removeAll()
        for session in active { session.close() }
    }

    private func accept(_ connection: NWConnection) {
        guard let bundle, sessions.count < Self.maximumSessions, LocalAddress.isLocal(connection.endpoint) else {
            connection.cancel()
            return
        }
        let session = WebRemoteSession(connection: connection, bundle: bundle, allowedHosts: allowedHosts)
        let key = ObjectIdentifier(session)
        sessions[key] = session
        session.onSocketOpened = { [weak self] socket in self?.onSocket?(socket) }
        session.onFinished = { [weak self] in self?.sessions.removeValue(forKey: key) }
        session.start(queue: queue)
    }

    private static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }
}
