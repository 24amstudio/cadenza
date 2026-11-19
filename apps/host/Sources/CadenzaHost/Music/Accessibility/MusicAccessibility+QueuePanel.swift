import AppKit
import ApplicationServices
import Foundation

/// Music's Playing Next list: opening the panel, finding its table and reading the queue and AutoPlay rows.
extension MusicAccessibility {
    // Music titles the section by its contents: "Queue" when it holds items, and the empty-state AutoPlay section otherwise.
    static let queueHeadings: Set<String> = ["queue", "playing next", "up next"]

    /// Music's View menu titles the list "Hide Playing Next" while it is visible, so the title is the list's state.
    func playingNextMenuItem() -> AXUIElement? {
        guard let application else { return nil }
        let titles: Set<String> = ["Show Playing Next", "Hide Playing Next", "Show Up Next", "Hide Up Next"]
        for bar in children(application) where string(bar, kAXRoleAttribute) == kAXMenuBarRole as String {
            for menuItem in children(bar) where string(menuItem, kAXTitleAttribute) == "View" {
                for menu in children(menuItem) {
                    if let item = children(menu).first(where: { titles.contains(string($0, kAXTitleAttribute)) }) {
                        return item
                    }
                }
            }
        }
        return nil
    }

    /// Whether Music is showing its Playing Next list.
    func queuePanelOpen() -> Bool {
        beginRead(deadline: monotonicMs() + 500)
        guard (try? root()) != nil else { return false }
        // Full Now Playing shows its queue in place and has no View menu item to open, so a visible queue counts as open.
        return !playQueueTables().isEmpty || (playingNextMenuState()?.open ?? false)
    }

    /// Opens the Playing Next list through Music's View menu, which Accessibility can press while Music is in the
    /// background. Music is brought forward only if that press fails or the list never appears. A list that is already
    /// visible is left alone, and the state is read again before every attempt, because pressing the item while the
    /// list is visible hides it.
    func requestQueuePanel() async throws {
        try await escalating(deadline: monotonicMs() + 1_500, routes: [.accessibility, .system]) { route, limit in
            var state: (item: AXUIElement, open: Bool)?
            repeat {
                self.beginRead(deadline: limit)
                _ = try self.root()
                state = self.playingNextMenuState()
                if state == nil { try await Task.sleep(for: .milliseconds(50)) }
            } while state == nil && monotonicMs() < limit
            guard let state else {
                throw CadenzaError.failure("native_queue_unavailable", "Music's View menu does not offer Playing Next.")
            }
            if state.open { return }
            guard AXUIElementPerformAction(state.item, kAXPressAction as CFString) == .success else {
                throw CadenzaError.failure("native_queue_unavailable", "Music did not open Playing Next.")
            }
            guard try await self.queuePanelAppears(deadline: limit) else {
                throw CadenzaError.failure("native_queue_unavailable", "Music did not show Playing Next.")
            }
        }
    }

    /// The panel counts as shown when its menu item reads "Hide" or the queue list is readable.
    private func queuePanelAppears(deadline: Int64) async throws -> Bool {
        let limit = min(deadline, monotonicMs() + 600)
        repeat {
            try await Task.sleep(for: .milliseconds(50))
            beginRead(deadline: monotonicMs() + 300)
            if playingNextMenuState()?.open == true || (try? queueTable()) != nil { return true }
        } while monotonicMs() < limit
        return false
    }

    /// The View menu item, and whether Music titles it "Hide" because the list is visible. Nil until Music answers.
    func playingNextMenuState() -> (item: AXUIElement, open: Bool)? {
        guard let item = playingNextMenuItem() else { return nil }
        let title = string(item, kAXTitleAttribute)
        guard !title.isEmpty else { return nil }
        return (item, title.hasPrefix("Hide"))
    }

    /// The Now Playing list is a table in the window's right-hand pane. That path is short, so the window is never
    /// walked, and the table is kept until Music replaces it.
    /// The tables on Music's short paths: window > split group > scroll area > table for the library list, and
    /// window > split group > group > scroll area > table for the Now Playing list. Neither walks the window.
    func pathTables() throws -> [AXUIElement] {
        let application = try root()
        var tables: [AXUIElement] = []
        func collect(_ scroll: AXUIElement) {
            tables += children(scroll).filter { string($0, kAXRoleAttribute) == kAXTableRole as String }
        }
        for window in children(application) where string(window, kAXRoleAttribute) == kAXWindowRole as String {
            for split in children(window) where string(split, kAXRoleAttribute) == kAXSplitGroupRole as String {
                for child in children(split) {
                    switch string(child, kAXRoleAttribute) {
                    case kAXScrollAreaRole:
                        collect(child)
                    case kAXGroupRole:
                        for scroll in children(child)
                        where string(scroll, kAXRoleAttribute) == kAXScrollAreaRole as String {
                            collect(scroll)
                        }
                    default:
                        continue
                    }
                }
            }
        }
        return tables
    }

    /// Full Now Playing nests its queue in a group described as "play queue", which the split-view paths never reach.
    /// The search is bounded because Music's window is large.
    func playQueueTables() -> [AXUIElement] {
        guard let application = try? root() else { return [] }
        var tables: [AXUIElement] = []
        for window in children(application) where string(window, kAXRoleAttribute) == kAXWindowRole as String {
            let groups = shallow(
                window, maxDepth: 8, maxNodes: 600, skipping: [kAXRowRole, kAXCellRole, kAXMenuBarRole, kAXMenuRole]
            ) { string($0, kAXDescriptionAttribute) == "play queue" }
            for group in groups {
                for scroll in children(group) where string(scroll, kAXRoleAttribute) == kAXScrollAreaRole as String {
                    tables += children(scroll).filter { string($0, kAXRoleAttribute) == kAXTableRole as String }
                }
            }
        }
        return tables
    }

    /// Whether the element sits inside Music's Playing Next list, which holds History, the queue and AutoPlay rather
    /// than the songs on the page. Song rows are never taken from it.
    func inPlayQueue(_ element: AXUIElement) -> Bool {
        var ancestor: AXUIElement? = element
        for _ in 0..<8 {
            guard let current = ancestor else { return false }
            if string(current, kAXDescriptionAttribute) == "play queue" { return true }
            ancestor = parent(current)
        }
        return false
    }

    func queueTable() throws -> AXUIElement {
        if let cachedQueueTable, string(cachedQueueTable, kAXRoleAttribute) == kAXTableRole as String {
            return cachedQueueTable
        }
        cachedQueueTable = nil
        let tables = try pathTables() + playQueueTables()
        // The Now Playing list is the table whose visible rows show its own sections. The library list never does.
        // With the menu open, the right-most table is the fallback, because the Now Playing list sits there.
        let panelShown = playingNextMenuItem().map { string($0, kAXTitleAttribute).hasPrefix("Hide") } ?? false
        guard
            let table = tables.first(where: showsQueueSections)
                ?? (panelShown ? tables.max(by: { position($0).x < position($1).x }) : nil)
        else {
            throw CadenzaError.failure(
                "native_queue_unavailable",
                "Open Music's Playing Next panel. Cadenza needs its visible native queue to verify changes.")
        }
        cachedQueueTable = table
        return table
    }

    func showsQueueSections(_ table: AXUIElement) -> Bool {
        let visible = attribute(table, "AXVisibleRows") as? [AXUIElement] ?? []
        return visible.contains { row in
            let text = key(firstText(row))
            return Self.queueHeadings.contains(text) || text == "history" || isAutoPlayText(text)
        }
    }

    /// The section after the queue: AutoPlay, or "Continue Playing" in newer layouts of Music's Up Next list.
    func isAutoPlayText(_ key: String) -> Bool {
        key.contains("autoplay") || key.contains("continue playing")
    }

    /// The queue is the requests between the Playing Next heading and AutoPlay. Music lists its History above the queue,
    /// so AutoPlay is found from the end of the table and the heading from AutoPlay backwards. The History heading
    /// marks an empty queue.
    func rows(deadline: Int64? = nil) throws -> [NativeQueueRow] {
        beginRead(deadline: deadline)
        let table = try queueTable()
        let all = tableRows(table)
        // Music states an empty Up Next list in its visible rows, so a long history never has to be scanned.
        let visible = attribute(table, "AXVisibleRows") as? [AXUIElement] ?? []
        if visible.contains(where: { key(firstText($0)).contains("no music in the queue") }) {
            return []
        }
        // The mark expires, because a change made in Music can keep the row count and AutoPlay position the same.
        if let mark = emptyQueueMark, CFEqual(mark.table, table), all.count == mark.rows, mark.autoPlay < all.count,
            monotonicMs() - mark.takenAt < 15_000, isAutoPlayText(key(firstText(all[mark.autoPlay])))
        {
            return []
        }
        let candidates = headingCandidates(all)
        // The queue ends at AutoPlay, and starts after the Playing Next heading or the History heading above it.
        var end =
            try lastIndex(in: all, before: all.count, among: candidates) { isAutoPlayText($0) }?.index ?? all.count
        let marker = try lastIndex(in: all, before: end, among: candidates) {
            Self.queueHeadings.contains($0) || $0 == "history"
        }
        let start = marker.map { Self.queueHeadings.contains($0.text) ? $0.index + 1 : end }
        guard let start else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "Music's queue layout was not recognized. Show Playing Next and try again.")
        }
        // "Continue Playing" comes before AutoPlay, so the queue ends at the first section marker after it starts.
        for index in start..<end {
            try requireReadTime()
            if isAutoPlayText(key(firstText(all[index]))) {
                end = index
                break
            }
        }
        var result: [NativeQueueRow] = []
        for row in all[start..<end] {
            try requireReadTime()
            if let native = nativeRow(row) { result.append(native) }
        }
        let isEmpty = result.isEmpty && start == end && end < all.count
        emptyQueueMark = isEmpty ? (table, all.count, end, monotonicMs()) : nil
        return result
    }

    /// Music creates a row's views only when its text is read, which costs about 20 ms per row outside the viewport. A
    /// row's height is cheap to read, and section headings are drawn at a different height than song rows, so the
    /// headings are found from the heights alone. Nil when every row has the same height.
    private func headingCandidates(_ rows: [AXUIElement]) -> Set<Int>? {
        var heights: [CGFloat] = []
        for row in rows {
            guard let value = attribute(row, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else {
                return nil
            }
            var size = CGSize.zero
            // The size attribute has been checked against AXValue's CF type.
            AXValueGetValue(value as! AXValue, .cgSize, &size)
            heights.append(size.height)
        }
        let usual = Dictionary(grouping: heights, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        let found = Set(heights.indices.filter { heights[$0] != usual })
        return found.isEmpty ? nil : found
    }

    /// The last row before `limit` whose text satisfies `matches`. Rows outside `candidates` are skipped; if none of
    /// the candidates matches, every row is read, so a layout with same-height headings is still recognized.
    private func lastIndex(
        in rows: [AXUIElement], before limit: Int, among candidates: Set<Int>?, matches: (String) throws -> Bool
    ) throws -> (index: Int, text: String)? {
        for restricted in candidates == nil ? [false] : [true, false] {
            for index in stride(from: limit - 1, through: 0, by: -1)
            where !restricted || candidates?.contains(index) == true {
                try requireReadTime()
                let text = key(firstText(rows[index]))
                if try matches(text) { return (index, text) }
            }
        }
        return nil
    }

    func nativeRow(_ row: AXUIElement) -> NativeQueueRow? {
        let text = rowTexts(row).map(displayText)
        guard let title = text.first else { return nil }
        // The second text reads "Artist — Album" in the Up Next list, so only the artist is kept.
        let artist = text.dropFirst().first?.components(separatedBy: " — ").first ?? ""
        return NativeQueueRow(token: "\(currentPid ?? 0)-\(CFHash(row))", title: title, artist: artist, element: row)
    }

    /// AutoPlay is the list Music plays after the queue. It is read for display only, and Cadenza never changes it.
    func autoPlayRows(deadline: Int64? = nil) throws -> [NativeQueueRow] {
        beginRead(deadline: deadline)
        let all = tableRows(try queueTable())
        // AutoPlay is the last section, so its heading is found from the end of the table.
        guard
            let heading = stride(from: all.count - 1, through: 0, by: -1).first(where: { index in
                isAutoPlayText(key(firstText(all[index])))
            })
        else { return [] }
        var result: [NativeQueueRow] = []
        for row in all[(heading + 1)...] {
            try requireReadTime()
            if let native = nativeRow(row) { result.append(native) }
        }
        return result
    }

    func tableRows(_ table: AXUIElement) -> [AXUIElement] {
        (attribute(table, kAXRowsAttribute) as? [AXUIElement]) ?? children(table)
    }
}
