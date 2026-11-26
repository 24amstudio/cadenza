import Foundation

/// The suites that stage receivers may fetch: the playing track and the one prefetched after it. Entries are bounded and
/// keyed by opaque suite IDs, so a receiver never names a catalog item.
@MainActor
final class StageSuiteStore {
    struct Entry {
        let suiteId: String
        let occurrenceId: String
        var suite: StageTrackSuite
        var lyrics: LyricDocument?
        var artwork: Data?
        var motion: Data?
        var videoFile: URL?
    }

    static let capacity = 4

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    /// The AVR delay that the karaoke lines wait for. The VTT for a video includes it at request time.
    var lipSyncOffsetMs: () -> Int = { 0 }

    func entry(_ suiteId: String) -> Entry? { entries[suiteId] }

    /// Registers or replaces an entry. The oldest entry leaves when the store is full.
    func register(_ entry: Entry) {
        if entries[entry.suiteId] == nil {
            order.append(entry.suiteId)
        }
        entries[entry.suiteId] = entry
        while order.count > Self.capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    func update(_ suiteId: String, _ change: (inout Entry) -> Void) {
        guard var entry = entries[suiteId] else { return }
        change(&entry)
        entries[suiteId] = entry
    }

    func has(suiteId: String, occurrenceId: String) -> Bool {
        entries[suiteId]?.occurrenceId == occurrenceId
    }

    /// The karaoke rendition of one suite, rebuilt on each request so a saved nudge or new lip-sync offset applies at once.
    func lyricsText(for suiteId: String) -> String? {
        guard let entry = entries[suiteId], let lyrics = entry.lyrics else { return nil }
        return WebVTTKaraoke.render(
            document: lyrics, userOffsetMs: lyrics.userOffsetMs ?? 0, lipSyncOffsetMs: lipSyncOffsetMs())
    }
}
