import Foundation

extension HostService {
    fileprivate func deliverCredits() {
        for peer in network.peers.values where peer.authenticated { sendCredits(peer) }
    }

    fileprivate func sendCredits(_ peer: NetworkService.Peer) {
        guard let actor = peer.remoteId else { return }
        let sent = lastCreditSent[peer.id] ?? 0
        let acknowledged = acknowledgedCredits[peer.id] ?? 0
        guard sent - acknowledged < 8 else { return }
        do {
            let available = 8 - Int(sent - acknowledged)
            for frame in try store.credits(actor, after: sent).prefix(available) {
                network.send(frame, to: peer)
                lastCreditSent[peer.id] = frame.sequence
            }
        } catch { onIssue?(error.localizedDescription) }
    }
}
