import Foundation

@MainActor
final class QueueCoordinator {
    let store: HostStore
    let music: MusicBridge
    let catalog: Catalog
    let journal: CommandJournal
    var onSnapshot: ((HostSnapshot) -> Void)?
    var onCredits: (() -> Void)?
    var onIssue: ((String) -> Void)?
    private(set) var nativeRows: [NativeQueueRow] = []
    private var bindings: [String: String] = [:]
    private var current: CurrentPlayback?
    private var lastStatus: MusicStatus?
    private var lastObservation: Int64?
    private var sequence: Int64 = 0
    private(set) var synchronized = false
    private(set) var issue: String?
    private var publishIssueReported = false
    private var locked = false
    private var draining = false
    private var waiting: [QueuedCommand] = []
    private var activeCommand: (String, String)?
    private var lastQuality = "unknown"
    private var lastMixing: Bool?
    private var observedIncomingTitle: String?
    private var lastQualityAt: Int64 = 0
    private var forcedEntry: String?
    private var primingLyrics = false
    private var pendingPlaybackMs: Int64 = 0
    private var pendingPlaybackOccurrence: String?
    private var preparationToken: String?
    private(set) var knownSongs: [SongIdentity: Song] = [:]

    private struct QueuedCommand {
        let frame: Frame
        let actor: String
        let continuation: CheckedContinuation<Frame, Error>
    }

    var busy: Bool { locked || draining || !waiting.isEmpty }
    var isPlaying: Bool { lastStatus?.playing == true }
    var nativeAssignments: [String: String] { bindings }

    func commandQueued(_ commandId: String, actor: String) -> Bool {
        (activeCommand?.0 == actor && activeCommand?.1 == commandId)
            || waiting.contains { $0.actor == actor && $0.frame.commandId == commandId }
    }

    init(store: HostStore, music: MusicBridge, catalog: Catalog) {
        self.store = store
        self.music = music
        self.catalog = catalog
        journal = CommandJournal(store: store)
    }

    func remember(_ songs: [Song]) {
        if knownSongs.count > 1_000 { knownSongs.removeAll(keepingCapacity: true) }
        for song in songs { knownSongs[song.identity] = song }
    }

    func refresh() async {
        guard !locked else { return }
        locked = true
        defer { locked = false }
        do { try await readState() } catch {
            synchronized = false
            issue = error.localizedDescription
            if current?.requestedBy != nil {
                do { try store.recordObservationGap() } catch {
                    issue =
                        (issue ?? "Music could not be read.") + " The observation gap could not be saved: "
                        + error.localizedDescription
                }
            }
            lastObservation = nil
        }
        publish()
    }

    private func readState(deadline: Int64? = nil, includeQueue: Bool = true) async throws {
        let status = try await music.status(deadline: deadline)
        let now = monotonicMs()
        if primingLyrics && status.song?.identity != lastStatus?.song?.identity { primingLyrics = false }
        if includeQueue, !primingLyrics { try? music.accessibility.showQueue(deadline: now + 250) }
        let nativeRead: Result<[NativeQueueRow], Error> =
            if !includeQueue || primingLyrics {
                .success(nativeRows)
            } else {
                Result { try music.accessibility.rows(deadline: deadline) }
            }
        let observed = (try? nativeRead.get()) ?? nativeRows
        guard observed.count <= 256, Set(observed.map(\.token)).count == observed.count else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "The native queue is too large or has ambiguous row identities.")
        }
        let pending = try store.pending()
        if bindings.isEmpty {
            for row in pending {
                if let token = row["native_token"]?.string,
                    let native = observed.first(where: { $0.token == token }),
                    native.title == row["title"]?.string, native.artist == row["artist"]?.string,
                    let id = row["entry_id"]?.string
                {
                    bindings[token] = id
                }
            }
        }
        let missing = nativeRows.filter { old in !observed.contains { $0.token == old.token } }
        for native in observed {
            if let id = bindings[native.token], let entry = try store.entry(id),
                native.title != entry["title"]?.string || native.artist != entry["artist"]?.string
            {
                bindings.removeValue(forKey: native.token)
            }
        }
        let songChanged =
            status.song?.identity != lastStatus?.song?.identity
            || status.song?.title != lastStatus?.song?.title
            || status.song?.artist != lastStatus?.song?.artist
            || (status.positionMs + 1_500 < (lastStatus?.positionMs ?? 0) && !missing.isEmpty)
            || (forcedEntry != nil && missing.contains { bindings[$0.token] == forcedEntry })
        if songChanged {
            lastQuality = "unknown"
            lastMixing = nil
            observedIncomingTitle = nil
            lastQualityAt = 0
        }
        if songChanged || !status.playing { try flushCredits() }
        if current == nil, lastStatus == nil, let song = status.song {
            let state = try store.database.query("SELECT current_occurrence_id,current_native_id FROM host_state").first
            if state?["current_native_id"]?.string == song.id,
                let occurrence = state?["current_occurrence_id"]?.string,
                let row = try store.database.query("SELECT * FROM queue_entries WHERE state='current'").first,
                row["title"]?.string == song.title, row["artist"]?.string == song.artist
            {
                current = CurrentPlayback(
                    occurrenceId: occurrence, entryId: row["entry_id"]?.string,
                    requestedBy: row["requested_by"]?.string,
                    requesterName: try store.remoteName(row["requested_by"]?.string), song: store.song(row),
                    positionMs: status.positionMs, sampledAtHostMs: now
                )
            }
        }
        if let song = status.song, status.state != "stopped", current == nil || songChanged {
            var entry: String?
            if missing.count == 1, let removed = missing.first,
                removed.token == nativeRows.first?.token, removed.title == song.title,
                removed.artist == song.artist
            {
                entry = bindings[removed.token]
            }
            let stored = try entry.flatMap { try store.entry($0) }
            let actual = stored.map(store.song) ?? song
            let occurrence = try store.beginOccurrence(entryId: entry, song: actual)
            current = CurrentPlayback(
                occurrenceId: occurrence, entryId: entry, requestedBy: stored?["requested_by"]?.string,
                requesterName: try store.remoteName(stored?["requested_by"]?.string),
                song: actual, positionMs: status.positionMs, sampledAtHostMs: now
            )
            try store.database.run("UPDATE host_state SET current_native_id=?", [.text(song.id)])
            lastObservation = nil
            forcedEntry = nil
        }
        if status.song == nil || status.state == "stopped" {
            if current != nil {
                try store.database.transaction {
                    try store.database.run("UPDATE queue_entries SET state='completed' WHERE state='current'")
                    try store.database.run("UPDATE host_state SET current_occurrence_id=NULL,current_native_id=NULL")
                    try store.bump()
                }
            }
            current = nil
            lastObservation = nil
        }
        if let occurrence = current?.occurrenceId, let last = lastObservation, let previous = lastStatus,
            status.playing, previous.playing, !songChanged
        {
            let elapsed = now - last
            let progress = status.positionMs - previous.positionMs
            if elapsed > 2_000 { try store.recordObservationGap() }
            if elapsed > 0 && elapsed <= 2_000 && progress > 0 && abs(progress - elapsed) <= 350 {
                if pendingPlaybackOccurrence != occurrence { try flushCredits() }
                pendingPlaybackOccurrence = occurrence
                pendingPlaybackMs += min(elapsed, progress)
                let counted =
                    try store.database.query(
                        "SELECT counted FROM playback_sessions WHERE occurrence_id=?", [.text(occurrence)]
                    ).first?["counted"]?.integer == 1
                if !counted || pendingPlaybackMs >= 5_000 { try flushCredits() }
            }
        }
        for removed in missing {
            if let id = bindings.removeValue(forKey: removed.token), id != current?.entryId { try store.remove(id) }
        }
        let unresolved = try store.pending().contains { entry in
            guard let id = entry["entry_id"]?.string else { return true }
            return !observed.contains { bindings[$0.token] == id }
        }
        let externalRows = observed.contains { bindings[$0.token] == nil }
        if observed.map(\.token) != nativeRows.map(\.token) {
            try store.reorder(observed.compactMap { bindings[$0.token] })
            try store.bump()
        }
        nativeRows = observed
        if case .failure(let error) = nativeRead {
            synchronized = false
            issue = error.localizedDescription
        } else if externalRows {
            synchronized = false
            issue =
                "Music's Playing Next queue changed outside Cadenza Host. "
                + "Review the queue before requesting another action."
        } else {
            synchronized = !unresolved
            issue = unresolved ? "Some saved requests cannot be matched to Music. Reconcile them in Cadenza Host." : nil
        }
        if now - lastQualityAt > 5_000, let title = status.song?.title {
            lastQuality = music.accessibility.quality(currentTitle: title)
            let mixing = music.accessibility.mixing(currentTitle: title)
            lastMixing = mixing.active
            observedIncomingTitle = mixing.incomingTitle
            lastQualityAt = now
        }
        current?.positionMs = status.positionMs
        current?.sampledAtHostMs = now
        lastStatus = status
        lastObservation = now
    }

    func snapshot() throws -> HostSnapshot {
        var queue: [QueueEntry] = []
        let snapshotHostTime = monotonicMs()
        var remaining = current?.song.durationMs.map { max(0, $0 - (current?.positionMs ?? 0)) }
        if current == nil { remaining = 0 }
        for row in nativeRows {
            let entry = try bindings[row.token].flatMap { try store.entry($0) }
            let song =
                entry.map(store.song) ?? Song(source: "unknown", id: row.token, title: row.title, artist: row.artist)
            let estimateStatus: String
            if !synchronized {
                estimateStatus = "unsynchronized"
            } else if remaining == nil {
                estimateStatus = "unknown_duration"
            } else {
                estimateStatus = lastStatus?.playing == true ? "known" : "paused"
            }
            queue.append(
                QueueEntry(
                    id: entry?["entry_id"]?.string ?? "mac-\(row.token)",
                    requestedBy: entry?["requested_by"]?.string,
                    requesterName: try store.remoteName(entry?["requested_by"]?.string), song: song,
                    estimatedWaitMs: remaining,
                    estimatedStartHostMs: remaining.map { snapshotHostTime + $0 },
                    estimateStatus: estimateStatus
                ))
            if let value = remaining, let duration = song.durationMs, duration <= Wire.maximumCounter - value {
                remaining = value + duration
            } else {
                remaining = nil
            }
        }
        let incomingMatches = queue.filter { $0.song.title == observedIncomingTitle }
        let incoming = lastMixing == true && incomingMatches.count == 1 ? incomingMatches.first?.song : nil
        return HostSnapshot(
            hostId: store.hostId, hostEpoch: store.epoch, revision: try store.revision,
            sequence: sequence, hostTimeMs: snapshotHostTime, allowCrossRemoteEdits: try store.crossEdits,
            playing: lastStatus?.playing ?? false, volume: lastStatus?.volume ?? 0,
            current: current, queue: queue, totalRemainingMs: remaining,
            quality: lastQuality,
            incoming: incoming, mixing: lastMixing,
            synchronized: synchronized, issue: issue,
            observationGap: try store.database.query("SELECT observation_gap FROM host_state").first?[
                "observation_gap"]?.integer == 1
        )
    }

    func publish() {
        sequence += 1
        do {
            onSnapshot?(try snapshot())
            publishIssueReported = false
        } catch {
            issue = error.localizedDescription
            if !publishIssueReported {
                publishIssueReported = true
                onIssue?("Cadenza Host could not publish the current playback state: " + error.localizedDescription)
            }
        }
    }

    func execute(_ command: Frame, actor: String) async throws -> Frame {
        try await withCheckedThrowingContinuation { continuation in
            guard waiting.count < 16 else {
                continuation.resume(
                    throwing: CadenzaError.failure("busy", "The command queue is full. Retry with current state."))
                return
            }
            waiting.append(QueuedCommand(frame: command, actor: actor, continuation: continuation))
            if !draining {
                draining = true
                Task { @MainActor [weak self] in await self?.drain() }
            }
        }
    }

    private func drain() async {
        defer { draining = false }
        while !waiting.isEmpty {
            let next = waiting.removeFirst()
            activeCommand = (next.actor, next.frame.commandId ?? "")
            while locked && monotonicMs() < (next.frame.expiresAtHostMs ?? 0) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            do { next.continuation.resume(returning: try await perform(next.frame, actor: next.actor)) } catch {
                next.continuation.resume(throwing: error)
            }
            activeCommand = nil
        }
    }

    private func perform(_ command: Frame, actor: String) async throws -> Frame {
        if let previous = try journal.previous(command, actor: actor) { return previous }
        guard monotonicMs() < (command.expiresAtHostMs ?? 0) else {
            throw CadenzaError.failure("expired", "The command expired while waiting for dispatch.")
        }
        guard !locked else {
            throw CadenzaError.failure("busy", "Music is processing another action. Retry using the latest queue.")
        }
        guard let action = command.action, let deadline = command.expiresAtHostMs else {
            throw CadenzaError.failure("invalid_command", "Invalid control action.")
        }
        locked = true
        defer {
            locked = false
            publish()
        }
        primingLyrics = false
        preparationToken = nil
        // Playback state is independently readable from Music. Avoid an Accessibility
        // queue walk for controls that cannot reorder or remove requests.
        let needsQueueRead =
            action.kind.hasPrefix("queue.")
            || action.kind == "playback.skip"
            || action.kind == "playback.previous"
        try await readState(deadline: deadline, includeQueue: needsQueueRead)
        if action.kind.hasPrefix("queue.") {
            try music.accessibility.showQueue(deadline: deadline)
        }
        let target = action.entryId ?? current?.entryId
        if let occurrence = action.occurrenceId, occurrence != current?.occurrenceId {
            throw CadenzaError.failure("stale_occurrence", "The current song changed.")
        }
        if action.kind == "queue.play_now" {
            guard action.occurrenceId == current?.occurrenceId else {
                throw CadenzaError.failure("stale_occurrence", "The current song changed.")
            }
            guard current == nil || current?.requestedBy != nil else {
                throw CadenzaError.failure("forbidden", "Cadenza Host playback stays under Host control.")
            }
            for native in nativeRows {
                let owner = try bindings[native.token].flatMap { try store.entry($0)?["requested_by"]?.string }
                if try owner == nil || (owner != actor && !store.crossEdits) {
                    throw CadenzaError.failure("forbidden", "Play Now would jump ahead of another person's request.")
                }
            }
        }
        try store.authorize(actor: actor, command: command, entryId: target)
        guard !action.kind.hasPrefix("queue.") || synchronized else {
            throw CadenzaError.failure("native_queue_unavailable", issue ?? "Reconcile Music's native queue first.")
        }
        var plannedEntry: String?
        if ["queue.enqueue", "queue.play_now", "queue.play_next"].contains(action.kind) {
            guard let identity = action.song, let song = knownSongs[identity] else {
                throw CadenzaError.failure("song_not_ready", "Search for and select the song first.")
            }
            let id = identifier()
            let plan = String(decoding: try JSONSerialization.data(withJSONObject: ["entry_id": id]), as: UTF8.self)
            try store.database.transaction {
                try store.insert(song, owner: actor, id: id, confirmed: false)
                try journal.prepare(command, actor: actor, plan: plan)
            }
            plannedEntry = id
        } else {
            try journal.prepare(command, actor: actor, plan: nil)
        }
        var dispatched = false
        let beforeEffect: @MainActor () throws -> Void = {
            guard !dispatched else { return }
            try self.store.authorize(actor: actor, command: command, entryId: target)
            try self.journal.dispatched(command, actor: actor)
            dispatched = true
        }
        do {
            if let identity = action.song, let song = knownSongs[identity] {
                guard music.accessibility.isPrepared(song) else {
                    throw CadenzaError.failure(
                        "song_not_ready", "Prepare this exact song again before requesting playback.")
                }
            }
            try store.authorize(actor: actor, command: command, entryId: target)
            if action.kind.hasPrefix("queue.") {
                try await editQueue(
                    action, actor: actor, deadline: deadline, plannedEntry: plannedEntry, beforeEffect: beforeEffect)
            } else {
                try flushCredits()
                lastObservation = nil
                try beforeEffect()
                try await music.control(action, deadline: deadline)
            }
            try await readState(deadline: deadline, includeQueue: needsQueueRead)
            try verifyPlayback(action, expectedEntry: plannedEntry)
            let result = try journal.result(command, outcome: "applied")
            try journal.finish(command, actor: actor, result: result)
            return result
        } catch {
            let code = (error as? CadenzaError)?.code ?? "music_unavailable"
            let failure = CommandFailure(dispatched: dispatched, code: code)
            if !dispatched, let plannedEntry { try store.remove(plannedEntry) }
            let result = try journal.result(
                command, outcome: failure.outcome, code: failure.code,
                message: dispatched
                    ? "Music may have accepted this action. Check its original outcome before retrying. "
                        + error.localizedDescription : error.localizedDescription
            )
            try journal.finish(command, actor: actor, result: result)
            if dispatched {
                synchronized = false
                issue = "A native action is unconfirmed. Reconcile the queue before retrying."
            }
            return result
        }
    }

    private func verifyPlayback(_ action: CommandAction, expectedEntry: String?) throws {
        guard let status = lastStatus else {
            throw CadenzaError.failure("outcome_unknown", "Music state could not be confirmed.")
        }
        let confirmed: Bool
        switch action.kind {
        case "queue.play_now": confirmed = current?.entryId == expectedEntry && status.playing
        case "playback.pause": confirmed = !status.playing
        case "playback.resume": confirmed = status.playing
        case "playback.stop": confirmed = status.state == "stopped"
        case "playback.seek": confirmed = abs(status.positionMs - (action.positionMs ?? 0)) <= 1_000
        case "playback.volume": confirmed = status.volume == action.percent
        case "playback.skip", "playback.previous": confirmed = current?.occurrenceId != action.occurrenceId
        default: confirmed = true
        }
        guard confirmed else {
            throw CadenzaError.failure("outcome_unknown", "Music has not confirmed the requested playback state.")
        }
    }

    private func editQueue(
        _ action: CommandAction, actor: String, deadline: Int64, plannedEntry: String?,
        beforeEffect: @MainActor () throws -> Void
    ) async throws {
        let before = try music.accessibility.rows(deadline: deadline)
        guard before.map(\.token) == nativeRows.map(\.token) else {
            throw CadenzaError.failure("stale_revision", "Music's queue changed before dispatch.")
        }
        switch action.kind {
        case "queue.enqueue", "queue.play_now", "queue.play_next":
            guard let identity = action.song, let song = knownSongs[identity] else {
                throw CadenzaError.failure("song_not_ready", "Search for the song and prepare it before adding it.")
            }
            let immediate = action.kind == "queue.play_now"
            let insertNext = immediate || action.kind == "queue.play_next"
            try beforeEffect()
            try music.accessibility.append(song, deadline: deadline, next: insertNext)
            let after = try await waitForQueue(deadline: deadline) { rows in
                let added = insertNext ? rows.first : rows.last
                let remainder = insertNext ? Array(rows.dropFirst()) : Array(rows.dropLast())
                return rows.count == before.count + 1
                    && remainder.map(\.token) == before.map(\.token)
                    && added?.title == song.title && added?.artist == song.artist
            }
            guard let added = insertNext ? after.first : after.last else {
                throw CadenzaError.failure("outcome_unknown", "Music did not expose the added request.")
            }
            guard let id = plannedEntry else {
                throw CadenzaError.failure("storage", "The durable request intent is missing.")
            }
            try store.database.transaction {
                try store.database.run(
                    "UPDATE queue_entries SET native_token=?,native_confirmed=1 WHERE entry_id=?",
                    [.text(added.token), .text(id)])
                try store.bump()
            }
            bindings[added.token] = id
            nativeRows = after
            if insertNext { try store.reorder(after.compactMap { bindings[$0.token] }) }
            if immediate {
                forcedEntry = id
                try music.accessibility.play(added, deadline: deadline)
                _ = try await waitForQueue(deadline: deadline) { $0.map(\.token) == before.map(\.token) }
            }
        case "queue.remove":
            guard let entry = action.entryId, let row = before.first(where: { bindings[$0.token] == entry }) else {
                throw CadenzaError.failure("missing_request", "The request is no longer in Music's queue.")
            }
            try beforeEffect()
            try music.accessibility.remove(row, deadline: deadline)
            _ = try await waitForQueue(deadline: deadline) {
                $0.map(\.token) == before.filter { $0.token != row.token }.map(\.token)
            }
            try store.remove(entry)
            bindings.removeValue(forKey: row.token)
            try store.bump()
        case "queue.move":
            try await move(action, rows: before, actor: actor, deadline: deadline, beforeEffect: beforeEffect)
        default: throw CadenzaError.failure("invalid_command", "Unknown queue action.")
        }
    }

    private func move(
        _ action: CommandAction, rows: [NativeQueueRow], actor: String, deadline: Int64,
        beforeEffect: @MainActor () throws -> Void
    ) async throws {
        guard let entry = action.entryId, let row = rows.first(where: { bindings[$0.token] == entry }) else {
            throw CadenzaError.failure("missing_request", "The queue request is unavailable.")
        }
        let anchor = action.beforeEntryId.flatMap { id in rows.first { bindings[$0.token] == id } }
        var desired = rows.filter { $0.token != row.token }
        let index = anchor.flatMap { target in desired.firstIndex { $0.token == target.token } } ?? desired.count
        desired.insert(row, at: index)
        let original = rows.firstIndex { $0.token == row.token } ?? index
        for crossed in rows[min(original, index)...max(original, index)] where crossed.token != row.token {
            let owner = try bindings[crossed.token].flatMap { try store.entry($0)?["requested_by"]?.string }
            if try owner == nil || (owner != actor && !store.crossEdits) {
                throw CadenzaError.failure("forbidden", "This move would cross a protected request.")
            }
        }
        try beforeEffect()
        try music.accessibility.move(row, before: anchor, deadline: deadline)
        let expected = desired.map(\.token)
        _ = try await waitForQueue(deadline: deadline) { $0.map(\.token) == expected }
        try store.reorder(desired.compactMap { bindings[$0.token] })
        try store.bump()
        nativeRows = desired
    }

    private func waitForQueue(
        deadline: Int64, matching condition: ([NativeQueueRow]) -> Bool
    ) async throws -> [NativeQueueRow] {
        repeat {
            let rows = try music.accessibility.rows(deadline: deadline)
            if condition(rows) { return rows }
            try await Task.sleep(for: .milliseconds(35))
        } while monotonicMs() < deadline
        throw CadenzaError.failure("outcome_unknown", "Music's native queue has not confirmed the action.")
    }

    func prepare(_ identity: SongIdentity) async throws {
        guard activeCommand == nil, waiting.isEmpty else {
            throw CadenzaError.failure(
                "busy", "Music is processing a control action. Prepare the song again in a moment.")
        }
        let token = identifier()
        preparationToken = token
        let song: Song
        if let known = knownSongs[identity] {
            song = known
        } else if identity.source == "catalog" {
            song = try await catalog.resolve(identity)
        } else {
            song = try await music.resolve(identity)
        }
        remember([song])
        guard preparationToken == token, activeCommand == nil, waiting.isEmpty else {
            throw CadenzaError.failure("busy", "Another Music action took priority. Prepare this song again.")
        }
        try await music.prepare(song) { [weak self] in self?.preparationToken == token }
    }

    func flushCredits() throws {
        guard let occurrence = pendingPlaybackOccurrence, pendingPlaybackMs > 0 else { return }
        try store.observe(occurrence: occurrence, milliseconds: pendingPlaybackMs)
        pendingPlaybackMs = 0
        pendingPlaybackOccurrence = nil
        onCredits?()
    }

    func primeLyrics(occurrence: String) async throws {
        guard !busy, current?.occurrenceId == occurrence else { return }
        primingLyrics = true
        do {
            try music.accessibility.showLyrics(deadline: monotonicMs() + 500)
            try await Task.sleep(for: .milliseconds(800))
        } catch {
            primingLyrics = false
            throw error
        }
        if primingLyrics {
            defer { primingLyrics = false }
            try music.accessibility.showQueue(deadline: monotonicMs() + 500)
        }
    }

    func reconcile(_ assignments: [String: String], discardMissing: Bool) throws {
        guard !busy else { throw CadenzaError.failure("busy", "Wait for Music's current action before reconciling.") }
        let rows = try music.accessibility.rows()
        guard Set(assignments.values).count == assignments.count else {
            throw CadenzaError.failure("invalid_state", "Each saved request can be assigned only once.")
        }
        try store.database.transaction {
            let missing = try store.pending().compactMap { $0["entry_id"]?.string }.filter {
                !assignments.values.contains($0)
            }
            guard discardMissing || missing.isEmpty else {
                throw CadenzaError.failure(
                    "invalid_state", "Assign every saved request or explicitly cancel missing requests.")
            }
            for id in missing { try store.remove(id) }
            for (token, id) in assignments {
                guard let row = rows.first(where: { $0.token == token }),
                    let saved = try store.entry(id), saved["state"]?.string == "pending",
                    row.title == saved["title"]?.string, row.artist == saved["artist"]?.string
                else {
                    throw CadenzaError.failure(
                        "invalid_state", "The selected native row does not match the saved song.")
                }
                try store.database.run(
                    "UPDATE queue_entries SET native_token=?,native_confirmed=1 WHERE entry_id=?",
                    [.text(token), .text(id)])
            }
            try store.bump()
        }
        bindings = assignments
        nativeRows = rows
        try store.reorder(rows.compactMap { assignments[$0.token] })
        try journal.reconcileQueue(assignments: Set(assignments.values))
        synchronized = true
        issue = nil
        publish()
    }

    func hostControl(_ kind: String) async throws {
        guard !busy else { throw CadenzaError.failure("busy", "Wait for the current Music action to finish.") }
        locked = true
        preparationToken = nil
        primingLyrics = false
        defer {
            locked = false
            publish()
        }
        try flushCredits()
        lastObservation = nil
        try await music.control(CommandAction(kind: kind), deadline: monotonicMs() + 1_000)
        try await readState()
    }
}
