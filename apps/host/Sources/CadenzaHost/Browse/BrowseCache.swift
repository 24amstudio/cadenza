import Foundation

/// Results held in memory only: at most `capacity` entries, each dropped when its time to live ends, and the
/// least recently used entry dropped first when the cache is full.
actor BrowseCache {
    static let capacity = 64
    static let catalogLifetime: TimeInterval = 6 * 3_600
    static let libraryLifetime: TimeInterval = 60

    private struct Entry {
        var result: BrowseResult
        var expires: TimeInterval
        var used: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var counter: UInt64 = 0
    private let capacity: Int
    private let now: @Sendable () -> TimeInterval

    init(
        capacity: Int = BrowseCache.capacity,
        now: @escaping @Sendable () -> TimeInterval = { Double(monotonicMs()) / 1_000 }
    ) {
        self.capacity = capacity
        self.now = now
    }

    func result(for key: String) -> BrowseResult? {
        guard var entry = entries[key] else { return nil }
        guard entry.expires > now() else {
            entries.removeValue(forKey: key)
            return nil
        }
        counter += 1
        entry.used = counter
        entries[key] = entry
        return entry.result
    }

    func store(_ result: BrowseResult, for key: String, lifetime: TimeInterval) {
        counter += 1
        entries[key] = Entry(result: result, expires: now() + lifetime, used: counter)
        guard entries.count > capacity else { return }
        let current = now()
        for (key, entry) in entries where entry.expires <= current { entries.removeValue(forKey: key) }
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
            entries.removeValue(forKey: oldest)
        }
    }
}
