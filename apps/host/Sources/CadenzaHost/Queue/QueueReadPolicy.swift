import Foundation

/// Decides when the background refresh reads Music's Playing Next list. The queue is read on startup, when the track
/// changes, and on a bounded interval. Music's Playing Next panel is opened at most once per Music process; after that
/// a closed panel keeps the last read until the user shows it again or a queue action opens it.
struct QueueReadPolicy {
    enum Decision: Equatable {
        case skip
        case read
        case openPanelThenRead
        /// The queue cannot be read, and the message says what the user can do about it.
        case blocked(String)
    }

    static let verifiedIntervalMs: Int64 = 10_000
    static let retryIntervalMs: Int64 = 3_000
    static let permissionMessage =
        "Allow Cadenza Host in Privacy & Security → Accessibility so it can read Music's queue."
    static let notRunningMessage = "Music is not running. Open Music so Cadenza Host can read its queue."
    static let panelClosedMessage =
        "Cadenza Host cannot read Music's queue while Playing Next is hidden. In Music, choose View → Show Playing Next."

    private var openedPanelForPid: pid_t?

    /// `panelOpen` is read lazily, because it costs Accessibility calls that a verified, up-to-date queue never needs.
    mutating func decide(
        now: Int64, lastReadAt: Int64?, verified: Bool, trackChanged: Bool, idle: Bool, permitted: Bool,
        musicPid: pid_t?, panelOpen: () -> Bool
    ) -> Decision {
        guard idle else { return .skip }
        guard permitted else { return verified ? .skip : .blocked(Self.permissionMessage) }
        guard let pid = musicPid else { return verified ? .skip : .blocked(Self.notRunningMessage) }
        let interval = verified ? Self.verifiedIntervalMs : Self.retryIntervalMs
        let due = trackChanged || lastReadAt.map { now - $0 >= interval } ?? true
        if verified && !due { return .skip }
        if panelOpen() { return due ? .read : .skip }
        if openedPanelForPid != pid {
            openedPanelForPid = pid
            return .openPanelThenRead
        }
        return verified ? .skip : .blocked(Self.panelClosedMessage)
    }
}
