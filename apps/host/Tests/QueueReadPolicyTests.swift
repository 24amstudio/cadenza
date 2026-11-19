import Foundation
import Testing

@testable import CadenzaHost

struct QueueReadPolicyTests {
    private func decide(
        _ policy: inout QueueReadPolicy, now: Int64 = 100_000, lastReadAt: Int64? = nil, verified: Bool = false,
        trackChanged: Bool = false, idle: Bool = true, permitted: Bool = true, pid: pid_t? = 42,
        panelOpen: Bool = true
    ) -> QueueReadPolicy.Decision {
        policy.decide(
            now: now, lastReadAt: lastReadAt, verified: verified, trackChanged: trackChanged, idle: idle,
            permitted: permitted, musicPid: pid, panelOpen: { panelOpen })
    }

    @Test func readsTheQueueOnStartupWhenPlayingNextIsVisible() {
        var policy = QueueReadPolicy()

        #expect(decide(&policy) == .read)
    }

    @Test func opensPlayingNextOncePerMusicProcessThenExplainsHowToShowIt() {
        var policy = QueueReadPolicy()

        #expect(decide(&policy, panelOpen: false) == .openPanelThenRead)
        #expect(decide(&policy, panelOpen: false) == .blocked(QueueReadPolicy.panelClosedMessage))
        // A relaunched Music is a new process, so its panel may be opened again.
        #expect(decide(&policy, pid: 43, panelOpen: false) == .openPanelThenRead)
    }

    @Test func aVerifiedQueueIsReadAgainOnTrackChangeOrAfterTheInterval() {
        var policy = QueueReadPolicy()
        let last: Int64 = 100_000
        let early = last + QueueReadPolicy.verifiedIntervalMs - 1
        let late = last + QueueReadPolicy.verifiedIntervalMs

        #expect(decide(&policy, now: early, lastReadAt: last, verified: true) == .skip)
        #expect(decide(&policy, now: early, lastReadAt: last, verified: true, trackChanged: true) == .read)
        #expect(decide(&policy, now: late, lastReadAt: last, verified: true) == .read)
    }

    @Test func aHiddenPanelKeepsTheLastVerifiedReadWithoutWarning() {
        var policy = QueueReadPolicy()
        _ = decide(&policy, panelOpen: false)

        #expect(decide(&policy, lastReadAt: 0, verified: true, panelOpen: false) == .skip)
    }

    @Test func reportsAccessAndAvailabilityOnlyWhileTheQueueIsUnverified() {
        var policy = QueueReadPolicy()

        #expect(decide(&policy, permitted: false) == .blocked(QueueReadPolicy.permissionMessage))
        #expect(decide(&policy, pid: nil) == .blocked(QueueReadPolicy.notRunningMessage))
        #expect(decide(&policy, verified: true, permitted: false) == .skip)
        #expect(decide(&policy, idle: false) == .skip)
    }
}
