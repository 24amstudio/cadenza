import Foundation

// Cadenza Web lifecycle: the browser Remote listener starts with the native listeners and its sockets become peers.
extension HostService {
    // Cadenza Web is optional. Its failure leaves native Remotes working, so it reports an issue instead of failing start.
    func startWebRemote() async {
        webRemote.stop()
        guard configuration.webEnabled else { return }
        let port = configuration.webPort
        let root = HostResources.bundle.resourceURL?.appendingPathComponent(
            "Resources/WebRemote", isDirectory: true)
        guard let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) else {
            onIssue?("Cadenza Web is not bundled in this build, so the browser Remote is unavailable.")
            return
        }
        let advertised = configuration.advertisedAddress
        do {
            try await webRemote.start(
                port: port, bundle: WebRemoteBundle(root: root),
                allowedHosts: { Self.webAllowedHosts(port: port, advertised: advertised) })
        } catch {
            logger.log(
                .warning, category: "network", action: "web.failed", "Cadenza Web could not start",
                metadata: ["port": String(port)])
            onIssue?("Cadenza Web could not start on port \(port). Check that the port is free.")
        }
    }

    // Host names a browser may use. Anything else, including a DNS name that points here, is refused.
    static func webAllowedHosts(port: UInt16, advertised: String) -> Set<String> {
        var hosts = Set(LANAddresses.all().map { "\($0):\(port)" })
        if !advertised.isEmpty { hosts.insert("\(advertised):\(port)") }
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
