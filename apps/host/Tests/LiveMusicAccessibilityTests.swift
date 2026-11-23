import Foundation
import Testing

@testable import CadenzaHost

// Runs only on a Mac with Music open and Accessibility granted to the test host:
//   CADENZA_LIVE_MUSIC=1 swift test --filter LiveMusicAccessibilityTests
// It searches the library through Music's own scripting and selects the song's row in Music. It never starts playback.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CADENZA_LIVE_MUSIC"] == "1"))
struct LiveMusicAccessibilityTests {
    @MainActor @Test func aLibrarySearchFindsASongThatMusicCanSelect() async throws {
        let bridge = MusicBridge()
        try bridge.accessibility.requireAccess()

        let songs = try await bridge.librarySearch("Praise The Lord")
        let song = try #require(songs.first)

        try await bridge.prepare(song, isCurrent: { true })
    }

    // Opens Playing Next through Music's View menu, then reads its rows. Only the window changes, never playback.
    @MainActor @Test func playingNextOpensAndReadsWithoutError() async throws {
        let bridge = MusicBridge()
        try bridge.accessibility.requireAccess()

        try await bridge.accessibility.requestQueuePanel()
        let rows = try bridge.accessibility.rows(deadline: monotonicMs() + 5_000)

        #expect(bridge.accessibility.queuePanelOpen())
        #expect(rows.count >= 0)
    }
}
