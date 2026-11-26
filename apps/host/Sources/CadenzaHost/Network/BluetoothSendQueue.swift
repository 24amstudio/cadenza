import Foundation

// One Remote's notification chunks waiting for CoreBluetooth. The window bounds how much a slow Remote can hold: the
// frames above this queue are kept in priority lanes by NetworkService, and each refused frame goes back to its own lane,
// so control frames and state reach the head again as soon as the window drains. A frame larger than the window is
// accepted only when the queue is nearly empty, which keeps the queue at most the refill level plus one frame.
struct BluetoothSendQueue {
    static let windowBytes = 4_096
    // A queue this close to empty takes the next frame, so the radio does not idle while that frame is prepared.
    static let refillBytes = 1_024

    private struct Frame {
        let chunks: [Data]
        var next = 0
        let completion: (Error?) -> Void
    }

    private var frames: [Frame] = []
    private var refused = false
    private(set) var pendingBytes = 0

    var isEmpty: Bool { frames.isEmpty }

    var nextChunk: Data? { frames.first.map { $0.chunks[$0.next] } }

    // Returns false when the queue is full. The caller keeps the frame and is told when to try again.
    //
    // A bulk frame (artwork, motion) enters only an empty queue. Otherwise a run of chunks would fill the window, and a
    // heartbeat or state frame behind them would wait for all of it to drain. The web Remote drops a link that goes
    // quiet for longer than its stall limit, so that wait is what ends the connection.
    mutating func enqueue(_ chunks: [Data], bulk: Bool, completion: @escaping (Error?) -> Void) -> Bool {
        let size = chunks.reduce(0) { $0 + $1.count }
        let admitted =
            bulk
            ? pendingBytes == 0
            : pendingBytes <= Self.refillBytes || pendingBytes + size <= Self.windowBytes
        guard admitted else {
            refused = true
            return false
        }
        frames.append(Frame(chunks: chunks, completion: completion))
        pendingBytes += size
        return true
    }

    // CoreBluetooth took the chunk returned by `nextChunk`.
    mutating func didSendChunk() {
        guard !frames.isEmpty else { return }
        pendingBytes -= frames[0].chunks[frames[0].next].count
        frames[0].next += 1
        if frames[0].next == frames[0].chunks.count { frames.removeFirst().completion(nil) }
    }

    // True once, when a refused frame can be offered again.
    mutating func takeDrainNotice() -> Bool {
        guard refused, pendingBytes <= Self.refillBytes else { return false }
        refused = false
        return true
    }

    mutating func removeAll() -> [(Error?) -> Void] {
        let completions = frames.map(\.completion)
        frames.removeAll()
        pendingBytes = 0
        refused = false
        return completions
    }
}
