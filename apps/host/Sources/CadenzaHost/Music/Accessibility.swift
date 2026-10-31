import AppKit
import ApplicationServices
import Foundation

@MainActor
final class MusicAccessibility {
    private let maximumElements = 6_000
    private var application: AXUIElement?
    private var cachedQueueTable: AXUIElement?
    // An empty queue is the History list directly above AutoPlay. Its row count and AutoPlay row confirm it cheaply.
    private var emptyQueueMark: (table: AXUIElement, rows: Int, autoPlay: Int, takenAt: Int64)?
    private var cachedTrackTable: AXUIElement?
    private var currentPid: pid_t?
    private var readDeadline: Int64 = 0
    private var lastPermissionPrompt: Int64 = 0
    var logger: HostLogger?

    private func beginRead(deadline: Int64? = nil) {
        // Callers pass the deadline of the whole operation. Without one, a read gets a short local budget.
        readDeadline = deadline ?? monotonicMs() + 200
    }

    private func finishRead() throws {
        guard monotonicMs() < readDeadline else {
            throw CadenzaError.failure(
                "native_queue_unavailable",
                "Music's accessibility response exceeded its time budget. Retry after Music finishes loading.")
        }
    }

    var permitted: Bool { AXIsProcessTrusted() }

    /// Fails with music_permission before a command starts Music work that Accessibility cannot finish.
    func requireAccess() throws {
        _ = try root()
    }

    func requestPermission() {
        // Literal value of kAXTrustedCheckOptionPrompt, which Swift 6 rejects as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func root() throws -> AXUIElement {
        guard permitted else {
            // The macOS prompt is shown at most once every ten minutes, so repeated commands do not stack dialogs.
            logger?.log(
                .warning, category: "accessibility", action: "permission.denied",
                "Accessibility access is not granted to Cadenza Host")
            if monotonicMs() - lastPermissionPrompt > 600_000 {
                lastPermissionPrompt = monotonicMs()
                logger?.log(
                    .info, category: "accessibility", action: "permission.prompted",
                    "Showed the macOS Accessibility prompt")
                requestPermission()
            }
            throw CadenzaError.failure("music_permission", "Allow Cadenza Host in Privacy & Security → Accessibility.")
        }
        guard let app = runningMusic() else {
            throw CadenzaError.failure("music_unavailable", "Music is not running. Open Music, then try again.")
        }
        if currentPid != app.processIdentifier {
            cachedQueueTable = nil
            cachedTrackTable = nil
            emptyQueueMark = nil
        }
        currentPid = app.processIdentifier
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.04)
        application = element
        return element
    }

    // NSRunningApplication can omit a running Music for about a second after Music changes state, so the lookup retries.
    private func runningMusic() -> NSRunningApplication? {
        let deadline = monotonicMs() + 1_000
        repeat {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first {
                return app
            }
            usleep(50_000)
        } while monotonicMs() < deadline
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard monotonicMs() < readDeadline else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func parent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // AXParent has been checked against the AXUIElement Core Foundation type.
        let element: AXUIElement = value as! AXUIElement
        return element
    }

    /// Full-subtree walk for small subtrees such as one row. Large views go through `shallow`, because a full walk
    /// of Music's window reads thousands of elements and cannot finish inside a read budget.
    private func walk(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        while let (element, depth) = stack.popLast(), result.count < maximumElements, monotonicMs() < readDeadline {
            result.append(element)
            if depth < 32 { stack.append(contentsOf: children(element).reversed().map { ($0, depth + 1) }) }
        }
        return result
    }

    /// Depth- and count-limited search. Subtrees whose roles are in `skipping` are reported but not entered, so
    /// rows and cells are never descended into unless a caller asks for them.
    private func shallow(
        _ start: AXUIElement,
        maxDepth: Int,
        maxNodes: Int,
        skipping: Set<String> = [],
        matching predicate: (AXUIElement) -> Bool
    ) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var visited = 0
        var stack: [(AXUIElement, Int)] = [(start, 0)]
        while let (element, depth) = stack.popLast(), visited < maxNodes, monotonicMs() < readDeadline {
            visited += 1
            if predicate(element) { found.append(element) }
            if depth >= maxDepth || skipping.contains(string(element, kAXRoleAttribute)) { continue }
            stack.append(contentsOf: children(element).reversed().map { ($0, depth + 1) })
        }
        return found
    }

    private func label(_ element: AXUIElement) -> String {
        let values = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .map { string(element, $0) }.filter { !$0.isEmpty }
        return values.joined(separator: " ")
    }

    private func normalized(_ value: String) -> String {
        // Music draws an inline explicit badge as U+FFFC after explicit titles, which the song title does not contain.
        value
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func selected(_ element: AXUIElement, descendants: [AXUIElement]) -> Bool {
        let nodes = descendants + [element]
        return nodes.contains {
            (attribute($0, kAXSelectedAttribute) as? Bool) == true
                || (attribute($0, kAXFocusedAttribute) as? Bool) == true
        }
    }

    private func links(_ element: AXUIElement, descendants: [AXUIElement], id: String) -> Bool {
        (descendants + [element]).contains { node in
            if string(node, kAXIdentifierAttribute) == id { return true }
            guard let url = attribute(node, kAXURLAttribute) as? URL,
                url.host == "music.apple.com"
            else { return false }
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return parts?.queryItems?.contains { $0.name == "i" && $0.value == id } == true
                || url.path.hasSuffix("/\(id)")
        }
    }

    private func requireDeadline(_ deadline: Int64) throws {
        guard monotonicMs() < deadline else {
            throw CadenzaError.failure("expired", "The request expired before the native queue action.")
        }
    }

    private func press(_ element: AXUIElement, deadline: Int64) throws {
        try requireDeadline(deadline)
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw CadenzaError.failure("music_unavailable", "Music did not accept the native button action.")
        }
    }

    /// Music comes forward asynchronously after AX asks for it, so wait briefly rather than
    /// reading `isActive` immediately after the request.
    private func bringMusicForward(deadline: Int64, unavailable: String) throws {
        let app = try root()
        let limit = min(deadline, monotonicMs() + 1_000)
        var requested = false
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.Music" {
            guard monotonicMs() < limit else {
                throw CadenzaError.failure("native_queue_unavailable", unavailable)
            }
            // Activation is requested once; repeating it on every poll would keep moving focus back to Music.
            if !requested {
                requested = true
                runningMusic()?.activate()
                AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            }
            usleep(20_000)
        }
    }

    // Queue edits send clicks and keys to whatever is on screen, so Music must already be frontmost. macOS does not let
    // this app take focus from the app the user is working in, so the request is refused instead of dispatched.
    func requireFrontmost() throws {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Music" else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "Bring Music to the front before changing the queue.")
        }
    }

    private func click(_ element: AXUIElement, deadline: Int64, count: Int = 1) throws {
        try bringMusicForward(deadline: deadline, unavailable: "Bring Music to the front before selecting a song.")
        let frame = try bounds(element)
        try requireDeadline(deadline)
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw CadenzaError.failure("native_queue_unavailable", "The native Music input source is unavailable.")
        }
        let previous = CGEvent(source: nil)?.location
        defer { restorePointer(previous, source: source) }
        for clickState in 1...count {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(
                    mouseEventSource: source, mouseType: type,
                    mouseCursorPosition: CGPoint(x: frame.midX, y: frame.midY), mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    // Music titles the section by its contents: "Queue" when it holds items, and the empty-state AutoPlay section otherwise.
    private static let queueHeadings: Set<String> = ["queue", "playing next", "up next"]

    /// Music's View menu titles the list "Hide Playing Next" while it is visible, so the title is the list's state.
    private func playingNextMenuItem() -> AXUIElement? {
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
        return playingNextMenuState()?.open ?? false
    }

    /// Opens the Playing Next list through Music's View menu. A list that is already visible is left alone. The item
    /// is pressed only after its title is readable, because pressing it while the list is visible hides the list.
    func requestQueuePanel() throws {
        let deadline = monotonicMs() + 1_500
        var state: (item: AXUIElement, open: Bool)?
        repeat {
            beginRead(deadline: deadline)
            _ = try root()
            state = playingNextMenuState()
            if state == nil { usleep(50_000) }
        } while state == nil && monotonicMs() < deadline
        guard let state else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's View menu does not offer Playing Next.")
        }
        if state.open { return }
        guard AXUIElementPerformAction(state.item, kAXPressAction as CFString) == .success else {
            throw CadenzaError.failure("native_queue_unavailable", "Music did not open Playing Next.")
        }
    }

    /// The View menu item, and whether Music titles it "Hide" because the list is visible. Nil until Music answers.
    private func playingNextMenuState() -> (item: AXUIElement, open: Bool)? {
        guard let item = playingNextMenuItem() else { return nil }
        let title = string(item, kAXTitleAttribute)
        guard !title.isEmpty else { return nil }
        return (item, title.hasPrefix("Hide"))
    }

    /// The Now Playing list is a table in the window's right-hand pane. That path is short, so the window is never
    /// walked, and the table is kept until Music replaces it.
    /// The tables on Music's short paths: window > split group > scroll area > table for the library list, and
    /// window > split group > group > scroll area > table for the Now Playing list. Neither walks the window.
    private func pathTables() throws -> [AXUIElement] {
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

    private func queueTable() throws -> AXUIElement {
        if let cachedQueueTable, string(cachedQueueTable, kAXRoleAttribute) == kAXTableRole as String {
            return cachedQueueTable
        }
        cachedQueueTable = nil
        let tables = try pathTables()
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

    private func showsQueueSections(_ table: AXUIElement) -> Bool {
        let visible = attribute(table, "AXVisibleRows") as? [AXUIElement] ?? []
        return visible.contains { row in
            let text = key(firstText(row))
            return Self.queueHeadings.contains(text) || text == "history" || isAutoPlayText(text)
        }
    }

    private func position(_ element: AXUIElement) -> CGPoint {
        guard let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return .zero
        }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    /// The section after the queue: AutoPlay, or "Continue Playing" in newer layouts of Music's Up Next list.
    private func isAutoPlayText(_ key: String) -> Bool {
        key.contains("autoplay") || key.contains("continue playing")
    }

    /// Row text as Music shows it, without the inline explicit badge (U+FFFC) that follows explicit titles.
    private func displayText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Row text without Music's attachment glyphs, for comparing section headings.
    private func key(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The first text in a row, read through its cells. The walk is direct, because each call is an Accessibility request.
    private func firstText(_ row: AXUIElement) -> String {
        for cell in children(row) {
            for item in children(cell) where string(item, kAXRoleAttribute) == kAXStaticTextRole as String {
                let value = string(item, kAXValueAttribute)
                if !value.isEmpty { return value }
            }
        }
        return ""
    }

    private func requireReadTime() throws {
        guard monotonicMs() < readDeadline else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's queue is still loading. Try again.")
        }
    }

    func showLyrics(deadline: Int64) throws {
        beginRead(deadline: deadline)
        try showPanel(["lyrics", "show lyrics"], deadline: deadline)
    }

    private func showPanel(_ names: [String], deadline: Int64) throws {
        let root = try root()
        let matches = shallow(
            root, maxDepth: 24, maxNodes: 4_000, skipping: [kAXRowRole, kAXCellRole, kAXMenuBarRole, kAXMenuRole]
        ) { element in
            let role = string(element, kAXRoleAttribute)
            guard [kAXButtonRole, kAXCheckBoxRole].contains(role),
                attribute(element, "AXHidden") as? Bool != true
            else { return false }
            let values = [
                string(element, kAXDescriptionAttribute),
                string(element, kAXTitleAttribute),
                string(element, kAXIdentifierAttribute),
                label(element),
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return names.contains { name in
                values.contains { value in value == name || value.contains(name) }
            }
        }
        guard
            let button = matches.first(where: { (attribute($0, kAXValueAttribute) as? Bool) == true }) ?? matches.first
        else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "The required Music sidebar button is not accessible.")
        }
        if (attribute(button, kAXValueAttribute) as? Bool) == true { return }
        try press(button, deadline: deadline)
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
        var end = all.count
        for index in stride(from: all.count - 1, through: 0, by: -1) {
            try requireReadTime()
            if isAutoPlayText(key(firstText(all[index]))) {
                end = index
                break
            }
        }
        var start: Int?
        for index in stride(from: end - 1, through: 0, by: -1) {
            try requireReadTime()
            let text = key(firstText(all[index]))
            if Self.queueHeadings.contains(text) {
                start = index + 1
                break
            }
            if text == "history" {
                start = end
                break
            }
        }
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
            let text = rowTexts(row).map(displayText)
            guard let title = text.first else { continue }
            // The second text reads "Artist — Album" in the Up Next list, so only the artist is kept.
            let artist = text.dropFirst().first?.components(separatedBy: " — ").first ?? ""
            result.append(
                NativeQueueRow(
                    token: "\(currentPid ?? 0)-\(CFHash(row))", title: title, artist: artist, element: row))
        }
        let isEmpty = result.isEmpty && start == end && end < all.count
        emptyQueueMark = isEmpty ? (table, all.count, end, monotonicMs()) : nil
        return result
    }

    private func rowTexts(_ row: AXUIElement) -> [String] {
        shallow(row, maxDepth: 5, maxNodes: 80) { string($0, kAXRoleAttribute) == kAXStaticTextRole }
            .map { string($0, kAXValueAttribute) }
            .filter { !$0.isEmpty }
    }

    /// The track table that contains the requested song. Tables with a selected row come first, because a
    /// song opened by its link is selected as soon as Music shows its album.
    private func trackTables(_ root: AXUIElement) -> [AXUIElement] {
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

    private func tableRows(_ table: AXUIElement) -> [AXUIElement] {
        (attribute(table, kAXRowsAttribute) as? [AXUIElement]) ?? children(table)
    }

    private func isTrackRow(_ row: AXUIElement, song: Song, titleIsEnough: Bool = false) -> Bool {
        let nodes = shallow(row, maxDepth: 5, maxNodes: 80) { _ in true }
        let values =
            nodes.filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }
            .map { string($0, kAXValueAttribute) }
            + [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].map { string(row, $0) }
        let exactTitle = values.contains { normalized($0) == normalized(song.title) }
        let exactArtist = values.contains { normalized($0) == normalized(song.artist) }
        // Music's album track rows often omit the artist from their AX text. The deep link already identifies
        // catalog tracks; the exact title is the remaining identity exposed by Music's native UI.
        return links(row, descendants: nodes, id: song.id)
            || (exactTitle && (song.source == "catalog" || exactArtist || titleIsEnough))
    }

    private func selectedSong(_ song: Song, deadline: Int64) throws -> AXUIElement {
        beginRead(deadline: deadline)
        var candidates: [AXUIElement] = []
        if let table = cachedTrackTable {
            candidates = matchingRows(table, song: song)
        }
        if candidates.isEmpty {
            // The short path finds the library list without walking the window. The full walk is only the fallback.
            for table in try pathTables() + trackTables(try root()) {
                candidates = matchingRows(table, song: song)
                if !candidates.isEmpty {
                    cachedTrackTable = table
                    break
                }
            }
        }
        try finishRead()
        guard candidates.count == 1, let row = candidates.first else {
            throw CadenzaError.failure(
                "native_queue_unavailable",
                "Music did not expose one exact song after navigation. Retry the preparation action."
            )
        }
        beginRead(deadline: deadline)
        if !selected(row, descendants: walk(row)) {
            try click(row, deadline: deadline)
            beginRead(deadline: deadline)
            guard selected(row, descendants: walk(row)) else {
                throw CadenzaError.failure(
                    "native_queue_unavailable", "Music did not select the exact song row. Retry the preparation action."
                )
            }
        }
        return row
    }

    // Music selects the track it navigated to, so selected rows are checked before the table's other rows.
    private func matchingRows(_ table: AXUIElement, song: Song) -> [AXUIElement] {
        let selectedRows = (attribute(table, kAXSelectedRowsAttribute) as? [AXUIElement]) ?? []
        // Music selects the one track it navigated to. Album rows often omit the artist, so a lone selected row
        // is matched by title alone.
        if selectedRows.count == 1, isTrackRow(selectedRows[0], song: song, titleIsEnough: true) {
            return selectedRows
        }
        let selected = selectedRows.filter { isTrackRow($0, song: song) }
        if !selected.isEmpty { return selected }
        // The title is compared first, because the full row check costs many Accessibility calls per row.
        return tableRows(table).prefix(200)
            .filter { normalized(firstText($0)) == normalized(song.title) }
            .filter { isTrackRow($0, song: song) }
    }

    /// The reason Music does not show the exact song as selected, or nil when it does.
    func preparationIssue(_ song: Song, deadline: Int64 = monotonicMs() + 800) -> String? {
        do {
            _ = try selectedSong(song, deadline: deadline)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func isPrepared(_ song: Song) -> Bool {
        preparationIssue(song) == nil
    }

    func append(_ song: Song, deadline: Int64, next: Bool = false) throws {
        emptyQueueMark = nil
        let row = try selectedSong(song, deadline: deadline)
        // Music enables a track's menu actions only once the row has focus, so the row is clicked before its menu opens.
        try click(row, deadline: deadline)
        if try pressSongMenuItem(next ? "play next" : "add to queue", deadline: deadline) { return }
        // Music disables Add to Queue until the queue has an item. For an empty queue, Play Next is the same position.
        guard !next else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's Play Next is unavailable for this song.")
        }
        try requireEmptyQueue(deadline: deadline)
        guard try pressSongMenuItem("play next", deadline: deadline) else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's Add to Queue is unavailable for this song.")
        }
    }

    func play(_ row: NativeQueueRow, deadline: Int64) throws {
        beginRead(deadline: deadline)
        try bringMusicForward(
            deadline: deadline, unavailable: "Bring Music to the front to start this queued request.")
        let frame = try bounds(row.element)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        try requireDeadline(deadline)
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw CadenzaError.failure("native_queue_unavailable", "The native Music input source is unavailable.")
        }
        let previous = CGEvent(source: nil)?.location
        defer { restorePointer(previous, source: source) }
        for count: Int64 in [1, 2] {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(
                    mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: count)
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    func remove(_ row: NativeQueueRow, deadline: Int64) throws {
        emptyQueueMark = nil
        try click(row.element, deadline: deadline)
        beginRead(deadline: deadline)
        try menu(
            row.element,
            choices: ["remove from queue", "remove from playing next", "remove from up next", "remove"],
            deadline: deadline)
    }

    private func popupMenu(near element: AXUIElement) -> AXUIElement? {
        var ancestor: AXUIElement? = element
        for _ in 0..<6 {
            guard let current = ancestor else { return nil }
            if let popup = children(current).first(where: { string($0, kAXRoleAttribute) == kAXMenuRole as String }) {
                return popup
            }
            ancestor = parent(current)
        }
        return nil
    }

    /// Music answers mouse events on a row, while Accessibility actions on its menu are refused. The row's menu is opened
    /// with a right-click and the matching item is clicked where it is drawn.
    private func menu(_ element: AXUIElement, choices: [String], deadline: Int64) throws {
        try requireDeadline(deadline)
        let frame = try bounds(element)
        // The pointer stays on the row while the popup is open, so the popup is not dismissed before its item is chosen.
        try postClick(at: CGPoint(x: frame.midX, y: frame.midY), button: .right, restoresPointer: false)
        var popup: AXUIElement?
        repeat {
            beginRead(deadline: deadline)
            popup = popupMenu(near: element)
            if popup == nil { usleep(40_000) }
        } while popup == nil && monotonicMs() < deadline
        guard let popup else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's song menu did not open.")
        }
        beginRead(deadline: deadline)
        let items = children(popup).filter { string($0, kAXRoleAttribute) == kAXMenuItemRole as String }
        guard let target = items.first(where: { choices.contains(string($0, kAXTitleAttribute).lowercased()) }) else {
            // The titles Music actually showed make a missing menu action diagnosable from the log alone.
            let shown = items.map { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }.prefix(12)
            logger?.log(
                .warning, category: "accessibility", action: "menu.missing",
                "No matching song menu action",
                metadata: ["wanted": choices.joined(separator: " | "), "shown": shown.joined(separator: " | ")])
            try dismissPopup(near: element)
            throw CadenzaError.failure(
                "native_queue_unavailable", "The required native queue menu action is unavailable.")
        }
        logger?.log(
            .info, category: "accessibility", action: "menu.pressed", "Pressed \(string(target, kAXTitleAttribute))")
        let targetFrame = try bounds(target)
        try postClick(at: CGPoint(x: targetFrame.midX, y: targetFrame.midY), button: .left)
    }

    // The Song menu bar acts on the focused track, so the caller must select the row first. Returns false when Music
    // has the action disabled, since pressing a disabled item does nothing.
    private func pressSongMenuItem(_ title: String, deadline: Int64) throws -> Bool {
        try requireDeadline(deadline)
        beginRead(deadline: deadline)
        guard
            let bar = children(try root()).first(where: { string($0, kAXRoleAttribute) == kAXMenuBarRole }),
            let songMenu = children(bar).first(where: { string($0, kAXTitleAttribute) == "Song" })
        else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's Song menu is unavailable.")
        }
        AXUIElementPerformAction(songMenu, kAXPressAction as CFString)
        var target: AXUIElement?
        repeat {
            beginRead(deadline: deadline)
            target = children(songMenu).flatMap { children($0) }.first {
                string($0, kAXTitleAttribute).lowercased() == title
            }
            if target == nil { usleep(40_000) }
        } while target == nil && monotonicMs() < deadline
        guard let target else {
            closeMenu(songMenu)
            throw CadenzaError.failure("native_queue_unavailable", "The Song menu's \(title) action is unavailable.")
        }
        guard attribute(target, kAXEnabledAttribute) as? Bool == true else {
            closeMenu(songMenu)
            return false
        }
        guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
            closeMenu(songMenu)
            throw CadenzaError.failure(
                "native_queue_unavailable", "Music did not accept the Song menu's \(title) action.")
        }
        return true
    }

    // A posted Escape key does not reliably close Music's menu bar menus, so the open menu is cancelled directly.
    private func closeMenu(_ menuBarItem: AXUIElement) {
        for menu in children(menuBarItem) where string(menu, kAXRoleAttribute) == kAXMenuRole {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
    }

    private func requireEmptyQueue(deadline: Int64) throws {
        if !queuePanelOpen() { try requestQueuePanel() }
        guard try rows(deadline: deadline).isEmpty else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's Add to Queue is unavailable for this song.")
        }
    }

    private func postClick(at point: CGPoint, button: CGMouseButton, restoresPointer: Bool = true) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw CadenzaError.failure("native_queue_unavailable", "The native Music input source is unavailable.")
        }
        let previous = CGEvent(source: nil)?.location
        defer { if restoresPointer { restorePointer(previous, source: source) } }
        let types: [CGEventType] =
            button == .right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
                .post(tap: .cghidEventTap)
        }
    }

    // Escape and AX cancel leave Music's popup menus open, and an open popup stalls Music's scripting. A click outside
    // the popup dismisses it, so the click lands on the blank toolbar of the window that owns the popup.
    private func dismissPopup(near element: AXUIElement) throws {
        guard let window = windowAncestor(of: element) else { return }
        let frame = try bounds(window)
        try postClick(at: CGPoint(x: frame.midX, y: frame.minY + 12), button: .left)
    }

    func move(_ row: NativeQueueRow, before anchor: NativeQueueRow?, deadline: Int64) throws {
        beginRead(deadline: deadline)
        try bringMusicForward(deadline: deadline, unavailable: "Bring Music to the front to rearrange the queue.")
        let queue = try rows(deadline: deadline)
        guard let destination = anchor ?? queue.last else { return }
        let origin = try bounds(row.element)
        let target = try bounds(destination.element)
        let point = CGPoint(x: origin.midX, y: origin.midY)
        let end = CGPoint(x: target.midX, y: anchor == nil ? target.maxY - 2 : target.minY + 2)
        try requireDeadline(deadline)
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw CadenzaError.failure("native_queue_unavailable", "Cannot create the native queue drag.")
        }
        let previous = CGEvent(source: nil)?.location
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        // A single jump to the drop point is not recognised as a drag, so the pointer travels along the path.
        let steps = 12
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let position = CGPoint(
                x: point.x + (end.x - point.x) * fraction, y: point.y + (end.y - point.y) * fraction)
            CGEvent(
                mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: position,
                mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(
            tap: .cghidEventTap)
        restorePointer(previous, source: source)
    }

    private func restorePointer(_ point: CGPoint?, source: CGEventSource) {
        guard let point else { return }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(
            tap: .cghidEventTap)
    }

    private func windowAncestor(of element: AXUIElement) -> AXUIElement? {
        var ancestor: AXUIElement? = element
        for _ in 0..<12 {
            guard let current = ancestor else { return nil }
            if string(current, kAXRoleAttribute) == kAXWindowRole as String { return current }
            ancestor = parent(current)
        }
        return nil
    }

    private func bounds(_ element: AXUIElement) throws -> CGRect {
        guard let position = attribute(element, kAXPositionAttribute),
            let size = attribute(element, kAXSizeAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else {
            throw CadenzaError.failure("native_queue_unavailable", "The native queue row is not visible.")
        }
        // AX's position and size attributes have been checked against AXValue's CF type.
        let positionValue = position as! AXValue
        let sizeValue = size as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
            AXValueGetValue(sizeValue, .cgSize, &dimensions),
            dimensions.width > 0, dimensions.height > 0
        else {
            throw CadenzaError.failure("native_queue_unavailable", "The native queue row is not visible.")
        }
        let frame = CGRect(origin: point, size: dimensions)
        // Rows do not expose AXWindow, so the window is found among the row's ancestors.
        guard let window = windowAncestor(of: element) else {
            throw CadenzaError.failure("native_queue_unavailable", "The native queue row has no visible window.")
        }
        guard attribute(window, kAXMinimizedAttribute) as? Bool != true,
            NSScreen.screens.contains(where: { screen in
                let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
                let screenBounds = CGRect(
                    x: screen.frame.minX, y: desktopTop - screen.frame.maxY, width: screen.frame.width,
                    height: screen.frame.height)
                return screenBounds.contains(CGPoint(x: frame.midX, y: frame.midY))
            })
        else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "Scroll the requested Music row into view before moving or playing it.")
        }
        return frame
    }

    func quality(currentTitle: String) -> String {
        beginRead()
        guard !currentTitle.isEmpty, let root = try? root() else { return "unknown" }
        // Music keeps the audio tier in its mini player badge. The toolbar this used to search does not hold it.
        let badge = shallow(
            root, maxDepth: 14, maxNodes: 1_500, skipping: [kAXMenuBarRole, kAXMenuRole, kAXRowRole, kAXCellRole]
        ) {
            string($0, kAXIdentifierAttribute) == "Music.miniPlayer.audioBadge"
        }.first
        guard let badge else { return "unknown" }
        let text = [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].map { string(badge, $0) }
            .joined(separator: " ")
        return MusicQuality.tier(forBadge: text)
    }

    func mixing(currentTitle: String) -> (active: Bool?, incomingTitle: String?) {
        beginRead()
        guard !currentTitle.isEmpty, let root = try? root() else { return (nil, nil) }
        let toolbars = shallow(root, maxDepth: 12, maxNodes: 1_200, skipping: [kAXMenuBarRole, kAXMenuRole]) {
            string($0, kAXRoleAttribute) == kAXToolbarRole
        }
        for toolbar in toolbars {
            let nodes = walk(toolbar)
            guard nodes.contains(where: { label($0).contains(currentTitle) }) else { continue }
            let active = nodes.contains(where: {
                string($0, kAXIdentifierAttribute) == "automix-transition"
                    && (attribute($0, kAXValueAttribute) as? Bool) == true
            })
            for node in nodes {
                let value = label(node)
                let prefix = "Mixing " + currentTitle + " into "
                if value.hasPrefix(prefix), value.count > prefix.count {
                    return (true, String(value.dropFirst(prefix.count)))
                }
            }
            if active { return (true, nil) }
        }
        return (nil, nil)
    }

    func diagnostic() throws -> String {
        // Attributes are read as each element is visited, so every read must fall inside the deadline.
        beginRead(deadline: monotonicMs() + 4_000)
        var lines: [String] = []
        var stack = [try root()]
        while let element = stack.popLast(), lines.count < 1_000, monotonicMs() < readDeadline {
            let role = string(element, kAXRoleAttribute)
            let id = string(element, kAXIdentifierAttribute)
            lines.append("\(role) id=\(id) \(label(element).prefix(200))")
            stack.append(contentsOf: children(element).reversed())
        }
        return lines.joined(separator: "\n")
    }
}
