import Foundation
import Testing

@testable import CadenzaHost

struct CrashLoopGuardTests {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "CrashLoopGuardTests-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func aLaunchOlderThanTheWindowIsForgotten() {
        #expect(CrashLoopGuard.launches(recording: 30_000, after: [0]) == [30_000])
        #expect(CrashLoopGuard.launches(recording: 29_999, after: [0]) == [0, 29_999])
    }

    @Test func threeLaunchesInsideThirtySecondsEnterSafeRecovery() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        CrashLoopGuard.recordLaunch(nowMs: 0, defaults: defaults)
        CrashLoopGuard.recordLaunch(nowMs: 10_000, defaults: defaults)
        #expect(!CrashLoopGuard.safeRecoveryActive(defaults: defaults))

        CrashLoopGuard.recordLaunch(nowMs: 20_000, defaults: defaults)
        #expect(CrashLoopGuard.safeRecoveryActive(defaults: defaults))
    }

    @Test func launchesSpreadOverLongerThanTheWindowDoNotEnterSafeRecovery() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        CrashLoopGuard.recordLaunch(nowMs: 0, defaults: defaults)
        CrashLoopGuard.recordLaunch(nowMs: 20_000, defaults: defaults)
        CrashLoopGuard.recordLaunch(nowMs: 40_000, defaults: defaults)

        #expect(!CrashLoopGuard.safeRecoveryActive(defaults: defaults))
    }

    @Test func aCleanExitEndsTheStreakBeforeTheNextLaunch() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        CrashLoopGuard.recordLaunch(nowMs: 0, defaults: defaults)
        CrashLoopGuard.recordLaunch(nowMs: 10_000, defaults: defaults)
        CrashLoopGuard.recordCleanExit(defaults: defaults)
        CrashLoopGuard.recordLaunch(nowMs: 20_000, defaults: defaults)

        #expect(!CrashLoopGuard.safeRecoveryActive(defaults: defaults))
    }

    @Test func safeRecoveryPersistsUntilTheUserResumesPolling() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        for now in [Int64(0), 5_000, 10_000] {
            CrashLoopGuard.recordLaunch(nowMs: now, defaults: defaults)
        }
        CrashLoopGuard.recordCleanExit(defaults: defaults)
        #expect(CrashLoopGuard.safeRecoveryActive(defaults: defaults))

        CrashLoopGuard.resumeAutomaticMusicPolling(defaults: defaults)
        #expect(!CrashLoopGuard.safeRecoveryActive(defaults: defaults))
    }
}
