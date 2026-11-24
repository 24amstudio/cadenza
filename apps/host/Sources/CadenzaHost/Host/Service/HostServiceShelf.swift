import Foundation

extension HostService {
    /// Sends a read-only list of ranked suggestions for a Remote's shelves. Nothing is queued or planned for it. A Remote
    /// without a passport is ranked from the Host's taste ledger alone. The reply echoes the request id it answers.
    func sendRecommendationShelf(
        _ query: RecommendationQuery, requestId: String?, actor: String, peer: NetworkService.Peer
    ) throws {
        let mode = try store.recommendationMode
        guard try store.creeEnabled, mode != "disabled", mode != "paused" else {
            network.send(
                Frame(type: "recommendation.result", requestId: requestId, errorCode: "planning_paused"), to: peer)
            return
        }
        let profile = (try? store.recommendationProfile(remoteId: actor)) ?? .blank(remoteId: actor)
        let snapshot = try queue.snapshot()
        let (_, ranked) = rankedRecommendations(query, profile: profile, actor: actor, snapshot: snapshot)
        network.send(
            Frame(
                type: "recommendation.result", requestId: requestId,
                recommendationShelf: RecommendationShelf.make(from: ranked)),
            to: peer)
    }
}
