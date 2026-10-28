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

    private func beginRead(deadline: Int64? = nil) {
        readDeadline = min(deadline ?? monotonicMs() + 200, monotonicMs() + 200)
    }

    private func finishRead() throws {
        guard monotonicMs() < readDeadline else {
            throw CadenzaError.failure(
                "native_queue_unavailable",
                "Music's accessibility response exceeded its time budget. Retry after Music finishes loading.")
        }
    }

    var permitted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        // Literal value of kAXTrustedCheckOptionPrompt, which Swift 6 rejects as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func root() throws -> AXUIElement {
        guard permitted else {
            throw CadenzaError.failure("music_permission", "Allow Cadenza Host in Privacy & Security → Accessibility.")
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw CadenzaError.failure("music_unavailable", "Music is starting. Retry in a moment while Cadenza Host connects.")
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

    private func walk(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        while let (element, depth) = stack.popLast(), result.count < maximumElements, monotonicMs() < readDeadline {
            result.append(element)
            if depth < 32 { stack.append(contentsOf: children(element).reversed().map { ($0, depth + 1) }) }
        }
        return result
    }

    private func label(_ element: AXUIElement) -> String {
        let values = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .map { string(element, $0) }.filter { !$0.isEmpty }
        return values.joined(separator: " ")
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

    private func queuePane() throws -> AXUIElement {
        let root = try root()
        if let cachedPane, !string(cachedPane, kAXRoleAttribute).isEmpty,
            attribute(cachedPane, "AXHidden") as? Bool != true
        {
            return cachedPane
        }
        let elements = walk(root)
        for heading in elements where string(heading, kAXRoleAttribute) == kAXStaticTextRole {
            guard
                ["playing next", "up next"].contains(
                    label(heading).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            else { continue }
            var ancestor = parent(heading)
            for _ in 0..<12 {
                guard let element = ancestor else { break }
                if string(element, kAXRoleAttribute) == kAXScrollAreaRole {
                    try finishRead()
                    cachedPane = element
                    return element
                }
                ancestor = parent(element)
            }
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
        let matches = walk(root).filter { element in
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
        let nodes = walk(pane)
        let autoplay =
            nodes.firstIndex {
                string($0, kAXRoleAttribute) == kAXStaticTextRole && label($0).lowercased() == "autoplay"
            } ?? nodes.count
        let result = nodes.prefix(autoplay).filter { string($0, kAXRoleAttribute) == kAXRowRole }.compactMap {
            row -> NativeQueueRow? in
            let text = walk(row).filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }
                .map { string($0, kAXValueAttribute) }.filter { !$0.isEmpty }
            guard let title = text.first else { return nil }
            return NativeQueueRow(
                token: "\(currentPid ?? 0)-\(CFHash(row))", title: title, artist: text.dropFirst().first ?? "",
                element: row
            )
        }
        try finishRead()
        return result
    }

    private func selectedSong(_ song: Song, deadline: Int64) throws -> AXUIElement {
        let queued = Set(try rows(deadline: deadline).map(\.token))
        beginRead(deadline: deadline)
        let root = try root()
        let elements = walk(root)
        let rows = elements.filter {
            string($0, kAXRoleAttribute) == kAXRowRole
                && !queued.contains("\(currentPid ?? 0)-\(CFHash($0))")
        }
        var candidates: [AXUIElement] = []
        for row in rows {
            let nodes = walk(row)
            let values =
                nodes.filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }
                .map { string($0, kAXValueAttribute) }
                + [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].map { string(row, $0) }
            let exactTitle = values.contains { normalized($0) == normalized(song.title) }
            let exactArtist = values.contains { normalized($0) == normalized(song.artist) }
            let linked = links(row, descendants: nodes, id: song.id)
            let exactSelection = selected(row, descendants: nodes) && exactTitle
            // Music's album track rows often omit the artist from their AX text. The
            // deep link already identifies catalog tracks; the selected exact title
            // is the remaining identity exposed by Music's native UI.
            if linked || (exactSelection && (song.source == "catalog" || exactArtist)) { candidates.append(row) }
        }
        try finishRead()
        guard candidates.count == 1, let row = candidates.first else {
            throw CadenzaError.failure(
                "native_queue_unavailable",
                "Music has not exposed one exact selected song. Select this song in Music, then retry."
            )
        }
        return row
    }

    func isPrepared(_ song: Song) -> Bool {
        (try? selectedSong(song, deadline: monotonicMs() + 200)) != nil
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
        let root = try root()
        AXUIElementSetAttributeValue(root, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?.isActive == true
        else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "Bring Music to the front to start this queued request.")
        }
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
                let button = walk(element).first(where: {
                    string($0, kAXRoleAttribute) == kAXMenuButtonRole || label($0).lowercased().contains("more")
                })
            else { throw CadenzaError.failure("native_queue_unavailable", "Music's song menu is unavailable.") }
            try press(button, deadline: deadline)
        }
        guard let root = application else {
            throw CadenzaError.failure("music_unavailable", "Music closed before its menu could be read.")
        }
        let items = walk(root).filter { string($0, kAXRoleAttribute) == kAXMenuItemRole }
        guard let target = items.first(where: { choices.contains(string($0, kAXTitleAttribute).lowercased()) }) else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "The required native queue menu action is unavailable.")
        }
        try press(target, deadline: deadline)
    }

    func move(_ row: NativeQueueRow, before anchor: NativeQueueRow?, deadline: Int64) throws {
        beginRead(deadline: deadline)
        let app = try root()
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?.isActive == true
        else {
            throw CadenzaError.failure("native_queue_unavailable", "Bring Music to the front to rearrange the queue.")
        }
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
        guard !currentTitle.isEmpty else { return "unknown" }
        guard let root = try? root() else { return "unknown" }
        for toolbar in walk(root) where string(toolbar, kAXRoleAttribute) == kAXToolbarRole {
            let nodes = walk(toolbar)
            guard nodes.contains(where: { label($0).contains(currentTitle) }),
                nodes.contains(where: { string($0, kAXRoleAttribute) == kAXSliderRole })
            else { continue }
            let labels = nodes.filter { string($0, kAXRoleAttribute) == kAXButtonRole }.map(label)
            if labels.contains(where: { $0.contains("Dolby Atmos") }) { return "dolby_atmos" }
            if labels.contains(where: { $0.contains("Hi-Res Lossless") }) { return "hi_res_lossless" }
            if labels.contains(where: { $0 == "Lossless" || $0.hasPrefix("Lossless ") }) { return "lossless" }
        }
        return "unknown"
    }

    func mixing(currentTitle: String) -> (active: Bool?, incomingTitle: String?) {
        beginRead()
        guard !currentTitle.isEmpty, let root = try? root() else { return (nil, nil) }
        for toolbar in walk(root) where string(toolbar, kAXRoleAttribute) == kAXToolbarRole {
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
