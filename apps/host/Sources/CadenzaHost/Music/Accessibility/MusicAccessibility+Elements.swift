import AppKit
import ApplicationServices
import Foundation

/// Raw Accessibility reads: attributes, bounded tree searches, row text and element geometry.
extension MusicAccessibility {
    /// One attribute read. A slow answer is `.timedOut`, which a bounded poll retries, rather than `.absent`, which
    /// means Music answered and has no such value.
    enum AttributeRead {
        case value(CFTypeRef)
        case absent
        case timedOut
    }

    func read(_ element: AXUIElement, _ name: String) -> AttributeRead {
        guard monotonicMs() < readDeadline else { return .timedOut }
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
        case .success: return value.map(AttributeRead.value) ?? .absent
        case .cannotComplete: return .timedOut
        default: return .absent
        }
    }

    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard case .value(let value) = read(element, name) else { return nil }
        return value
    }

    func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    func parent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // AXParent has been checked against the AXUIElement Core Foundation type.
        let element: AXUIElement = value as! AXUIElement
        return element
    }

    /// Full-subtree walk for small subtrees such as one row. Large views go through `shallow`, because a full walk
    /// of Music's window reads thousands of elements and cannot finish inside a read budget.
    func walk(_ root: AXUIElement) -> [AXUIElement] {
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
    func shallow(
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

    func label(_ element: AXUIElement) -> String {
        let values = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .map { string(element, $0) }.filter { !$0.isEmpty }
        return values.joined(separator: " ")
    }

    func position(_ element: AXUIElement) -> CGPoint {
        guard let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return .zero
        }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    /// Row text as Music shows it, without the inline explicit badge (U+FFFC) that follows explicit titles.
    func displayText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Row text without Music's attachment glyphs, for comparing section headings.
    func key(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The first text in a row, read through its cells. The walk is direct, because each call is an Accessibility request.
    func firstText(_ row: AXUIElement) -> String {
        for cell in children(row) {
            for item in children(cell) where string(item, kAXRoleAttribute) == kAXStaticTextRole as String {
                let value = string(item, kAXValueAttribute)
                if !value.isEmpty { return value }
            }
        }
        return ""
    }

    func rowTexts(_ row: AXUIElement) -> [String] {
        shallow(row, maxDepth: 5, maxNodes: 80) { string($0, kAXRoleAttribute) == kAXStaticTextRole }
            .map { string($0, kAXValueAttribute) }
            .filter { !$0.isEmpty }
    }

    func windowAncestor(of element: AXUIElement) -> AXUIElement? {
        var ancestor: AXUIElement? = element
        for _ in 0..<12 {
            guard let current = ancestor else { return nil }
            if string(current, kAXRoleAttribute) == kAXWindowRole as String { return current }
            ancestor = parent(current)
        }
        return nil
    }

    func bounds(_ element: AXUIElement) throws -> CGRect {
        var frame = try readFrame(of: element)
        guard frame.width > 0, frame.height > 0 else {
            throw CadenzaError.failure("native_queue_unavailable", "The native queue row is not visible.")
        }
        // Rows do not expose AXWindow, so the window is found among the row's ancestors.
        guard let window = windowAncestor(of: element) else {
            throw CadenzaError.failure("native_queue_unavailable", "The native queue row has no visible window.")
        }
        guard attribute(window, kAXMinimizedAttribute) as? Bool != true else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's window is minimized.")
        }
        if !isOnScreen(frame) {
            // A row outside the scroll area's clip reports its real position. Music scrolls it into view when asked.
            scrollIntoView(element)
            for _ in 0..<3 where !isOnScreen(frame) {
                usleep(80_000)
                guard let moved = try? readFrame(of: element) else { break }
                frame = moved
            }
        }
        guard isOnScreen(frame) else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "Scroll the requested Music row into view before moving or playing it.")
        }
        return frame
    }

    private func readFrame(of element: AXUIElement) throws -> CGRect {
        guard let position = attribute(element, kAXPositionAttribute),
            let size = attribute(element, kAXSizeAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else {
            throw CadenzaError.failure("native_queue_unavailable", "The native queue row is not visible.")
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        // AX's position and size attributes have been checked against AXValue's CF type.
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
        return CGRect(origin: point, size: dimensions)
    }

    private func isOnScreen(_ frame: CGRect) -> Bool {
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.contains { screen in
            let screenBounds = CGRect(
                x: screen.frame.minX, y: desktopTop - screen.frame.maxY, width: screen.frame.width,
                height: screen.frame.height)
            return screenBounds.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    /// Asks Music to scroll the element into view. Music ignores it for rows that are already visible.
    func scrollIntoView(_ element: AXUIElement) {
        AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
    }
}
