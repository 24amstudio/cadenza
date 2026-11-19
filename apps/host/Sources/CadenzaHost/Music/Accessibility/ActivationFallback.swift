import Foundation

/// The one place where Cadenza Host may pull focus to Music. Steps run in order; quiet steps never touch focus.
/// The first activating step brings Music forward, and whatever was frontmost before is handed focus back when the
/// whole run ends, whether it succeeded, failed or was cancelled.
@MainActor
struct ActivationFallback {
    enum Tier { case quiet, activating }

    struct Step<Value> {
        let name: String
        let tier: Tier
        /// Receives the time this attempt may use. Throwing a recoverable error moves on to the next step.
        let run: (_ deadline: Int64) async throws -> Value
    }

    static let musicBundleId = "com.apple.Music"
    static let activationLimitMs: Int64 = 1_500
    static let restoreLimitMs: Int64 = 500
    static let pollMs: Int64 = 20
    /// Errors that mean "this way did not work", as opposed to a refusal or a failure no other step can fix.
    static let recoverableCodes: Set<String> = ["native_queue_unavailable", "music_window_unavailable"]

    var applications: any FrontApplications
    var now: () -> Int64
    var sleep: (Int64) async throws -> Void
    var report: (_ action: String, _ message: String) -> Void = { _, _ in }

    static func live(report: @escaping (String, String) -> Void) -> ActivationFallback {
        ActivationFallback(
            applications: WorkspaceApplications(), now: monotonicMs,
            sleep: { try await Task.sleep(for: .milliseconds($0)) }, report: report)
    }

    func run<Value>(deadline: Int64, steps: [Step<Value>]) async throws -> Value {
        var handBack: FrontApplication?
        do {
            let value = try await attempt(deadline: deadline, steps: steps, handBack: &handBack)
            await restore(handBack)
            return value
        } catch {
            await restore(handBack)
            throw error
        }
    }

    private func attempt<Value>(
        deadline: Int64, steps: [Step<Value>], handBack: inout FrontApplication?
    ) async throws -> Value {
        var failures: [String] = []
        var lastCode = "native_queue_unavailable"
        var activated = false
        for (index, step) in steps.enumerated() {
            try Task.checkCancellation()
            if step.tier == .activating, !activated {
                activated = true
                handBack = try await bringMusicForward(deadline: deadline)
            }
            // Each remaining step gets an equal share of the time that is left; the last one gets all of it.
            let attemptDeadline = now() + max(0, deadline - now()) / Int64(steps.count - index)
            do {
                return try await step.run(attemptDeadline)
            } catch let error as CadenzaError where isRecoverable(error, deadline: deadline) {
                failures.append("\(step.name): \(error.localizedDescription)")
                lastCode = error.code
            }
        }
        throw CadenzaError.failure(lastCode, failures.joined(separator: " "))
    }

    /// An attempt that ran out of its own share expires with the command still alive; that is recoverable too.
    private func isRecoverable(_ error: CadenzaError, deadline: Int64) -> Bool {
        Self.recoverableCodes.contains(error.code) || (error.code == "expired" && now() < deadline)
    }

    /// Returns the application to hand focus back to, or nil when Music was already frontmost.
    private func bringMusicForward(deadline: Int64) async throws -> FrontApplication? {
        guard let music = applications.running(bundleId: Self.musicBundleId) else {
            throw CadenzaError.failure("music_unavailable", "Music is not running. Open Music, then try again.")
        }
        let previous = applications.frontmost
        if previous?.bundleId == Self.musicBundleId { return nil }
        applications.activate(music)
        report("focus.activated", "Brought Music forward because no focus-neutral step worked")
        let limit = min(deadline, now() + Self.activationLimitMs)
        while applications.frontmost?.bundleId != Self.musicBundleId {
            guard now() < limit else {
                await restore(previous)
                throw CadenzaError.failure("native_queue_unavailable", "Music did not come to the front in time.")
            }
            try await sleepOrRestore(previous)
        }
        return previous
    }

    private func sleepOrRestore(_ previous: FrontApplication?) async throws {
        do {
            try await sleep(Self.pollMs)
        } catch {
            await restore(previous)
            throw error
        }
    }

    /// Focus is handed back only while Music still holds it, so a user who already moved on is left alone.
    private func restore(_ application: FrontApplication?) async {
        guard let application, applications.frontmost?.bundleId == Self.musicBundleId else { return }
        applications.activate(application)
        report("focus.restored", "Returned focus to the previously active application")
        let limit = now() + Self.restoreLimitMs
        while applications.frontmost?.processId != application.processId, now() < limit {
            do { try await sleep(Self.pollMs) } catch { return }
        }
    }
}
