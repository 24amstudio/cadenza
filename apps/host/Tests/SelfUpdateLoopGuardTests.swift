import Testing

@testable import CadenzaHost

struct SelfUpdateLoopGuardTests {
    @Test func aTargetThatFailedTwiceIsNotRetriedUntilANewerBuildAppears() {
        var record: SelfUpdateLoopGuard.Record?
        for _ in 0..<SelfUpdateLoopGuard.attemptLimit {
            #expect(SelfUpdateLoopGuard.allowsAttempt(for: 13, record: record))
            record = SelfUpdateLoopGuard.recordingAttempt(for: 13, after: record)
        }

        #expect(!SelfUpdateLoopGuard.allowsAttempt(for: 13, record: record))
        #expect(SelfUpdateLoopGuard.allowsAttempt(for: 14, record: record))
    }

    @Test func aSuccessfulInstallClearsTheRecordWhenTheTargetIsRunning() {
        let record = SelfUpdateLoopGuard.Record(targetBuild: 13, attempts: 1)

        #expect(SelfUpdateLoopGuard.settled(record, runningBuild: 13) == nil)
        #expect(SelfUpdateLoopGuard.settled(record, runningBuild: 12) == record)
    }

    @Test func aNewerTargetStartsWithAFreshCount() {
        let record = SelfUpdateLoopGuard.Record(targetBuild: 13, attempts: 2)

        #expect(
            SelfUpdateLoopGuard.recordingAttempt(for: 14, after: record)
                == SelfUpdateLoopGuard.Record(targetBuild: 14, attempts: 1))
    }
}
