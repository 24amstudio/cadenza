import Foundation

extension HostService {
    /// Answers `browse.get` asynchronously, like a search. `operation.cancel` stops it through `jobs`.
    func startBrowse(_ frame: Frame, peer: NetworkService.Peer) {
        guard let requestId = frame.requestId, case .request(let request)? = frame.browse else {
            fail(
                CadenzaError.failure("invalid_command", "Choose an album, artist, or playlist."), request: frame,
                peer: peer)
            return
        }
        guard jobs.count < 16 else {
            fail(CadenzaError.failure("busy", "Too many searches are running."), request: frame, peer: peer)
            return
        }
        let key = peer.id + requestId
        jobs[key]?.cancel()
        network.send(Frame(type: "operation.started", requestId: requestId), to: peer)
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            let startedAt = monotonicMs()
            do {
                var result = try await self.browse.result(for: request)
                try Task.checkCancellation()
                if peer.transport == "ble" { result = result.bounded(forBluetooth: true) }
                self.queue.remember(result.songs)
                self.logger.log(
                    .info, category: "catalog", action: "browse.completed", "Browse returned \(result.title)",
                    remoteVersion: peer.remoteVersion,
                    metadata: [
                        "kind": request.kind, "sections": String(result.sections.count),
                        "ms": String(monotonicMs() - startedAt), "remote_id": peer.remoteId ?? "",
                    ])
                self.network.send(
                    Frame(type: "browse.result", requestId: requestId, browse: .result(result)), to: peer)
            } catch {
                if !Task.isCancelled { self.fail(error, request: frame, peer: peer) }
            }
        }
    }
}
