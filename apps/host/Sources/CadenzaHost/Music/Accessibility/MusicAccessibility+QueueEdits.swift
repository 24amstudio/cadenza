import AppKit
import ApplicationServices
import Foundation

/// Starting playback of a queue row and rearranging the queue by dragging. Each operation is tried without focusing
/// Music first; see `InputRoute` for the order.
extension MusicAccessibility {
    private enum PlayStrategy: CaseIterable {
        case doubleClick, returnKey

        var name: String {
            switch self {
            case .doubleClick: "double-click"
            case .returnKey: "Return key"
            }
        }
    }

    /// Starts the row. `skipToNext` moves Music to the row without focus, and the caller starts playback after it.
    /// `confirmed` reads Music back, so each way is checked before the next one runs.
    func play(
        _ row: NativeQueueRow, deadline: Int64, skipToNext: (() async throws -> Void)? = nil,
        confirmed: @escaping () -> Bool
    ) async throws {
        if let skipToNext, try await skipsToRow(skipToNext, deadline: deadline, confirmed: confirmed) { return }
        do {
            try await escalating(deadline: deadline) { route, limit in
                try await self.startRow(row, route: route, deadline: limit, confirmed: confirmed)
            }
        } catch let error as CadenzaError where error.code == "native_queue_unavailable" {
            throw CadenzaError.failure(
                "outcome_unknown", "Music did not start the queued song. " + error.localizedDescription)
        }
    }

    private func skipsToRow(
        _ skipToNext: () async throws -> Void, deadline: Int64, confirmed: () -> Bool
    ) async throws -> Bool {
        do {
            try await skipToNext()
        } catch let error as CadenzaError where error.code != "expired" {
            logger?.log(
                .warning, category: "accessibility", action: "play.skip-failed", "Music's next track did not run",
                metadata: ["reason": error.localizedDescription])
            return false
        }
        return try await settled(deadline: deadline, confirmed: confirmed)
    }

    private func settled(deadline: Int64, confirmed: () -> Bool) async throws -> Bool {
        let limit = min(deadline, monotonicMs() + 1_200)
        repeat {
            try await Task.sleep(for: .milliseconds(60))
            if confirmed() { return true }
        } while monotonicMs() < limit
        return false
    }

    private func startRow(
        _ row: NativeQueueRow, route: InputRoute, deadline: Int64, confirmed: () -> Bool
    ) async throws {
        try requireInput(route)
        var failures: [String] = []
        for strategy in PlayStrategy.allCases {
            try Task.checkCancellation()
            try requireDeadline(deadline)
            do {
                try await start(row, using: strategy, route: route, deadline: deadline)
            } catch let error as CadenzaError where error.code == "native_queue_unavailable" {
                // A row Music has already consumed is no longer visible, which is the success case.
                if confirmed() { return }
                failures.append("\(strategy.name): \(error.localizedDescription)")
                continue
            }
            if try await settled(deadline: deadline, confirmed: confirmed) { return }
            failures.append("\(strategy.name): Music did not start the song.")
        }
        throw CadenzaError.failure("native_queue_unavailable", failures.joined(separator: " "))
    }

    private func start(
        _ row: NativeQueueRow, using strategy: PlayStrategy, route: InputRoute, deadline: Int64
    ) async throws {
        switch strategy {
        case .doubleClick:
            try await click(row.element, deadline: deadline, count: 2, route: route)
        case .returnKey:
            // The click gives the list keyboard focus, which a search field may still hold.
            try await click(row.element, deadline: deadline, route: route)
            try await Task.sleep(for: .milliseconds(80))
            beginRead(deadline: min(deadline, monotonicMs() + 400))
            guard !textFieldHasFocus() else {
                throw CadenzaError.failure(
                    "native_queue_unavailable", "Music's search field kept keyboard focus, so Return was not sent.")
            }
            try requireDeadline(deadline)
            try pressKey(Self.returnKey, route: route)
        }
    }

    /// Drags `row` before `anchor`, or to the end. `confirmed` reads the queue back after each drag.
    func move(
        _ row: NativeQueueRow, before anchor: NativeQueueRow?, deadline: Int64, confirmed: @escaping () -> Bool
    ) async throws {
        try await escalating(deadline: deadline, routes: [.process, .system]) { route, limit in
            try await self.drag(row, before: anchor, route: route, deadline: limit)
            guard try await self.settled(deadline: limit, confirmed: confirmed) else {
                throw CadenzaError.failure("native_queue_unavailable", "Music did not reorder the queue.")
            }
        }
    }

    private func drag(
        _ row: NativeQueueRow, before anchor: NativeQueueRow?, route: InputRoute, deadline: Int64
    ) async throws {
        try requireInput(route)
        beginRead(deadline: deadline)
        let queue = try rows(deadline: deadline)
        guard let destination = anchor ?? queue.last else { return }
        let origin = try bounds(row.element)
        let target = try bounds(destination.element)
        let point = CGPoint(x: origin.midX, y: origin.midY)
        let end = CGPoint(x: target.midX, y: anchor == nil ? target.maxY - 2 : target.minY + 2)
        try requireDeadline(deadline)
        let source = try inputSource()
        let previous = pointerToRestore(route: route)
        try deliver(
            CGEvent(
                mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            route: route)
        var position = point
        do {
            // A single jump to the drop point is not recognised as a drag, so the pointer travels along the path.
            let steps = 12
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                position = CGPoint(
                    x: point.x + (end.x - point.x) * fraction, y: point.y + (end.y - point.y) * fraction)
                try deliver(
                    CGEvent(
                        mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: position,
                        mouseButton: .left), route: route)
                try await Task.sleep(for: .milliseconds(20))
            }
        } catch {
            // A cancelled drag must not leave Music with a held mouse button.
            try? deliver(
                CGEvent(
                    mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: position, mouseButton: .left
                ),
                route: route)
            restorePointer(previous, source: source)
            throw error
        }
        try deliver(
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left),
            route: route)
        restorePointer(previous, source: source)
    }
}
