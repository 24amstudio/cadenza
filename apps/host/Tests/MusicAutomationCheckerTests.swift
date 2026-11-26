import Foundation
import Synchronization
import Testing

@testable import CadenzaHost

@MainActor
struct MusicAutomationCheckerTests {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "cadenza.tests.automation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func remembered(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: MusicAutomationChecker.previouslyGrantedKey)
    }

    @Test func aLiveGrantIsShownAndRemembered() async {
        let defaults = isolatedDefaults()
        let checker = MusicAutomationChecker(defaults: defaults, probe: { _ in noErr })

        #expect(await checker.refresh(promptUser: false) == .granted)
        #expect(remembered(defaults))
    }

    @Test func aRememberedGrantIsShownAtLaunchBeforeAnyProbe() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: MusicAutomationChecker.previouslyGrantedKey)

        #expect(MusicAutomationChecker(defaults: defaults, probe: { _ in -1743 }).state == .granted)
    }

    @Test func aClosedMusicKeepsARememberedGrant() async {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: MusicAutomationChecker.previouslyGrantedKey)
        let checker = MusicAutomationChecker(defaults: defaults, probe: { _ in -600 })

        #expect(await checker.refresh(promptUser: false) == .granted)
        #expect(remembered(defaults))
    }

    @Test func aClosedMusicWithoutARememberedGrantIsNotCheckedNotDenied() async {
        let checker = MusicAutomationChecker(defaults: isolatedDefaults(), probe: { _ in -600 })

        #expect(await checker.refresh(promptUser: false) == .notChecked)
    }

    @Test func aRunningMusicThatRefusesDowngradesTheGrantToDenied() async {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: MusicAutomationChecker.previouslyGrantedKey)
        let checker = MusicAutomationChecker(defaults: defaults, probe: { _ in -1743 })

        #expect(await checker.refresh(promptUser: false) == .needed)
        #expect(!remembered(defaults))
    }

    @Test func aRunningMusicThatNeedsConsentIsAlsoDenied() async {
        let checker = MusicAutomationChecker(defaults: isolatedDefaults(), probe: { _ in -1744 })

        #expect(await checker.refresh(promptUser: false) == .needed)
    }

    @Test func aSuccessfulMusicCommandMarksTheGrantInMemoryAndOnDisk() {
        let defaults = isolatedDefaults()
        let checker = MusicAutomationChecker(defaults: defaults, probe: { _ in -600 })

        checker.markGranted()

        #expect(checker.state == .granted)
        #expect(remembered(defaults))
    }

    @Test func passiveRefreshesNeverRequestTheConsentPrompt() async {
        let prompts = Mutex<[Bool]>([])
        let checker = MusicAutomationChecker(
            defaults: isolatedDefaults(),
            probe: { promptUser in
                prompts.withLock { $0.append(promptUser) }
                return -600
            })

        await checker.refresh(promptUser: false)
        await checker.refresh(promptUser: true)

        #expect(prompts.withLock { $0 } == [false, true])
    }
}
