import Foundation

// Reads of Music's Playing Next list and the settling of requests it no longer shows.
extension QueueCoordinator {
    /// Saved requests that never reached a Music row and are old enough that their enqueue has finished.
    func unboundRequestIds() throws -> [String] {
        let bound = Set(bindings.values)
        let cutoff = wallMs() - Self.unboundGraceMs
        return try store.pending().compactMap { row in
            guard let id = row["entry_id"]?.string, row["native_token"]?.string == nil, !bound.contains(id),
                let created = row["created_at_ms"]?.integer, created < cutoff
            else { return nil }
            return id
        }
    }

    /// Cancels unbound requests that no visible row matches. A request a visible row matches is left alone, because
    /// binding it would guess who requested that row.
    func settleUnboundRequests(observed: [NativeQueueRow]) throws -> Bool {
        let stale = try unboundRequestIds().filter { id in
            guard let entry = try store.entry(id), let title = entry["title"]?.string,
                let artist = entry["artist"]?.string
            else { return false }
            return !observed.contains { $0.title == title && $0.artist == artist && bindings[$0.token] == nil }
        }
        guard !stale.isEmpty else { return false }
        let assigned = Set(bindings.values)
        for id in stale { try store.remove(id) }
        try store.bump()
        try journal.reconcileQueue(assignments: assigned)
        logger?.log(
            .warning, category: "queue", action: "queue.settled",
            "Cancelled \(stale.count) saved request(s) that Music no longer lists.",
            metadata: ["count": String(stale.count)])
        return true
    }

    /// The background refresh reads the queue only while it is unsynchronized and Music already shows its queue, so the
    /// Host never opens Music's panels for this.
    func needsStaleRequestSettlement() -> Bool {
        guard !synchronized, commandsIdle,
            ((try? unboundRequestIds()) ?? []).isEmpty == false
        else { return false }
        return music.accessibility.queuePanelOpen()
    }

    func backgroundQueueDecision(status: MusicStatus, now: Int64) -> QueueReadPolicy.Decision {
        queuePolicy.decide(
            now: now, lastReadAt: lastQueueReadAt, verified: queueVerified,
            trackChanged: status.song?.identity != lastStatus?.song?.identity,
            idle: commandsIdle, permitted: music.accessibility.permitted,
            musicPid: queuePid, panelOpen: { [music] in music.accessibility.queuePanelOpen() })
    }

    /// Reads Music's queue on an explicit action. The Playing Next list is opened first when it is closed, and the read
    /// waits for it only within the deadline. The status poll reads the queue only for the settlement above.
    func readNativeQueue(deadline: Int64, openPanel: Bool = true) async throws -> [NativeQueueRow] {
        if !music.accessibility.queuePanelOpen() {
            guard openPanel else {
                throw CadenzaError.failure("native_queue_unavailable", QueueReadPolicy.panelClosedMessage)
            }
            try await music.accessibility.requestQueuePanel()
        }
        while true {
            do {
                return try music.accessibility.rows(deadline: deadline)
            } catch let error as CadenzaError where ["music_permission", "music_unavailable"].contains(error.code) {
                throw error
            } catch {
                guard monotonicMs() < deadline else { throw error }
                try await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    /// Polls Music's queue until `condition` holds. A read that fails inside the window is retried, because Music
    /// redraws its list right after an edit.
    func waitForQueue(
        deadline: Int64, matching condition: ([NativeQueueRow]) -> Bool
    ) async throws -> [NativeQueueRow] {
        var lastFailure: String?
        repeat {
            do {
                let rows = try music.accessibility.rows(deadline: min(deadline, monotonicMs() + 1_000))
                if condition(rows) { return rows }
                lastFailure = nil
            } catch let error as CadenzaError where error.code == "native_queue_unavailable" {
                lastFailure = error.localizedDescription
            }
            try await Task.sleep(for: .milliseconds(35))
        } while monotonicMs() < deadline
        throw CadenzaError.failure(
            "outcome_unknown",
            "Music's native queue has not confirmed the action." + (lastFailure.map { " Last read: \($0)" } ?? ""))
    }

    static func rowKeys(_ rows: [NativeQueueRow]) -> [String] {
        rows.map { "\($0.title)|\($0.artist)" }
    }
}
