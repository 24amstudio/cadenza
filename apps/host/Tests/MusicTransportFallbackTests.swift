import Testing

@testable import CadenzaHost

struct MusicTransportFallbackTests {
    @Test func onlyAnAutomationRefusalMayFallBack() {
        #expect(
            MusicTransportFallback.isAutomationDenial(
                CadenzaError.failure("music_unavailable", "Not authorized to send Apple events to Music. (-1743)")))
        #expect(
            !MusicTransportFallback.isAutomationDenial(
                CadenzaError.failure("music_unavailable", "Music is not running.")))
        #expect(
            !MusicTransportFallback.isAutomationDenial(
                CadenzaError.failure("outcome_unknown", "Music did not confirm the action (-1743)")))
    }

    @Test func pauseAndResumeUseOnlyTheExplicitCommands() {
        #expect(MusicTransportFallback.mediaRemoteCommand(for: "playback.pause") == .pause)
        #expect(MusicTransportFallback.mediaRemoteCommand(for: "playback.resume") == .play)
        #expect(MusicTransportFallback.mediaKey(for: "playback.pause") == nil)
        #expect(MusicTransportFallback.mediaKey(for: "playback.resume") == nil)
    }

    @Test func nextAndPreviousHaveAMediaKeyFallbackAndNoOtherAction() {
        #expect(MusicTransportFallback.mediaKey(for: "playback.skip") == .next)
        #expect(MusicTransportFallback.mediaKey(for: "playback.previous") == .previous)
        #expect(MusicTransportFallback.mediaRemoteCommand(for: "playback.seek") == nil)
        #expect(MusicTransportFallback.mediaKey(for: "playback.seek") == nil)
    }
}
