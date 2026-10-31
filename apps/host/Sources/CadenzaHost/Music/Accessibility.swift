import AppKit
import ApplicationServices
import Foundation

@MainActor
final class MusicAccessibility {
    private let maximumElements = 6_000
    private var application: AXUIElement?
    private var cachedPane: AXUIElement?
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
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw CadenzaError.failure(
                "music_unavailable",
                "Music is starting. Retry in a moment while Cadenza Host connects."
            )
        }
        if currentPid != app.processIdentifier { cachedPane = nil }
        currentPid = app.processIdentifier
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.04)
        application = element
        return element
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

    private func isQueueHeading(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute) == kAXStaticTextRole
            && ["playing next", "up next"].contains(
                label(element).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// AutoPlay's label carries a leading attachment character, so it is matched by substring.
    private func isAutoPlayLabel(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute) == kAXStaticTextRole && label(element).lowercased().contains("autoplay")
    }

    private func scrollArea(enclosing element: AXUIElement) -> AXUIElement? {
        var ancestor = parent(element)
        for _ in 0..<12 {
            guard let current = ancestor else { return nil }
            if string(current, kAXRoleAttribute) == kAXScrollAreaRole { return current }
            ancestor = parent(current)
        }
        return nil
    }

    private func normalized(_ value: String) -> String {
        value
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
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let limit = min(deadline, monotonicMs() + 400)
        while NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            .first?.isActive != true
        {
            guard monotonicMs() < limit else {
                throw CadenzaError.failure("native_queue_unavailable", unavailable)
            }
            usleep(20_000)
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

    private func queuePane() throws -> AXUIElement {
        let root = try root()
        if let cachedPane, !string(cachedPane, kAXRoleAttribute).isEmpty,
            attribute(cachedPane, "AXHidden") as? Bool != true
        {
            return cachedPane
        }
        // Music replaces the Playing Next heading with AutoPlay while the queue is empty.
        let skipped: Set<String> = [kAXRowRole, kAXCellRole, kAXMenuBarRole, kAXMenuRole]
        var markers = shallow(root, maxDepth: 24, maxNodes: 4_000, skipping: skipped) { isQueueHeading($0) }
        if markers.isEmpty {
            markers = shallow(root, maxDepth: 24, maxNodes: 4_000, skipping: skipped) { isAutoPlayLabel($0) }
        }
        for marker in markers {
            guard let pane = scrollArea(enclosing: marker) else { continue }
            try finishRead()
            cachedPane = pane
            return pane
        }
        throw CadenzaError.failure(
            "native_queue_unavailable",
            "Open Music's Playing Next panel. Cadenza needs its visible native queue to verify changes."
        )
    }

    func showQueue(deadline: Int64) throws {
        beginRead(deadline: deadline)
        if (try? queuePane()) != nil { return }
        beginRead(deadline: deadline)
        try showPanel(["playing next", "up next"], deadline: deadline)
        cachedPane = nil
    }

    func showLyrics(deadline: Int64) throws {
        beginRead(deadline: deadline)
        try showPanel(["lyrics", "show lyrics"], deadline: deadline)
        cachedPane = nil
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

    func rows(deadline: Int64? = nil) throws -> [NativeQueueRow] {
        beginRead(deadline: deadline)
        let pane = try queuePane()
        // Rows are read only between the Playing Next heading and AutoPlay. Each row's text is read on its own.
        let nodes = shallow(pane, maxDepth: 10, maxNodes: 1_500, skipping: [kAXRowRole, kAXCellRole]) { _ in true }
        let start = nodes.firstIndex { isQueueHeading($0) }.map { $0 + 1 } ?? nodes.count
        let end = nodes[start...].firstIndex { isAutoPlayLabel($0) } ?? nodes.count
        let result = nodes[start..<end].filter { string($0, kAXRoleAttribute) == kAXRowRole }.compactMap {
            row -> NativeQueueRow? in
            let text = rowTexts(row)
            guard let title = text.first else { return nil }
            return NativeQueueRow(
                token: "\(currentPid ?? 0)-\(CFHash(row))", title: title, artist: text.dropFirst().first ?? "",
                element: row
            )
        }
        try finishRead()
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

    private func isTrackRow(_ row: AXUIElement, song: Song) -> Bool {
        let nodes = shallow(row, maxDepth: 5, maxNodes: 80) { _ in true }
        let values =
            nodes.filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }
            .map { string($0, kAXValueAttribute) }
            + [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].map { string(row, $0) }
        let exactTitle = values.contains { normalized($0) == normalized(song.title) }
        let exactArtist = values.contains { normalized($0) == normalized(song.artist) }
        // Music's album track rows often omit the artist from their AX text. The deep link already identifies
        // catalog tracks; the exact title is the remaining identity exposed by Music's native UI.
        return links(row, descendants: nodes, id: song.id) || (exactTitle && (song.source == "catalog" || exactArtist))
    }

    private func selectedSong(_ song: Song, deadline: Int64) throws -> AXUIElement {
        beginRead(deadline: deadline)
        let root = try root()
        var candidates: [AXUIElement] = []
        for table in trackTables(root) {
            candidates = tableRows(table).prefix(200).filter { isTrackRow($0, song: song) }
            if !candidates.isEmpty { break }
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

    /// The reason Music does not show the exact song as selected, or nil when it does.
    func preparationIssue(_ song: Song) -> String? {
        do {
            _ = try selectedSong(song, deadline: monotonicMs() + 800)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func isPrepared(_ song: Song) -> Bool {
        preparationIssue(song) == nil
    }

    func append(_ song: Song, deadline: Int64, next: Bool = false) throws {
        let row = try selectedSong(song, deadline: deadline)
        beginRead(deadline: deadline)
        try menu(
            row, choices: next ? ["play next"] : ["play last", "add to playing next", "play later"], deadline: deadline
        )
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
        beginRead(deadline: deadline)
        try menu(
            row.element, choices: ["remove from playing next", "remove from up next", "remove"], deadline: deadline)
    }

    private func menu(_ element: AXUIElement, choices: [String], deadline: Int64) throws {
        try requireDeadline(deadline)
        let result = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
        if result != .success {
            guard
                let button = shallow(
                    element, maxDepth: 4, maxNodes: 80,
                    matching: {
                        string($0, kAXRoleAttribute) == kAXMenuButtonRole || label($0).lowercased().contains("more")
                    }
                ).first
            else { throw CadenzaError.failure("native_queue_unavailable", "Music's song menu is unavailable.") }
            try press(button, deadline: deadline)
        }
        guard let root = application else {
            throw CadenzaError.failure("music_unavailable", "Music closed before its menu could be read.")
        }
        // A popup menu is a direct child of the application, so the search stays out of the window's tree.
        let items = shallow(root, maxDepth: 4, maxNodes: 3_000, skipping: [kAXMenuBarRole, kAXWindowRole]) {
            string($0, kAXRoleAttribute) == kAXMenuItemRole
        }
        guard let target = items.first(where: { choices.contains(string($0, kAXTitleAttribute).lowercased()) }) else {
            // The titles Music actually showed make a missing menu action diagnosable from the log alone.
            let shown = items.map { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }.prefix(12)
            logger?.log(
                .warning, category: "accessibility", action: "menu.missing",
                "No matching song menu action",
                metadata: ["wanted": choices.joined(separator: " | "), "shown": shown.joined(separator: " | ")])
            throw CadenzaError.failure(
                "native_queue_unavailable", "The required native queue menu action is unavailable.")
        }
        logger?.log(
            .info, category: "accessibility", action: "menu.pressed", "Pressed \(string(target, kAXTitleAttribute))")
        try press(target, deadline: deadline)
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
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(
            tap: .cghidEventTap)
        restorePointer(previous, source: source)
    }

    private func restorePointer(_ point: CGPoint?, source: CGEventSource) {
        guard let point else { return }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(
            tap: .cghidEventTap)
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
        guard let window = attribute(element, kAXWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() else {
            throw CadenzaError.failure("native_queue_unavailable", "The native queue row has no visible window.")
        }
        // AXWindow returns an AXUIElement, checked by Core Foundation type ID above.
        let windowElement = window as! AXUIElement
        guard attribute(windowElement, kAXMinimizedAttribute) as? Bool != true,
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
        beginRead(deadline: monotonicMs() + 200)
        return try walk(root()).prefix(1_000).map { element in
            let role = string(element, kAXRoleAttribute)
            let id = string(element, kAXIdentifierAttribute)
            return "\(role) id=\(id) \(label(element).prefix(200))"
        }.joined(separator: "\n")
    }
}
