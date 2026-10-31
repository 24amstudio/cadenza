import Foundation

// One Remote log entry. A log.report frame carries a batch of these under log_entries.
struct LogReportEntry: Codable, Sendable {
    var level: String
    var action: String
    var message: String
}

struct Frame: Codable, Sendable {
    var version: Int = 1
    var type: String
    var requestId: String? = nil
    var commandId: String? = nil
    var hostEpoch: String? = nil
    var expiresAtHostMs: Int64? = nil
    var expectedRevision: Int64? = nil
    var action: CommandAction? = nil
    var name: String? = nil
    var heartbeat: Bool? = nil
    var auth: DeviceAuth? = nil
    var pair: PairRequest? = nil
    var welcome: Welcome? = nil
    var transport: TransportPolicy? = nil
    var status: SessionStatus? = nil
    var snapshot: HostSnapshot? = nil
    var query: String? = nil
    var scope: String? = nil
    var updateAction: String? = nil
    var updateState: String? = nil
    var updateVersion: String? = nil
    var songs: [Song]? = nil
    var terms: [String]? = nil
    var lyrics: LyricDocument? = nil
    var clock: ClockSample? = nil
    var errorCode: String? = nil
    var message: String? = nil
    var outcome: String? = nil
    var resolved: Bool? = nil
    var revision: Int64? = nil
    var eventId: String? = nil
    var sequence: Int64? = nil
    var occurrenceId: String? = nil
    var song: SongIdentity? = nil
    var songMetadata: Song? = nil
    var playCountDelta: Int? = nil
    var playedMsDelta: Int64? = nil
    var logAction: String? = nil
    var logLevel: String? = nil
    var logMessage: String? = nil
    var logEntries: [LogReportEntry]? = nil
    var artworkUrl: String? = nil
    var artworkDataBase64: String? = nil
    var sing: SingSession? = nil
    var recommendationPassport: SignedRecommendationPassport? = nil
    var recommendationQuery: RecommendationQuery? = nil
    var recommendationResult: RecommendationResult? = nil
    var recommendationFeedback: RecommendationFeedback? = nil
    var recommendationPlan: RecommendationPlanEnvelope? = nil
    var recommendationShadowObservation: RecommendationShadowObservation? = nil
>>>>>>> origin/main
    var chunkIndex: Int? = nil
    var chunkCount: Int? = nil
    var totalBytes: Int? = nil
    var sha256: String? = nil
    var dataBase64: String? = nil
}

struct RecommendationQuery: Codable, Sendable {
    var intent: String?
    var horizon: Int
    var filters: RecommendationFilters
    var modelVersion: Int
}

struct RecommendationFilters: Codable, Sendable {
    var explicitAllowed: Bool
    var locked: Bool
}

struct RecommendationPlanEnvelope: Codable, Sendable {
    var planId: String
    var recommendationId: String
    var passportSequence: Int64
    var modelVersion: Int
    var expectedRevision: Int64
    var operation: CommandAction
}
