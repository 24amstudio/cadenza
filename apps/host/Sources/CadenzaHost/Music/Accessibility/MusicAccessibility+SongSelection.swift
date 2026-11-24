import AppKit
import ApplicationServices
import Foundation

/// Finding and selecting the requested song in whatever Music is showing: an album, a library list or search results.
/// Rows are scored rather than matched exactly, and every wait is a bounded poll.
extension MusicAccessibility {
    typealias ScoredRow = (row: AXUIElement, score: Int)

    private static let linkRole = "AXLink"
    private static let containerRoles: Set<String> = [kAXGroupRole, kAXCellRole, kAXButtonRole, linkRole]
    private static let anchorRoles: Set<String> = [
        kAXStaticTextRole, kAXButtonRole, kAXCellRole, kAXGroupRole, kAXRowRole, linkRole,
    ]
    private static let maximumRows = 400

    /// Selects the requested song's row and returns it. Music's UI is polled until `deadline`, so a page that is still
    /// loading does not fail the request. A reason is thrown as `song_not_ready` once the budget is spent. With a
    /// `route`, one selection attempt is made through it and a failure is thrown for the caller to escalate; without
    /// one, selection escalates by itself.
    func selectSong(_ song: Song, deadline: Int64, route: InputRoute? = nil) async throws -> AXUIElement {
        if route == nil { try await ensureWindow(deadline: deadline) } else { try requireWindow() }
        var reason = "Music is not showing this song yet."
        var expandedSongs = false
        var located: AXUIElement?
        repeat {
            try Task.checkCancellation()
            beginRead(deadline: min(deadline, monotonicMs() + 1_500))
            do {
                located = try locateSongRow(song)
                if located != nil { break }
                reason = "Music's current page does not list this song."
                // A search page lists a few songs under Top Results. Its Songs section shows the rest after Show All.
                if !expandedSongs, try await pressShowAllSongs() { expandedSongs = true }
            } catch let error as CadenzaError where ["native_queue_unavailable", "song_not_ready"].contains(error.code)
            {
                reason = error.localizedDescription
            }
            try await Task.sleep(for: .milliseconds(120))
        } while monotonicMs() < deadline
        guard let row = located else {
            if modalBlocked() {
                throw CadenzaError.failure(
                    "music_modal_blocked", "Music is showing a dialog. Dismiss it in Music, then try again.")
            }
            throw CadenzaError.failure("song_not_ready", reason)
        }
        if let route { return try await ensureSelected(row, deadline: deadline, route: route) }
        return try await escalating(deadline: max(deadline, monotonicMs() + 2_400)) { route, limit in
            try await self.ensureSelected(row, deadline: limit, route: route)
        }
    }

    /// The reason Music does not show the exact song as selected, or nil when it does. Permission and availability
    /// failures are thrown, because waiting cannot fix them.
    func preparationIssue(_ song: Song, deadline: Int64) async throws -> String? {
        do {
            _ = try await selectSong(song, deadline: deadline)
            return nil
        } catch let error as CadenzaError where ["song_not_ready", "native_queue_unavailable"].contains(error.code) {
            return error.localizedDescription
        }
    }

    /// One pass over Music's window. Tables on the short paths are scored first, then every table in the window, and
    /// last any element whose text names the song, because search results are not always tables.
    func locateSongRow(_ song: Song) throws -> AXUIElement? {
        var shortPath = cachedTrackTable.map { [$0] } ?? []
        for table in try pathTables() where !shortPath.contains(where: { CFEqual($0, table) }) {
            shortPath.append(table)
        }
        shortPath.removeAll(where: inPlayQueue)
        if let found = bestRow(in: shortPath, song: song) { return found.row }
        guard monotonicMs() < readDeadline else { return nil }
        let windowTables = trackTables(try root()).filter { !inPlayQueue($0) }
        if let found = bestRow(in: windowTables, song: song) { return found.row }
        guard monotonicMs() < readDeadline else { return nil }
        let anchored = SongRowMatcher.best(anchoredRows(song))
        if anchored != nil {
            logger?.log(
                .debug, category: "accessibility", action: "song.located",
                "Matched the song by its text because no list row matched")
        }
        return anchored
    }

    private func bestRow(in tables: [AXUIElement], song: Song) -> (row: AXUIElement, table: AXUIElement)? {
        var scored: [(row: AXUIElement, score: Int, table: AXUIElement)] = []
        for table in tables {
            scored += scoredRows(in: table, song: song).map { ($0.row, $0.score, table) }
        }
        guard
            let winner = SongRowMatcher.best(scored.map { (row: ($0.row, $0.table), score: $0.score) })
        else { return nil }
        cachedTrackTable = winner.1
        return (winner.0, winner.1)
    }

    private func scoredRows(in table: AXUIElement, song: Song) -> [ScoredRow] {
        let selectedRows = attribute(table, kAXSelectedRowsAttribute) as? [AXUIElement] ?? []
        let visible = attribute(table, "AXVisibleRows") as? [AXUIElement] ?? []
        var rows = selectedRows + visible.filter { row in !selectedRows.contains { CFEqual($0, row) } }
        let known = rows.count
        for row in tableRows(table).prefix(Self.maximumRows) where !rows[..<known].contains(where: { CFEqual($0, row) })
        {
            rows.append(row)
        }
        var scored: [ScoredRow] = []
        for (index, row) in rows.enumerated() {
            guard monotonicMs() < readDeadline else { break }
            let isSelected = selectedRows.contains { CFEqual($0, row) }
            // Rows beyond the visible ones are screened by their first text, which is far cheaper than a full read.
            if index >= known {
                let lead = firstText(row)
                if !lead.isEmpty, SongRowMatcher.titleScore(song.title, in: lead) == 0 { continue }
            }
            let snapshot = snapshot(of: row, song: song)
            let score = SongRowMatcher.score(song, texts: snapshot.texts, linked: snapshot.linked, selected: isSelected)
            if score > 0 { scored.append((row, score)) }
        }
        return scored
    }

    /// Elements whose own text names the song, widened to the row-like container that holds them.
    private func anchoredRows(_ song: Song) -> [ScoredRow] {
        guard let application else { return [] }
        var scored: [ScoredRow] = []
        var seen: [AXUIElement] = []
        for window in children(application) where string(window, kAXRoleAttribute) == kAXWindowRole as String {
            let anchors = shallow(
                window, maxDepth: 28, maxNodes: 2_500, skipping: [kAXMenuBarRole, kAXMenuRole]
            ) { node in
                Self.anchorRoles.contains(self.string(node, kAXRoleAttribute))
                    && self.labels(node).contains { SongRowMatcher.titleScore(song.title, in: $0) > 0 }
            }
            for anchor in anchors.prefix(16) {
                let container = rowContainer(of: anchor)
                guard !inPlayQueue(container), !seen.contains(where: { CFEqual($0, container) }) else { continue }
                seen.append(container)
                let snapshot = snapshot(of: container, song: song)
                let isSelected = (attribute(container, kAXSelectedAttribute) as? Bool) == true
                let score = SongRowMatcher.score(
                    song, texts: snapshot.texts, linked: snapshot.linked, selected: isSelected)
                if score > 0 { scored.append((container, score)) }
            }
        }
        return scored
    }

    private func rowContainer(of anchor: AXUIElement) -> AXUIElement {
        var best = anchor
        var current = anchor
        for _ in 0..<4 {
            guard let up = parent(current) else { break }
            let role = string(up, kAXRoleAttribute)
            if role == kAXRowRole as String { return up }
            guard Self.containerRoles.contains(role) else { break }
            best = up
            current = up
        }
        return best
    }

    /// Every text a row shows, and whether any part of it links to the song's catalog or library identifier.
    private func snapshot(of row: AXUIElement, song: Song) -> (texts: [String], linked: Bool) {
        let nodes = shallow(row, maxDepth: 5, maxNodes: 80) { _ in true }
        var texts: [String] = []
        for node in nodes {
            let role = string(node, kAXRoleAttribute)
            if role == kAXStaticTextRole as String {
                texts.append(string(node, kAXValueAttribute))
            } else {
                texts += [kAXTitleAttribute, kAXDescriptionAttribute].map { string(node, $0) }
            }
        }
        return (texts.map(displayText).filter { !$0.isEmpty }, links(nodes, id: song.id))
    }

    private func labels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].map { string(element, $0) }
            .filter { !$0.isEmpty }
    }

    private func links(_ nodes: [AXUIElement], id: String) -> Bool {
        nodes.contains { node in
            if string(node, kAXIdentifierAttribute) == id { return true }
            guard let url = attribute(node, kAXURLAttribute) as? URL, url.host == "music.apple.com" else {
                return false
            }
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return parts?.queryItems?.contains { $0.name == "i" && $0.value == id } == true
                || url.path.hasSuffix("/\(id)")
        }
    }

    /// The table that holds a song, preferring tables with a selected row, because a song opened by its link is
    /// selected as soon as Music shows its album.
    func trackTables(_ root: AXUIElement) -> [AXUIElement] {
        // Rows and cells hold the sidebar and every list item. A table is found without descending into them.
        let tables = shallow(
            root, maxDepth: 24, maxNodes: 1_500, skipping: [kAXMenuBarRole, kAXMenuRole, kAXRowRole, kAXCellRole]
        ) {
            string($0, kAXRoleAttribute) == kAXTableRole
        }
        return tables.sorted { hasSelectedRow($0) && !hasSelectedRow($1) }
    }

    private func hasSelectedRow(_ table: AXUIElement) -> Bool {
        (attribute(table, kAXSelectedRowsAttribute) as? [AXUIElement])?.isEmpty == false
    }

    /// Whether Music shows the row as selected. Nil when the element exposes no selection state at all.
    func selectionState(_ row: AXUIElement) -> Bool? {
        var observable = false
        for node in shallow(row, maxDepth: 4, maxNodes: 40, matching: { _ in true }) {
            for name in [kAXSelectedAttribute, kAXFocusedAttribute] {
                guard let value = attribute(node, name) as? Bool else { continue }
                observable = true
                if value { return true }
            }
        }
        return observable ? false : nil
    }

    /// Selects the row through `route` and waits for Music to show the selection. Accessibility sets the table's
    /// selected rows and then the row's own flag; an input route clicks first and then sets the flag.
    private func ensureSelected(_ row: AXUIElement, deadline: Int64, route: InputRoute) async throws -> AXUIElement {
        beginRead(deadline: min(deadline, monotonicMs() + 800))
        if selectionState(row) == true { return row }
        for attempt in 0..<2 {
            try Task.checkCancellation()
            if attempt == 0, route.sendsInput {
                try await click(row, deadline: deadline, route: route)
            } else if attempt == 0 {
                selectRowInTable(row)
            } else {
                AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            }
            let limit = min(deadline, monotonicMs() + 800)
            repeat {
                try await Task.sleep(for: .milliseconds(60))
                beginRead(deadline: limit + 200)
                // A row with no selection state cannot be checked after a click, so the click is trusted and later
                // readback decides. An attribute write is never trusted unchecked, because it may be ignored silently.
                let state = selectionState(row)
                if state == true || (state == nil && route.sendsInput && attempt == 0) { return row }
            } while monotonicMs() < limit
        }
        throw CadenzaError.failure(
            "native_queue_unavailable", "Music did not select the matching song row through \(route.name).")
    }

    private func selectRowInTable(_ row: AXUIElement) {
        guard let table = parent(row), string(table, kAXRoleAttribute) == kAXTableRole as String else { return }
        AXUIElementSetAttributeValue(table, kAXSelectedRowsAttribute as CFString, [row] as CFArray)
    }

    /// Presses Show All in the Songs section of a search page. Returns whether a button was pressed. Pressing needs no
    /// focus, so Music is only brought forward when Accessibility and process events both fail to press it.
    func pressShowAllSongs() async throws -> Bool {
        guard let button = showAllButton() else { return false }
        let pressed: Bool = try await escalating(deadline: monotonicMs() + 900) { route, _ in
            if route == .accessibility {
                guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                    throw CadenzaError.failure("native_queue_unavailable", "Music refused the Show All press.")
                }
                return true
            }
            self.beginRead(deadline: monotonicMs() + 400)
            let frame = try self.bounds(button)
            try self.postClick(at: CGPoint(x: frame.midX, y: frame.midY), button: .left, route: route)
            return true
        }
        if pressed {
            logger?.log(
                .info, category: "accessibility", action: "songs.show-all",
                "Opened the Songs section of Music's search page")
        }
        return pressed
    }

    private func showAllButton() -> AXUIElement? {
        guard let application else { return nil }
        for window in children(application) where string(window, kAXRoleAttribute) == kAXWindowRole as String {
            let headings = shallow(
                window, maxDepth: 26, maxNodes: 2_000, skipping: [kAXMenuBarRole, kAXMenuRole, kAXRowRole, kAXCellRole]
            ) { node in
                self.labels(node).contains { self.key($0) == "songs" }
            }
            for heading in headings.prefix(4) {
                var scope: AXUIElement? = heading
                for _ in 0..<3 {
                    guard let current = scope else { break }
                    let buttons = shallow(current, maxDepth: 4, maxNodes: 40) { node in
                        [kAXButtonRole, Self.linkRole].contains(self.string(node, kAXRoleAttribute))
                            && self.labels(node).contains { self.key($0) == "show all" }
                    }
                    if let button = buttons.first { return button }
                    scope = parent(current)
                }
            }
        }
        return nil
    }
}
