import Foundation
import Network
import Security

// What a transport did with one frame. `full` keeps the frame queued until the transport reports that it drained.
enum TransportSendResult: Equatable {
    case accepted
    case full
    case failed
}

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
        let sendTransport: ((Data) -> TransportSendResult)?
        let cancelTransport: () -> Void
        var remoteId: String?
        var remoteVersion: String?
        var authenticated = false
        var status: SessionStatus?
        var effectiveDecision: EffectiveTransportDecision?
        var transportPolicy = TransportPolicy(
            mode: "lan_only", selection: "deterministic", primary: "lan", bulk: "lan")
        var supportsHeartbeat = false
        // The last full state this Remote was sent, and when. Heartbeats are judged against it, not the latest snapshot.
        var lastSnapshot: HostSnapshot?
        var lastSnapshotAt: Int64 = 0
        var receivedAt: [Int64] = []
        var outbound: [Outbound] = []
        var pendingState: Outbound?
        // Media waiting behind control frames and state. Queued a few at a time, see sendBulk.
        var bulk: [Outbound] = []
        var bulkBytes = 0
        var outboundBytes = 0
        var sending = false
        // Set while a transport refuses frames. The queue resumes when the transport reports that it drained.
        var transportWaiting = false

        init(_ connection: NWConnection) {
            self.connection = connection
            transport = "lan"
            sendTransport = nil
            cancelTransport = { connection.cancel() }
        }

        init(
            transport: String,
            send: @escaping (Data) -> TransportSendResult,
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
    var logger: HostLogger?
    private let queue = DispatchQueue(label: "app.cadenza.network", qos: .userInitiated)

    func start(port: UInt16, name: String, hostId: String) async throws {
        stop()
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
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
        guard peers.count < 32, LocalAddress.isLocal(connection.endpoint) else {
            connection.cancel()
            return
        }
        let peer = Peer(connection)
        let peerID = peer.id
        peers[peerID] = peer
        logger?.log(
            .info, category: "network", action: "peer.connected", "Remote connection opened", metadata: ["peer": peerID]
        )
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

    private func receive(_ peerId: String) {
        guard let peer = peers[peerId] else { return }
        guard let connection = peer.connection else { return }
        connection.receiveMessage { [weak self] data, context, complete, error in
            Task { @MainActor in
                guard let self, self.peers[peerId] != nil else { return }
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
        send: @escaping (Data) -> TransportSendResult,
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
            try? await Task.sleep(for: .seconds(20))
            guard let self, let peer, self.peers[peer.id]?.authenticated == false else { return }
            self.disconnect(peer.id)
        }
    }

    // The Bluetooth transport can take frames again. The Remote's queue resumes with its latest state.
    func drainedBluetooth(_ centralID: UUID) {
        guard let peerId = bluetoothPeers[centralID], let peer = peers[peerId] else { return }
        peer.transportWaiting = false
        flush(peer)
    }

    func receiveBluetooth(_ data: Data, from centralID: UUID) {
        guard let peerId = bluetoothPeers[centralID] else { return }
        consume(data, peerId: peerId)
    }

    func disconnectBluetooth(_ centralID: UUID) {
        guard let peerId = bluetoothPeers.removeValue(forKey: centralID) else { return }
        disconnect(peerId)
    }

    // Browser Remotes arrive through the web listener, which owns WebSocket framing. Their messages then pass through the
    // same authentication, rate limits, and handlers as native Remotes.
    func acceptWeb(send: @escaping (Data) -> Bool, cancel: @escaping () -> Void) -> String? {
        guard peers.count < 32 else {
            cancel()
            return nil
        }
        let peer = Peer(transport: "lan", send: { send($0) ? .accepted : .failed }, cancel: cancel)
        peers[peer.id] = peer
        logger?.log(
            .info, category: "network", action: "peer.connected", "Remote connection opened",
            metadata: ["peer": peer.id, "transport": "web"]
        )
        Task { @MainActor [weak self, weak peer] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let peer, self.peers[peer.id]?.authenticated == false else { return }
            self.disconnect(peer.id)
        }
        return peer.id
    }

    func receiveWeb(_ data: Data, from peerId: String) {
        consume(data, peerId: peerId)
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
            send(try Wire.encode(frame), to: peer, lane: lane(for: frame.type))
        } catch {
            disconnect(peer.id)
            onIssue?("The Host could not encode a message for a Remote: " + error.localizedDescription)
        }
    }

    func broadcast(_ frame: Frame) {
        broadcast(
            frame,
            to: peers.values.filter { $0.authenticated && (frame.type != "heartbeat" || $0.supportsHeartbeat) })
    }

    // Encodes the frame once for all recipients, so several Remotes do not each pay for the same JSON.
    func broadcast(_ frame: Frame, to recipients: [Peer]) {
        guard !recipients.isEmpty else { return }
        let data: Data
        do {
            data = try Wire.encode(frame)
        } catch {
            // A silent drop here would leave every Remote without a state update.
            onIssue?("The Host could not encode a state update: " + error.localizedDescription)
            return
        }
        for peer in recipients where peers[peer.id] != nil {
            send(data, to: peer, lane: lane(for: frame.type))
        }
    }

    // Control frames go first, then the newest state, then media. Media never holds back a state update or a command result.
    private enum Lane {
        case control
        case state
        case bulk
    }

    private func lane(for type: String) -> Lane {
        switch type {
        case "state", "heartbeat": .state
        case "artwork.chunk", "motion.chunk": .bulk
        default: .control
        }
    }

    private func send(_ data: Data, to peer: Peer, lane: Lane) {
        guard peers[peer.id] != nil, data.count <= Wire.maximumMessageBytes else {
            disconnect(peer.id)
            onIssue?("The Host closed a Remote connection after an outbound message exceeded the safety limit.")
            return
        }
        let item = Peer.Outbound(data: data)
        let replacedBytes = lane == .state ? (peer.pendingState?.data.count ?? 0) : 0
        let nextBytes = peer.outboundBytes - replacedBytes + data.count
        guard nextBytes <= 4_194_304
        else {
            disconnect(peer.id)
            onIssue?("The Host closed a Remote connection after its outbound message buffer exceeded the safety limit.")
            return
        }
        peer.outboundBytes = nextBytes
        switch lane {
        case .control: peer.outbound.append(item)
        case .state: peer.pendingState = item
        case .bulk:
            peer.bulk.append(item)
            peer.bulkBytes += data.count
        }
        flush(peer)
    }

    // Queues bulk frames a few at a time. A transfer waits while its backlog is large, so control frames interleave between
    // its chunks and a long file cannot exhaust the peer's outbound budget.
    func sendBulk(count: Int, makeFrame: (Int) -> Frame, to peer: Peer) async {
        for index in 0..<count {
            while peer.bulkBytes > Self.bulkBacklogBytes, peers[peer.id] != nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard peers[peer.id] != nil else { return }
            send(makeFrame(index), to: peer)
        }
    }

    private static let bulkBacklogBytes = 64 * 1024

    private func flush(_ peer: Peer) {
        guard !peer.sending, !peer.transportWaiting, peers[peer.id] != nil else { return }
        let item: Peer.Outbound
        let lane: Lane
        if !peer.outbound.isEmpty {
            item = peer.outbound.removeFirst()
            lane = .control
        } else if let pending = peer.pendingState {
            item = pending
            peer.pendingState = nil
            lane = .state
        } else if !peer.bulk.isEmpty {
            item = peer.bulk.removeFirst()
            peer.bulkBytes -= item.data.count
            lane = .bulk
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
            switch sendTransport(item.data) {
            case .accepted:
                peer.outboundBytes -= item.data.count
                peer.sending = false
                flush(peer)
            case .full:
                // Keep the frame until the transport drains. It goes back to the front of its own lane, so control
                // frames keep their place, and a waiting state is superseded by a newer one.
                peer.sending = false
                peer.transportWaiting = true
                restore(item, lane: lane, to: peer)
            case .failed:
                peer.outboundBytes -= item.data.count
                peer.sending = false
                disconnect(peer.id)
            }
        } else {
            peer.outboundBytes -= item.data.count
            peer.sending = false
            disconnect(peer.id)
        }
    }

    private func restore(_ item: Peer.Outbound, lane: Lane, to peer: Peer) {
        switch lane {
        case .control:
            peer.outbound.insert(item, at: 0)
        case .state:
            if peer.pendingState == nil {
                peer.pendingState = item
            } else {
                peer.outboundBytes -= item.data.count
            }
        case .bulk:
            peer.bulk.insert(item, at: 0)
            peer.bulkBytes += item.data.count
        }
    }

    func disconnect(_ peerId: String) {
        guard let peer = peers.removeValue(forKey: peerId) else { return }
        bluetoothPeers = bluetoothPeers.filter { $0.value != peerId }
        peer.cancelTransport()
        logger?.log(
            .info, category: "network", action: "peer.disconnected", "Remote connection closed",
            remoteVersion: peer.remoteVersion,
            metadata: ["peer": peerId, "remote_id": peer.remoteId ?? "", "authenticated": String(peer.authenticated)])
        onDisconnect?(peerId)
    }

    func revoke(_ remoteId: String) {
        logger?.log(
            .warning, category: "network", action: "remote.revoked", "Remote access revoked",
            metadata: ["remote_id": remoteId])
        let ids = peers.values.filter { $0.remoteId == remoteId }.map(\.id)
        for id in ids { disconnect(id) }
    }
}
