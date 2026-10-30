import Foundation
import Network

@MainActor
final class PairingBootstrap {
    private static let magic = Data([0x43, 0x44, 0x5A, 0x42])
    private let queue = DispatchQueue(label: "app.cadenza.pairing-bootstrap", qos: .userInitiated)
    private var listener: NWListener?
    private var startResult: CheckedContinuation<Void, Error>?
    private(set) var ready = false
    var onRequest: ((Data) -> Data?)?

    static func port(for controlPort: UInt16) -> UInt16 {
        controlPort == UInt16.max ? controlPort - 1 : controlPort + 1
    }

    func start(controlPort: UInt16) async throws {
        stop()
        let port = Self.port(for: controlPort)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw CadenzaError.failure("network", "Invalid pairing bootstrap port.")
        }
        let listener = try NWListener(using: .tcp, on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.ready = true
                    self.startResult?.resume()
                    self.startResult = nil
                case .failed(let error):
                    self.ready = false
                    if let result = self.startResult {
                        self.startResult = nil
                        result.resume(throwing: error)
                    }
                case .cancelled:
                    self.ready = false
                    if let result = self.startResult {
                        self.startResult = nil
                        result.resume(throwing: CancellationError())
                    }
                default: break
                }
            }
        }
        self.listener = listener
        try await withCheckedThrowingContinuation { continuation in
            startResult = continuation
            listener.start(queue: queue)
            Task { @MainActor [weak self, weak listener] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, let listener, self.listener === listener, let result = self.startResult else { return }
                self.startResult = nil
                listener.cancel()
                result.resume(throwing: CadenzaError.failure("network", "Pairing bootstrap did not become ready."))
            }
        }
    }

    func stop() {
        ready = false
        startResult?.resume(throwing: CancellationError())
        startResult = nil
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        guard Self.isLocal(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.receive(connection)
                case .failed, .cancelled: connection.cancel()
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func receive(_ connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, error == nil, let data else {
                    connection.cancel()
                    return
                }
                var combined = buffer
                combined.append(data)
                let expectedLength = combined.count >= 6 ? 6 + Int(combined[5]) : 6
                guard combined.count >= expectedLength else {
                    self.receive(connection, buffer: combined)
                    return
                }
                let request = Data(combined.prefix(expectedLength))
                guard let secret = Self.secret(from: request),
                    let certificate = self.onRequest?(secret)
                else {
                    connection.cancel()
                    return
                }
                guard (512...3_072).contains(certificate.count) else {
                    connection.cancel()
                    return
                }
                var response = Self.magic
                response.append(1)
                response.append(UInt8((certificate.count >> 8) & 0xFF))
                response.append(UInt8(certificate.count & 0xFF))
                response.append(certificate)
                connection.send(
                    content: response,
                    contentContext: NWConnection.ContentContext(identifier: identifier()),
                    isComplete: true,
                    completion: .contentProcessed { _ in
                        connection.cancel()
                    })
            }
        }
    }

    private static func secret(from data: Data) -> Data? {
        guard data.count >= magic.count + 2,
            data.starts(with: magic),
            data[magic.count] == 1
        else { return nil }
        let length = Int(data[magic.count + 1])
        let start = magic.count + 2
        guard (32...128).contains(length), data.count == start + length else { return nil }
        return data.subdata(in: start..<(start + length))
    }

    private static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        let value = String(describing: host).lowercased()
        if value == "::1" || value.hasPrefix("fe80:") || value.hasPrefix("fc") || value.hasPrefix("fd") { return true }
        let bytes = value.split(separator: ".").compactMap { UInt8($0) }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 10 || bytes[0] == 127
            || (bytes[0] == 192 && bytes[1] == 168)
            || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 169 && bytes[1] == 254)
    }
}
