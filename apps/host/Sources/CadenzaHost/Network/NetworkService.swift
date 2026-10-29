import Foundation
import Network
import Security

@MainActor
final class NetworkService {
    @MainActor
    final class Peer {
        struct Outbound: Sendable {
            let data: Data
        }

        let id = identifier()
        let connection: NWConnection?
        let transport: String
        let sendTransport: ((Data) -> Bool)?
        let cancelTransport: () -> Void
        var remoteId: String?
        var remoteVersion: String?
        var authenticated = false
        var status: SessionStatus?
        var effectiveDecision: EffectiveTransportDecision?
        var transportPolicy = TransportPolicy(
            mode: "lan_only", selection: "deterministic", primary: "lan", bulk: "lan")
        var supportsHeartbeat = false
        var receivedAt: [Int64] = []
        var outbound: [Outbound] = []
        var pendingState: Outbound?
        var outboundBytes = 0
        var sending = false

        init(_ connection: NWConnection) {
            self.connection = connection
            transport = "lan"
            sendTransport = nil
            cancelTransport = { connection.cancel() }
        }

        init(
            transport: String,
            send: @escaping (Data) -> Bool,
            cancel: @escaping () -> Void,
        ) {
            connection = nil
            self.transport = transport
            sendTransport = send
            cancelTransport = cancel
        }
    }

    private var listener: NWListener?
    private let ssdp = SSDPResponder()
    private var startResult: CheckedContinuation<Void, Error>?
    private(set) var ready = false
    private(set) var peers: [String: Peer] = [:]
    private var bluetoothPeers: [UUID: String] = [:]
    var onFrame: ((Peer, Frame) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var onIssue: ((String) -> Void)?
    private let queue = DispatchQueue(label: "app.cadenza.network", qos: .userInitiated)

    func start(identity: TLSIdentity, port: UInt16, name: String, hostId: String) async throws {
        stop()
        let tls = NWProtocolTLS.Options()
        guard let local = sec_identity_create(identity.identity) else {
            throw CadenzaError.failure("tls", "Cannot initialize the Host identity.")
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, local)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        webSocket.maximumMessageSize = Wire.maximumMessageBytes
        webSocket.setClientRequestHandler(queue) { _, headers in
            let browserOrigin = headers.contains { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }
            return NWProtocolWebSocket.Response(
                status: browserOrigin ? .reject : .accept, subprotocol: nil,
                additionalHeaders: [
                    (name: "Cache-Control", value: "no-store"), (name: "X-Content-Type-Options", value: "nosniff"),
                ]
            )
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw CadenzaError.failure("network", "Invalid listening port.")
        }
        let listener = try NWListener(using: parameters, on: endpointPort)
        let record = Data(("host_id=" + hostId).utf8)
        listener.service = NWListener.Service(
            name: name, type: "_cadence._tcp", txtRecord: Data([UInt8(record.count)]) + record)
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
                    } else {
                        self.onFailure?(error.localizedDescription)
                    }
                case .cancelled:
                    self.ready = false
                    let error = CadenzaError.failure("network", "The local listener stopped unexpectedly.")
                    if let result = self.startResult {
                        self.startResult = nil
                        result.resume(throwing: error)
                    } else {
                        self.onFailure?(error.localizedDescription)
                    }
                default: break
                }
            }
        }
        self.listener = listener
        try await withCheckedThrowingContinuation { continuation in
            startResult = continuation
            listener.start(queue: queue)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.listener === listener, let result = self.startResult else { return }
                self.startResult = nil
                listener.cancel()
                result.resume(
                    throwing: CadenzaError.failure(
                        "network",
                        "The local listener did not become ready. Check local-network permission and the selected port."
                    ))
            }
        }
        ssdp.start(
            hostId: hostId,
            address: LANAddresses.all().first ?? "127.0.0.1",
            port: port)
    }

    func stop() {
        ready = false
        startResult?.resume(throwing: CancellationError())
        startResult = nil
        listener?.cancel()
        listener = nil
        ssdp.stop()
        for peer in peers.values { peer.cancelTransport() }
        peers.removeAll()
        bluetoothPeers.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard peers.count < 32, localAddress(connection.endpoint) else {
            connection.cancel()
            return
        }
        let peer = Peer(connection)
        let peerID = peer.id
        peers[peerID] = peer
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.receive(peerID)
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(5))
                        if self?.peers[peerID]?.authenticated == false { self?.disconnect(peerID) }
                    }
                case .failed, .cancelled: self.disconnect(peerID)
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func localAddress(_ endpoint: NWEndpoint) -> Bool {
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

    private func receive(_ peerId: String) {
        guard let peer = peers[peerId] else { return }
        guard let connection = peer.connection else { return }
        connection.receiveMessage { [weak self] data, context, complete, error in
            Task { @MainActor in
                guard let self, let peer = self.peers[peerId] else { return }
                if error != nil {
                    self.disconnect(peerId)
                    return
                }
                let metadata =
                    context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata
                if metadata?.opcode == .close {
                    self.disconnect(peerId)
                    return
                }
                if let data, metadata?.opcode == .text, complete {
                    self.consume(data, peerId: peerId)
                }
                self.receive(peerId)
            }
        }
    }

    func acceptBluetooth(
        centralID: UUID,
        send: @escaping (Data) -> Bool,
        cancel: @escaping () -> Void,
    ) {
        guard peers.count < 32 else {
            cancel()
            return
        }
        if let old = bluetoothPeers.removeValue(forKey: centralID) { disconnect(old) }
        let peer = Peer(transport: "ble", send: send, cancel: cancel)
        peers[peer.id] = peer
        bluetoothPeers[centralID] = peer.id
        Task { @MainActor [weak self, weak peer] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let peer, self.peers[peer.id]?.authenticated == false else { return }
            self.disconnect(peer.id)
        }
    }

    func receiveBluetooth(_ data: Data, from centralID: UUID) {
        guard let peerId = bluetoothPeers[centralID] else { return }
        consume(data, peerId: peerId)
    }

    func disconnectBluetooth(_ centralID: UUID) {
        guard let peerId = bluetoothPeers.removeValue(forKey: centralID) else { return }
        disconnect(peerId)
    }

    private func consume(_ data: Data, peerId: String) {
        guard let peer = peers[peerId] else { return }
        let now = monotonicMs()
        peer.receivedAt.removeAll { now - $0 > 1_000 }
        let limit = peer.authenticated ? 512 : 5
        guard peer.receivedAt.count < limit, peer.authenticated || data.count <= 4_096 else {
            disconnect(peerId)
            return
        }
        peer.receivedAt.append(now)
        do {
            let frame = try ProtocolValidation.decode(data)
            onFrame?(peer, frame)
        } catch {
            send(
                Frame(type: "error", errorCode: "invalid_command", message: error.localizedDescription),
                to: peer)
        }
    }

    func send(_ frame: Frame, to peer: Peer) {
        do {
            send(try Wire.encode(frame), to: peer, priority: isPriority(frame.type))
        } catch {
            disconnect(peer.id)
            onIssue?("The Host could not encode a message for a Remote: " + error.localizedDescription)
        }
    }

    func broadcast(_ frame: Frame) {
        let data: Data
        do {
            data = try Wire.encode(frame)
        } catch {
            // A silent drop here would leave every Remote without a state update.
            onIssue?("The Host could not encode a state update: " + error.localizedDescription)
            return
        }
        for peer in peers.values where peer.authenticated && (frame.type != "heartbeat" || peer.supportsHeartbeat) {
            send(data, to: peer, priority: isPriority(frame.type))
        }
    }

    private func isPriority(_ type: String) -> Bool {
        type != "state" && type != "heartbeat"
    }

    private func send(_ data: Data, to peer: Peer, priority: Bool) {
        guard peers[peer.id] != nil, data.count <= Wire.maximumMessageBytes else {
            disconnect(peer.id)
            onIssue?("The Host closed a Remote connection after an outbound message exceeded the safety limit.")
            return
        }
        let item = Peer.Outbound(data: data)
        let replacedBytes = priority ? 0 : (peer.pendingState?.data.count ?? 0)
        let nextBytes = peer.outboundBytes - replacedBytes + data.count
        guard nextBytes <= 4_194_304
        else {
            disconnect(peer.id)
            onIssue?("The Host closed a Remote connection after its outbound message buffer exceeded the safety limit.")
            return
        }
        peer.outboundBytes = nextBytes
        if priority {
            peer.outbound.append(item)
        } else {
            peer.pendingState = item
        }
        flush(peer)
    }

    private func flush(_ peer: Peer) {
        guard !peer.sending, peers[peer.id] != nil else { return }
        let item: Peer.Outbound
        if !peer.outbound.isEmpty {
            item = peer.outbound.removeFirst()
        } else if let pending = peer.pendingState {
            item = pending
            peer.pendingState = nil
        } else {
            return
        }
        peer.sending = true
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: identifier(), metadata: [metadata])
        if let connection = peer.connection {
            connection.send(
                content: item.data, contentContext: context, isComplete: true,
                completion: .contentProcessed { [weak self] error in
                    Task { @MainActor in
                        guard let self, let current = self.peers[peer.id] else { return }
                        current.outboundBytes -= item.data.count
                        current.sending = false
                        if error != nil {
                            self.disconnect(peer.id)
                        } else {
                            self.flush(current)
                        }
                    }
                })
        } else if let sendTransport = peer.sendTransport {
            guard sendTransport(item.data) else {
                peer.outboundBytes -= item.data.count
                peer.sending = false
                disconnect(peer.id)
                return
            }
            peer.outboundBytes -= item.data.count
            peer.sending = false
            flush(peer)
        } else {
            peer.outboundBytes -= item.data.count
            peer.sending = false
            disconnect(peer.id)
        }
    }

    func disconnect(_ peerId: String) {
        guard let peer = peers.removeValue(forKey: peerId) else { return }
        bluetoothPeers = bluetoothPeers.filter { $0.value != peerId }
        peer.cancelTransport()
        onDisconnect?(peerId)
    }

    func revoke(_ remoteId: String) {
        let ids = peers.values.filter { $0.remoteId == remoteId }.map(\.id)
        for id in ids { disconnect(id) }
    }
}
