import Foundation

enum RecommendationProvenance: String, Codable, Sendable {
    case user
    case appleAutoplay = "apple_autoplay"
    case cadenza
    case unknown
}

struct RecommendationNativeObservation: Sendable {
    var nativeLabel: String?
    var currentSong: SongIdentity?
    var queueSong: SongIdentity?
    var isMixing: Bool
}

enum RecommendationProvenanceResolver {
    static func resolve(_ observation: RecommendationNativeObservation) -> (RecommendationProvenance, Double) {
        guard observation.isMixing, let label = observation.nativeLabel?.lowercased() else {
            return (.unknown, 0)
        }
        let reliable = label.contains("automix") || label.contains("autoplay") || label.contains("infinite")
        guard reliable, observation.queueSong != observation.currentSong else { return (.unknown, 0) }
        return (.appleAutoplay, 0.95)
    }
}
