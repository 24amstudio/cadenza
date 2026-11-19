import AppKit
import ApplicationServices
import Foundation

/// Queue actions on a selected song row. Each action is tried through the row's More button, the Song menu, the row's AX
/// menu and the row's context menu in turn, and a strategy that cannot find, enable or press the item hands over to
/// the next. The whole action is repeated per `InputRoute`, so Music is only brought forward once every focus-neutral
/// attempt has failed. Music exposes the More button's menu to Accessibility while it is in the background, which is
/// why that strategy comes first; its Song menu reads as disabled unless Music is the active application.
extension MusicAccessibility {
    enum MenuOutcome { case pressed, disabled }

    private enum MenuStrategy: CaseIterable {
        case moreButton, songMenu, accessibilityMenu, contextMenu

        var name: String {
            switch self {
            case .moreButton: "More button"
            case .songMenu: "Song menu"
            case .accessibilityMenu: "accessibility menu"
            case .contextMenu: "context menu"
            }
        }
    }

    static let playNextTitles = ["play next"]
    static let addToQueueTitles = ["add to queue", "play last", "add to up next"]
    static let removeTitles = ["remove from queue", "remove from playing next", "remove from up next", "remove"]

    func append(_ song: Song, deadline: Int64, next: Bool = false) async throws {
        emptyQueueMark = nil
        try await escalating(deadline: deadline) { route, limit in
            try await self.append(song, next: next, route: route, deadline: limit)
        }
    }

    private func append(_ song: Song, next: Bool, route: InputRoute, deadline: Int64) async throws {
        let row = try await selectSong(song, deadline: min(deadline, monotonicMs() + 3_000), route: route)
        // Music enables a track's menu actions only once the row has focus.
        try await focus(row, route: route, deadline: deadline)
        let titles = next ? Self.playNextTitles : Self.addToQueueTitles
        do {
            if try await perform(titles, on: row, deadline: deadline, route: route) { return }
        } catch let error as CadenzaError where !next && error.code == "native_queue_unavailable" {
            // Music offers no Add to Queue until the queue has an item; the empty-queue check below decides.
        }
        // Music disables Add to Queue until the queue has an item. For an empty queue, Play Next is the same position.
        guard !next else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's Play Next is unavailable for this song.")
        }
        try await requireEmptyQueue(deadline: deadline)
        guard try await perform(Self.playNextTitles, on: row, deadline: deadline, route: route) else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's Add to Queue is unavailable for this song.")
        }
    }

    func remove(_ row: NativeQueueRow, deadline: Int64) async throws {
        emptyQueueMark = nil
        try await escalating(deadline: deadline) { route, limit in
            try await self.focus(row.element, route: route, deadline: limit)
            let removed = try await self.perform(
                Self.removeTitles, on: row.element, deadline: limit, route: route,
                strategies: [.moreButton, .accessibilityMenu, .contextMenu])
            guard removed else {
                throw CadenzaError.failure("native_queue_unavailable", "Music's Remove from Queue is unavailable.")
            }
        }
    }

    /// Gives the row keyboard focus: an AX focus write when only Accessibility is allowed, otherwise a click.
    private func focus(_ row: AXUIElement, route: InputRoute, deadline: Int64) async throws {
        guard route.sendsInput else {
            AXUIElementSetAttributeValue(row, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return
        }
        try await click(row, deadline: deadline, route: route)
    }

    /// True once an item is pressed, false when every strategy that found the item saw it disabled. Throws when no
    /// strategy found or pressed it.
    private func perform(
        _ titles: [String], on row: AXUIElement, deadline: Int64, route: InputRoute,
        strategies: [MenuStrategy] = MenuStrategy.allCases
    ) async throws -> Bool {
        var failures: [String] = []
        var sawDisabled = false
        for strategy in strategies where route.sendsInput || strategy != .contextMenu {
            try Task.checkCancellation()
            try requireDeadline(deadline)
            let started = monotonicMs()
            let attemptDeadline = min(deadline, started + 2_000)
            do {
                let outcome: MenuOutcome
                switch strategy {
                case .moreButton:
                    outcome = try await popupAction(
                        titles, row: row, deadline: attemptDeadline, opening: .moreButton, route: route)
                case .songMenu:
                    outcome = try await songMenuAction(titles, deadline: attemptDeadline)
                case .accessibilityMenu:
                    outcome = try await popupAction(
                        titles, row: row, deadline: attemptDeadline, opening: .accessibilityMenu, route: route)
                case .contextMenu:
                    outcome = try await popupAction(
                        titles, row: row, deadline: attemptDeadline, opening: .contextClick, route: route)
                }
                if outcome == .pressed { return true }
                // A disabled item is not final: the Song menu reads as disabled for a background Music.
                sawDisabled = true
                failures.append("\(strategy.name): the item is disabled.")
            } catch let error as CadenzaError where error.code == "native_queue_unavailable" {
                failures.append("\(strategy.name): \(error.localizedDescription)")
                logger?.log(
                    .warning, category: "accessibility", action: "menu.strategy-failed",
                    "Music's \(strategy.name) did not run \(titles[0]) through \(route.name)",
                    metadata: ["reason": error.localizedDescription, "ms": String(monotonicMs() - started)])
            }
        }
        if sawDisabled { return false }
        throw CadenzaError.failure(
            "native_queue_unavailable",
            "Music did not accept \(titles[0]) for this song. " + failures.joined(separator: " "))
    }

    private func isMenuChoice(_ element: AXUIElement, in titles: [String]) -> Bool {
        let title = key(string(element, kAXTitleAttribute)).replacingOccurrences(of: "\u{2026}", with: "")
        return titles.contains(title.trimmingCharacters(in: .whitespaces))
    }

    // The Song menu bar acts on the focused track, so the caller must select the row first.
    private func songMenuAction(_ titles: [String], deadline: Int64) async throws -> MenuOutcome {
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
            target = children(songMenu).flatMap { children($0) }.first { isMenuChoice($0, in: titles) }
            if target == nil { try await Task.sleep(for: .milliseconds(40)) }
        } while target == nil && monotonicMs() < deadline
        guard let target else {
            closeMenu(songMenu)
            throw CadenzaError.failure(
                "native_queue_unavailable", "The Song menu's \(titles[0]) action is unavailable.")
        }
        guard attribute(target, kAXEnabledAttribute) as? Bool == true else {
            closeMenu(songMenu)
            return .disabled
        }
        guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
            closeMenu(songMenu)
            throw CadenzaError.failure(
                "native_queue_unavailable", "Music did not accept the Song menu's \(titles[0]) action.")
        }
        return .pressed
    }

    private enum PopupOpening {
        /// AXPress on the row's More button. Music answers it with a menu that is a child of the button, whether or not
        /// Music is active, and reports the press itself as failed because the menu tracks inside it.
        case moreButton
        case accessibilityMenu
        case contextClick
    }

    /// Opens the row's popup menu and chooses the item. Music answers mouse events on a row where it refuses AX
    /// actions on the item, so the item is clicked where it is drawn when its press is refused.
    private func popupAction(
        _ titles: [String], row: AXUIElement, deadline: Int64, opening: PopupOpening, route: InputRoute
    ) async throws -> MenuOutcome {
        beginRead(deadline: deadline)
        scrollIntoView(row)
        let opener = opening == .moreButton ? try moreButton(in: row) : row
        // A popup left open by an earlier attempt would stall Music's scripting and hide this one's items.
        if popupMenu(near: opener) != nil { try await closePopup(near: opener, route: route) }
        beginRead(deadline: deadline)
        let restore = route == .system ? pointerToRestore(route: route) : nil
        let source = try inputSource()
        defer { restorePointer(restore, source: source) }
        switch opening {
        case .moreButton:
            pressWithoutWaiting(opener)
        case .accessibilityMenu:
            guard AXUIElementPerformAction(row, "AXShowMenu" as CFString) == .success else {
                throw CadenzaError.failure("native_queue_unavailable", "Music's row has no accessibility menu.")
            }
        case .contextClick:
            let frame = try bounds(row)
            // The pointer stays on the row while the popup is open, so the popup is not dismissed before its item is chosen.
            try postClick(
                at: CGPoint(x: frame.midX, y: frame.midY), button: .right, route: route, restoresPointer: false)
        }
        var popup: AXUIElement?
        repeat {
            beginRead(deadline: deadline)
            popup = popupMenu(near: opener)
            if popup == nil { try await Task.sleep(for: .milliseconds(40)) }
        } while popup == nil && monotonicMs() < deadline
        guard let popup else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's song menu did not open.")
        }
        beginRead(deadline: deadline + 300)
        let items = children(popup).filter { string($0, kAXRoleAttribute) == kAXMenuItemRole as String }
        guard let target = items.first(where: { isMenuChoice($0, in: titles) }) else {
            // The titles Music actually showed make a missing menu action diagnosable from the log alone.
            let shown = items.map { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }.prefix(12)
            logger?.log(
                .warning, category: "accessibility", action: "menu.missing", "No matching song menu action",
                metadata: ["wanted": titles.joined(separator: " | "), "shown": shown.joined(separator: " | ")])
            try await closePopup(near: opener, route: route)
            throw CadenzaError.failure(
                "native_queue_unavailable", "The required native queue menu action is unavailable.")
        }
        guard attribute(target, kAXEnabledAttribute) as? Bool != false else {
            try await closePopup(near: opener, route: route)
            return .disabled
        }
        logger?.log(
            .info, category: "accessibility", action: "menu.pressed", "Pressed \(string(target, kAXTitleAttribute))",
            metadata: ["route": route.name, "opened": "\(opening)"])
        if opening != .contextClick, AXUIElementPerformAction(target, kAXPressAction as CFString) == .success {
            return .pressed
        }
        guard route.sendsInput else {
            try await closePopup(near: opener, route: route)
            throw CadenzaError.failure("native_queue_unavailable", "Music refused the menu item's accessibility press.")
        }
        let targetFrame = try bounds(target)
        try postClick(
            at: CGPoint(x: targetFrame.midX, y: targetFrame.midY), button: .left, route: route, restoresPointer: false)
        return .pressed
    }

    /// Music does not answer the More button's press until its menu closes or about 1.5 s pass, so the press is made off
    /// the main actor while the menu is read and chosen from.
    private func pressWithoutWaiting(_ button: AXUIElement) {
        let target = SendableElement(element: button)
        DispatchQueue.global(qos: .userInitiated).async {
            AXUIElementPerformAction(target.element, kAXPressAction as CFString)
        }
    }

    /// Dismisses the popup and waits until Music has closed it, because a menu that is still closing ignores the next
    /// press on the More button.
    private func closePopup(near opener: AXUIElement, route: InputRoute) async throws {
        try dismissPopup(near: opener, route: route)
        let limit = monotonicMs() + 600
        repeat {
            beginRead(deadline: limit + 200)
            if popupMenu(near: opener) == nil { return }
            try await Task.sleep(for: .milliseconds(40))
        } while monotonicMs() < limit
    }

    /// The More button that Music draws at the end of a song row.
    private func moreButton(in row: AXUIElement) throws -> AXUIElement {
        let button = shallow(row, maxDepth: 5, maxNodes: 60) { node in
            string(node, kAXRoleAttribute) == kAXButtonRole as String
                && (string(node, kAXIdentifierAttribute) == "actionButton"
                    || key(string(node, kAXDescriptionAttribute)) == "more")
        }.first
        guard let button else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's row shows no More button.")
        }
        return button
    }

    func popupMenu(near element: AXUIElement) -> AXUIElement? {
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

    // A posted Escape key does not reliably close Music's menu bar menus, so the open menu is cancelled directly.
    func closeMenu(_ menuBarItem: AXUIElement) {
        for menu in children(menuBarItem) where string(menu, kAXRoleAttribute) == kAXMenuRole as String {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
    }

    private func requireEmptyQueue(deadline: Int64) async throws {
        if !queuePanelOpen() { try await requestQueuePanel() }
        // The list takes a moment to appear after the panel opens, so the read is retried within its own budget.
        let limit = min(deadline, monotonicMs() + 2_000)
        var queue: [NativeQueueRow]?
        repeat {
            queue = try? rows(deadline: min(limit, monotonicMs() + 800))
            if queue == nil { try await Task.sleep(for: .milliseconds(100)) }
        } while queue == nil && monotonicMs() < limit
        guard let queue, queue.isEmpty else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's Add to Queue is unavailable for this song.")
        }
    }
}

/// Carries an AXUIElement to the one background call that presses it. Accessibility elements are thread-safe handles.
private struct SendableElement: @unchecked Sendable {
    let element: AXUIElement
}
