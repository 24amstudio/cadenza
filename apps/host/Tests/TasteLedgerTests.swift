import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct TasteLedgerTests {
    private func database() throws -> (Database, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-taste-" + UUID().uuidString)
        let database = try Database(url: directory.appendingPathComponent("test.sqlite"))
        return (database, directory)
    }

    private func pair(_ database: Database, _ remote: String) throws {
        _ = try database.run(
            "INSERT INTO paired_remotes(remote_id,display_name,credential_reference,paired_at_ms) VALUES(?,?,?,?)",
            [.text(remote), .text("Remote " + remote), .text("host." + remote), .integer(0)])
    }

    @Test func aSkipOnlyLowersTheRemoteThatSkipped() throws {
        let (database, directory) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        try pair(database, "remote-a")
        try pair(database, "remote-b")
        let ledger = TasteLedger(database: database)
        let now = Date()

        try ledger.record(
            remoteId: "remote-a", signal: .playNow, artist: "artist-x", track: "t1", at: now, bucket: .evening)
        try ledger.record(
            remoteId: "remote-a", signal: .earlySkip, artist: "artist-x", track: "t1", at: now, bucket: .evening)
        try ledger.record(
            remoteId: "remote-b", signal: .playNow, artist: "artist-x", track: "t1", at: now, bucket: .evening)

        let skipped = try #require(ledger.affinities(remoteId: "remote-a", now: now)["artist-x"])
        let other = try #require(ledger.affinities(remoteId: "remote-b", now: now)["artist-x"])

        #expect(abs(skipped - (3.0 - 2.0) / 3) < 0.0001)
        #expect(abs(other - 1.0) < 0.0001)
    }

    @Test func aRecentSignalCountsForMoreThanAnOldOne() throws {
        let (database, directory) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        try pair(database, "remote-a")
        let ledger = TasteLedger(database: database)
        let now = Date()
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)

        try ledger.record(
            remoteId: "remote-a", signal: .playNow, artist: "old", track: "t1", at: twoWeeksAgo, bucket: .morning)
        try ledger.record(
            remoteId: "remote-a", signal: .playNow, artist: "new", track: "t2", at: now, bucket: .morning)
        let scores = try ledger.affinities(remoteId: "remote-a", now: now)

        #expect(abs((scores["old"] ?? 0) - 0.5) < 0.01)
        #expect(abs((scores["new"] ?? 0) - 1.0) < 0.01)
    }

    @Test func aTimeOfDayCountsOnlyWhatThatRemotePlayedAndDidNotSkip() throws {
        let (database, directory) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        try pair(database, "remote-a")
        try pair(database, "remote-b")
        let ledger = TasteLedger(database: database)
        let now = Date()

        try ledger.record(
            remoteId: "remote-a", signal: .playNow, artist: "evening-artist", track: "t1", at: now, bucket: .evening)
        try ledger.record(
            remoteId: "remote-a", signal: .earlySkip, artist: "skipped-artist", track: "t2", at: now, bucket: .evening)
        try ledger.record(
            remoteId: "remote-a", signal: .playNow, artist: "morning-artist", track: "t3", at: now, bucket: .morning)

        let evening = try ledger.artists(remoteId: "remote-a", bucket: .evening)
        let otherRemote = try ledger.artists(remoteId: "remote-b", bucket: .evening)

        #expect(evening == ["evening-artist"])
        #expect(otherRemote.isEmpty)
    }

    @Test func aPlayNowOfAnAutoPlaySongCountsAsAnAutoPlayChoiceAndOtherRequestsKeepTheirSignal() {
        #expect(TasteSignal.played(.playNow, fromAutoPlay: true) == .autoplayPlay)
        #expect(TasteSignal.played(.playNow, fromAutoPlay: false) == .playNow)
        #expect(TasteSignal.played(.playNext, fromAutoPlay: true) == .playNext)
    }

    @Test func aSongEndingIsAnEarlySkipOrACompletionAndRadioEarnsNeither() {
        #expect(TasteSignal.ending(positionMs: 10_000, durationMs: 200_000, isLiveRadio: false) == .earlySkip)
        #expect(TasteSignal.ending(positionMs: 180_000, durationMs: 200_000, isLiveRadio: false) == .completion)
        #expect(TasteSignal.ending(positionMs: 100_000, durationMs: 200_000, isLiveRadio: false) == nil)
        #expect(TasteSignal.ending(positionMs: 19_000, durationMs: 20_000, isLiveRadio: false) == .completion)
        #expect(TasteSignal.ending(positionMs: 10_000, durationMs: nil, isLiveRadio: false) == nil)
        #expect(TasteSignal.ending(positionMs: 10_000, durationMs: 200_000, isLiveRadio: true) == nil)
    }

    @Test func onlyTheThreeQueueRequestsCarryTaste() {
        #expect(TasteSignal(commandKind: "queue.play_now") == .playNow)
        #expect(TasteSignal(commandKind: "queue.play_next") == .playNext)
        #expect(TasteSignal(commandKind: "queue.enqueue") == .enqueue)
        #expect(TasteSignal(commandKind: "playback.pause") == nil)
        #expect(TasteSignal(commandKind: "library.favorite") == nil)
    }

    @Test func timeOfDayBucketsCoverTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func hour(_ value: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: value))!
        }

        #expect(TasteBucket.bucket(for: hour(7), calendar: calendar) == .morning)
        #expect(TasteBucket.bucket(for: hour(14), calendar: calendar) == .afternoon)
        #expect(TasteBucket.bucket(for: hour(19), calendar: calendar) == .evening)
        #expect(TasteBucket.bucket(for: hour(2), calendar: calendar) == .lateNight)
    }
}
