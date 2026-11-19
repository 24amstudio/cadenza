import Foundation

/// Confirms a playback action by reading Music's state until it shows the requested result. Music applies an action a
/// moment after its script returns, so a single readback taken right after dispatch can report the old state. A
/// transient mismatch is retried inside the budget, and only a state that never arrives is reported as unconfirmed.
enum TransportConfirmation {
    /// A song that restarts at its beginning counts as skipped when its position falls back by at least this much.
    static let restartDropMs: Int64 = 2_000
    static let seekToleranceMs: Int64 = 1_000
    static let pollIntervalMs = 90

    /// Whether `status` shows `action` applied. `before` is the state read before dispatch and `elapsedMs` is the time
    /// since dispatch, which a playing position keeps advancing through.
    static func isConfirmed(
        _ action: CommandAction, status: MusicStatus, before: MusicStatus?, elapsedMs: Int64
    ) -> Bool {
        switch action.kind {
        case "playback.pause": return !status.playing
        case "playback.resume": return status.playing
        case "playback.stop": return status.state == "stopped"
        case "playback.seek":
            let target = action.positionMs ?? 0
            let drift = status.playing ? elapsedMs : 0
            let latest = target + seekToleranceMs + drift
            return status.positionMs >= target - seekToleranceMs && status.positionMs <= latest
        case "playback.volume": return abs(status.volume - (action.percent ?? -1)) <= 1
        case "playback.shuffle": return status.shuffle == action.enabled
        case "playback.repeat": return status.repeat == action.mode
        case "playback.skip", "playback.previous":
            guard let before else { return false }
            return status.state == "stopped" || status.song?.identity != before.song?.identity
                || before.positionMs - status.positionMs >= restartDropMs
        default: return true
        }
    }

    /// Reads state until it confirms `action` or `deadline` passes. `first` is the state the dispatch script returned.
    /// Returns the confirming state, or nil with the last state read when the budget ran out.
    @MainActor
    static func awaitConfirmation(
        _ action: CommandAction, before: MusicStatus?, first: MusicStatus?, dispatchedAtMs: Int64, deadline: Int64,
        intervalMs: Int = pollIntervalMs, read: () async throws -> MusicStatus
    ) async -> (confirmed: MusicStatus?, last: MusicStatus?) {
        var last = first
        while true {
            if let status = last,
                isConfirmed(action, status: status, before: before, elapsedMs: monotonicMs() - dispatchedAtMs)
            {
                return (status, status)
            }
            guard monotonicMs() < deadline, !Task.isCancelled else { return (nil, last) }
            try? await Task.sleep(for: .milliseconds(intervalMs))
            if let status = try? await read() { last = status }
        }
    }
}
