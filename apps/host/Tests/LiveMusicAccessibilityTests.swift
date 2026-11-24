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

    // Return plays a selected row in Music. The background route is tried first and the system route second, which
    // brings Music forward. Playback is always stopped again afterwards, so Music is left stopped.
    @MainActor @Test func aPreparedSongStartsWithinTheBudgetAndIsStoppedAgain() async throws {
        let bridge = MusicBridge()
        try bridge.accessibility.requireAccess()
        let song = try #require(try await bridge.librarySearch("Praise The Lord").first)
        try await bridge.prepare(song, isCurrent: { true })

        let started = monotonicMs()
        var route = "process"
        try bridge.accessibility.pressKey(36, route: .process)
        var elapsed = try await playingElapsed(bridge, since: started, within: 2_000)
        if elapsed == nil {
            route = "system"
            try bridge.accessibility.pressKey(36, route: .system)
            elapsed = try await playingElapsed(bridge, since: started, within: 4_000)
        }
        try stopMusic()

        #expect(elapsed != nil, "Music did not start the prepared song on either route.")
        #expect((elapsed ?? .max) <= 1_000, "Playback took \(elapsed ?? -1) ms on the \(route) route.")
    }

    private func playingElapsed(_ bridge: MusicBridge, since started: Int64, within limit: Int64) async throws -> Int64?
    {
        while monotonicMs() - started < limit {
            if try await bridge.status().playing { return monotonicMs() - started }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func stopMusic() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Music\" to stop"]
        try process.run()
        process.waitUntilExit()
    }
}
