/// The rows on screen. It is bounded, so a long session cannot grow it, and it can hold new rows back while the
/// user reads.
struct LogBuffer {
    static let capacity = 5_000

    private(set) var rows: [LogRow] = []
    /// Rows that arrived while paused. They join `rows` on resume.
    private var held: [LogRow] = []
    private(set) var heldCount = 0
    private(set) var isPaused = false
    private(set) var newestId: Int64 = 0
    private let capacity: Int

    init(capacity: Int = LogBuffer.capacity) { self.capacity = capacity }

    /// Replaces the rows with a fresh read of the store. `newestStoredId` is the newest id the store held at that
    /// moment, so later rows are the only ones treated as new.
    mutating func replace(with newRows: [LogRow], newestStoredId: Int64) {
        rows = Array(newRows.suffix(capacity))
        held.removeAll()
        heldCount = 0
        newestId = newestStoredId
    }

    /// Adds live rows. Rows already seen are ignored, which keeps a reload and a flush from duplicating a row.
    mutating func append(_ newRows: [LogRow]) {
        let fresh = newRows.filter { $0.id > newestId }
        guard let last = fresh.last else { return }
        newestId = last.id
        if isPaused {
            held = Array((held + fresh).suffix(capacity))
            heldCount += fresh.count
        } else {
            rows = Array((rows + fresh).suffix(capacity))
        }
    }

    mutating func pause() { isPaused = true }

    mutating func resume() {
        isPaused = false
        guard !held.isEmpty else { return }
        rows = Array((rows + held).suffix(capacity))
        held.removeAll()
        heldCount = 0
    }

    /// Empties the view only. Stored logs are untouched, and rows seen so far do not come back.
    mutating func clear() {
        rows.removeAll()
        held.removeAll()
        heldCount = 0
    }
}
