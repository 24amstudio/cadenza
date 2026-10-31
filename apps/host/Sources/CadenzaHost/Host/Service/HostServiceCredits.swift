import Foundation

extension HostService {
    fileprivate func acknowledge(_ frame: Frame, peer: NetworkService.Peer, actor: String) throws {
        guard let sequence = frame.sequence, sequence >= (acknowledgedCredits[peer.id] ?? 0),
            sequence <= (lastCreditSent[peer.id] ?? 0)
        else {
            throw CadenzaError.failure("invalid_command", "Invalid analytics acknowledgment.")
        }
        try store.acknowledge(actor, through: sequence)
        acknowledgedCredits[peer.id] = sequence
        sendCredits(peer)
    }

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
