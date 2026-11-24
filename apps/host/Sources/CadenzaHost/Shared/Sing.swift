import Foundation

/// Host-owned state for the optional local stem-processing route.
/// Audio is never transported over the Remote session.
struct SingSession: Codable, Equatable, Sendable {
    var status: String
    var vocalPercent: Int
    var latencyMs: Int64?
    var backend: String?
    var modelRevision: String?
    var issue: String?
    /// Whether the verified Sing model is installed on this Host. Optional, so older Remotes ignore it.
    var modelReady: Bool?

    init(
        status: String = "unavailable",
        vocalPercent: Int = 0,
        latencyMs: Int64? = nil,
        backend: String? = nil,
        modelRevision: String? = nil,
        issue: String? = nil,
        modelReady: Bool? = nil
    ) {
        self.status = status
        self.vocalPercent = vocalPercent
        self.latencyMs = latencyMs
        self.backend = backend
        self.modelRevision = modelRevision
        self.issue = issue
        self.modelReady = modelReady
    }
}
