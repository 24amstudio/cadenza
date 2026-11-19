import AppKit
import ApplicationServices
import Foundation

/// Synthetic pointer and keyboard input for Music, which answers mouse and key events where its menus refuse AX actions.
/// `.process` events reach Music without activating it; `.system` events go to whatever is frontmost.
extension MusicAccessibility {
    static let returnKey: CGKeyCode = 36

    /// The row is scrolled into view first, because an AX frame outside the visible clip cannot be clicked.
    func click(_ element: AXUIElement, deadline: Int64, count: Int = 1, route: InputRoute) async throws {
        try requireInput(route)
        beginRead(deadline: min(deadline, monotonicMs() + 800))
        scrollIntoView(element)
        let frame = try bounds(element)
        try requireDeadline(deadline)
        try postClicks(at: CGPoint(x: frame.midX, y: frame.midY), count: count, route: route)
    }

    func deliver(_ event: CGEvent?, route: InputRoute) throws {
        switch route {
        case .accessibility:
            try requireInput(route)
        case .process:
            guard let currentPid else {
                throw CadenzaError.failure("music_unavailable", "Music is not running. Open Music, then try again.")
            }
            event?.postToPid(currentPid)
        case .system:
            event?.post(tap: .cghidEventTap)
        }
    }

    func inputSource() throws -> CGEventSource {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw CadenzaError.failure("native_queue_unavailable", "The native Music input source is unavailable.")
        }
        return source
    }

    /// Events sent to a process do not move the pointer, so only system events need it put back.
    func pointerToRestore(route: InputRoute) -> CGPoint? {
        route == .system ? CGEvent(source: nil)?.location : nil
    }

    func postClicks(at point: CGPoint, count: Int, route: InputRoute) throws {
        try requireInput(route)
        let source = try inputSource()
        let previous = pointerToRestore(route: route)
        defer { restorePointer(previous, source: source) }
        for clickState in 1...max(1, count) {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(
                    mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
                try deliver(event, route: route)
            }
        }
    }

    func postClick(at point: CGPoint, button: CGMouseButton, route: InputRoute, restoresPointer: Bool = true) throws {
        try requireInput(route)
        let source = try inputSource()
        let previous = pointerToRestore(route: route)
        defer { if restoresPointer { restorePointer(previous, source: source) } }
        let types: [CGEventType] =
            button == .right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            try deliver(
                CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button),
                route: route)
        }
    }

    func pressKey(_ code: CGKeyCode, route: InputRoute) throws {
        try requireInput(route)
        let source = try inputSource()
        for keyDown in [true, false] {
            try deliver(CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown), route: route)
        }
    }

    func restorePointer(_ point: CGPoint?, source: CGEventSource) {
        guard let point else { return }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(
            tap: .cghidEventTap)
    }

    /// A key press goes to the focused control. While Music's search field has focus, Return would submit the search
    /// again instead of playing the selected row.
    func textFieldHasFocus() -> Bool {
        guard let application, let value = attribute(application, kAXFocusedUIElementAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }
        // The focused element has been checked against the AXUIElement Core Foundation type.
        let focused: AXUIElement = value as! AXUIElement
        let role = string(focused, kAXRoleAttribute)
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
            || string(focused, kAXSubroleAttribute) == kAXSearchFieldSubrole
    }

    // Escape leaves Music's popup menus open, and an open popup stalls Music's scripting. AX cancel is tried first; if
    // the popup stays, a click outside it dismisses it, on the blank toolbar of the window that owns the popup.
    func dismissPopup(near element: AXUIElement, route: InputRoute) throws {
        beginRead(deadline: monotonicMs() + 400)
        if let popup = popupMenu(near: element) { AXUIElementPerformAction(popup, kAXCancelAction as CFString) }
        guard route.sendsInput, popupMenu(near: element) != nil, let window = windowAncestor(of: element) else {
            return
        }
        let frame = try bounds(window)
        try postClick(at: CGPoint(x: frame.midX, y: frame.minY + 12), button: .left, route: route)
    }
}
