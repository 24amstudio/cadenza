import Foundation

/// Lets at most `limit` operations run at once. A waiting operation leaves the line when its task is cancelled.
actor BrowseGate {
    private let limit: Int
    private var running = 0
    private var waiting: [(id: UInt64, continuation: CheckedContinuation<Void, Error>)] = []
    private var next: UInt64 = 0

    init(limit: Int) { self.limit = limit }

    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await enter()
        defer { leave() }
        return try await operation()
    }

    private func enter() async throws {
        try Task.checkCancellation()
        if running < limit {
            running += 1
            return
        }
        next += 1
        let id = next
        try await withTaskCancellationHandler(
            operation: { try await self.wait(id) },
            onCancel: { Task { await self.abandon(id) } })
    }

    private func wait(_ id: UInt64) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Cancellation that arrived before this line has already run its handler, so it is checked here.
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                waiting.append((id, continuation))
            }
        }
    }

    private func abandon(_ id: UInt64) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func leave() {
        if waiting.isEmpty {
            running -= 1
        } else {
            // The slot passes straight to the next waiter, so `running` stays the same.
            waiting.removeFirst().continuation.resume()
        }
    }
}
