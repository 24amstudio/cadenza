import Foundation
import Network

/// A TLS connection to a Cast device's control port. Cast devices present self-signed certificates on the local network,
/// so the device certificate is not checked. The connection carries control messages only. The device pulls the audio
/// from Cadenza's own LAN address, and Cadenza sends it nothing else.
final class CastControlConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "app.cadenza.host.cast.control")
    private var buffer: [UInt8] = []
    private let onMessage: @Sendable (CastMessage) -> Void
    private let onClose: @Sendable (String) -> Void

    init(
        endpoint: NWEndpoint,
        onMessage: @escaping @Sendable (CastMessage) -> Void,
        onClose: @escaping @Sendable (String) -> Void
    ) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        connection = NWConnection(to: endpoint, using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        self.onMessage = onMessage
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.onClose(error.localizedDescription)
            case .cancelled:
                self?.onClose("The Cast connection closed.")
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func send(_ message: CastMessage) {
        connection.send(
            content: CastMessageCodec.frame(message),
            completion: .contentProcessed { [weak self] error in
                if let error { self?.onClose(error.localizedDescription) }
            })
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }

            if let data {
                buffer.append(contentsOf: data)
                drain()
            }
            if let error {
                onClose(error.localizedDescription)

                return
            }
            if complete {
                onClose("The Cast device closed the connection.")

                return
            }
            receive()
        }
    }

    private func drain() {
        while let length = CastMessageCodec.bodyLength(prefix: buffer), buffer.count >= 4 + length {
            let body = Array(buffer[4..<(4 + length)])
            buffer.removeFirst(4 + length)
            if let message = CastMessageCodec.decode(body) { onMessage(message) }
        }
    }
}
