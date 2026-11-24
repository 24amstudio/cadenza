import Foundation

/// Detects a Host that keeps crashing soon after it starts. Each launch that follows an unclean exit is recorded
/// with its wall-clock time. Three launches within thirty seconds enter safe recovery, where automatic Music polling
/// stays off until the user resumes it from Logs. A clean exit ends the streak.
enum CrashLoopGuard {
    static let windowMs: Int64 = 30_000
    static let launchLimit = 3
    private static let launchesKey = "cadenza.crashLoop.launchTimesMs"
    private static let recoveryKey = "cadenza.crashLoop.safeRecovery"

    /// The launch times that still fall inside the window, followed by `nowMs`.
    static func launches(recording nowMs: Int64, after previous: [Int64]) -> [Int64] {
        previous.filter { $0 <= nowMs && nowMs - $0 < windowMs } + [nowMs]
    }

    static func entersSafeRecovery(_ launches: [Int64]) -> Bool {
        launches.count >= launchLimit
    }

    static func recordLaunch(nowMs: Int64, defaults: UserDefaults = .standard) {
        let previous = (defaults.array(forKey: launchesKey) as? [NSNumber] ?? []).map(\.int64Value)
        let updated = launches(recording: nowMs, after: previous)
        defaults.set(updated.map { NSNumber(value: $0) }, forKey: launchesKey)
        if entersSafeRecovery(updated) { defaults.set(true, forKey: recoveryKey) }
    }

    static func recordCleanExit(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: launchesKey)
    }

    static func safeRecoveryActive(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: recoveryKey)
    }

    static func resumeAutomaticMusicPolling(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: recoveryKey)
        defaults.removeObject(forKey: launchesKey)
    }
}
