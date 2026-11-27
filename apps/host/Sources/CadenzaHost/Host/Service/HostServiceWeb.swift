import Foundation

// Cadenza Web lifecycle: the browser Remote listener starts with the native listeners and its sockets become peers.
extension HostService {
    static let bundledWebRoot = WebRemoteBundle.bundledRoot(in: HostResources.bundle.resourceURL)

    // Cadenza Web is optional. Its failure leaves native Remotes working, so it reports an issue instead of failing start.
    func startWebRemote() async {
        webRemote.stop()
        guard configuration.webEnabled else { return }
        let port = configuration.webPort
        // Without a bundled page the socket still serves the hosted Cadenza Web page, so a paired browser can reach the
        // Host over the LAN. Settings shows the unbundled state.
        let bundle = Self.bundledWebRoot.map { WebRemoteBundle(root: $0) }
        if bundle == nil {
            logger.log(
                .info, category: "network", action: "web.unbundled",
                "Cadenza Web is not bundled in this build; its socket serves the hosted page")
        }
        let advertised = configuration.advertisedAddress
        webRemote.updateReply = { @MainActor [weak self] request in
            self?.remoteUpdateReply(request) ?? WebRemoteReply(status: 503)
        }
        do {
            try await webRemote.start(
                port: port, bundle: bundle,
                allowedHosts: { Self.webAllowedHosts(port: port, advertised: advertised) })
        } catch {
            logger.log(
                .warning, category: "network", action: "web.failed", "Cadenza Web could not start",
                metadata: ["port": String(port)])
            onIssue?("Cadenza Web could not start on port \(port). Check that the port is free.")
        }
    }

    /// The Remote build cached for this Host's release, offered in the welcome so a Remote can update without asking.
    func remoteUpdateOffer() -> RemoteUpdateCache.Offer? {
        let root = RemoteUpdateCache.root(hostVersion: HostBuild.version, supportDirectory: supportDirectory)
        return RemoteUpdateCache.current(root: root).map { RemoteUpdateCache.Offer(artifact: $0.artifact) }
    }

    // Remote updates come from the cache for this Host's release. Each request must carry a paired Remote's credentials.
    func remoteUpdateReply(_ request: WebRemoteRequest) -> WebRemoteReply {
        let root = RemoteUpdateCache.root(hostVersion: HostBuild.version, supportDirectory: supportDirectory)
        return RemoteUpdateRelay(
            current: { RemoteUpdateCache.current(root: root) },
            authorize: { [store] auth in (try? store.authenticate(auth)) == true }
        ).reply(to: request)
    }

    // Host names a browser may use. Anything else, including a DNS name that points here, is refused.
    static func webAllowedHosts(port: UInt16, advertised: String) -> Set<String> {
        var hosts = Set(LANAddresses.all().map { "\($0):\(port)" })
        if !advertised.isEmpty { hosts.insert("\(advertised):\(port)") }
        if let bonjour = BonjourName.current() { hosts.insert("\(bonjour):\(port)") }
        hosts.formUnion(["127.0.0.1:\(port)", "localhost:\(port)"])
        return hosts
    }

    // A browser session becomes a network peer, so authentication, limits, and commands match native Remotes.
    func openWebSocket(_ socket: WebRemoteSession) {
        guard
            let peerId = network.acceptWeb(
                send: { [weak socket] data in socket?.send(data) ?? false },
                cancel: { [weak socket] in socket?.close() })
        else {
            socket.close()
            return
        }
        socket.onText = { [weak self] bytes in self?.network.receiveWeb(Data(bytes), from: peerId) }
        socket.onSocketClosed = { [weak self] in self?.network.disconnect(peerId) }
    }
}
