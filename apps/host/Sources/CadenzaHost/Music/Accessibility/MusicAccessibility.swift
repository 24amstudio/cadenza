import AppKit
import ApplicationServices
import Foundation

/// Drives Music's own UI through the Accessibility API. Every wait is a bounded poll that yields the main actor
/// between passes; the extensions in this directory own one responsibility each.
@MainActor
final class MusicAccessibility {
    let maximumElements = 6_000
    static let messagingTimeout: Float = 0.35
    var application: AXUIElement?
    var cachedQueueTable: AXUIElement?
    // An empty queue is the History list directly above AutoPlay. Its row count and AutoPlay row confirm it cheaply.
    var emptyQueueMark: (table: AXUIElement, rows: Int, autoPlay: Int, takenAt: Int64)?
    var cachedTrackTable: AXUIElement?
    var currentPid: pid_t?
    private var lastMusicPid: pid_t?
    var readDeadline: Int64 = 0
    var lastPermissionPrompt: Int64 = 0
    var logger: HostLogger?
    /// Escalation to Music's foreground is decided here and nowhere else.
    lazy var activation = ActivationFallback.live { [weak self] action, message in
        self?.logger?.log(.info, category: "accessibility", action: action, message)
    }

    func beginRead(deadline: Int64? = nil) {
        // Callers pass the deadline of the whole operation. Without one, a read gets a short local budget.
        readDeadline = deadline ?? monotonicMs() + 200
    }

    func finishRead() throws {
        guard monotonicMs() < readDeadline else {
            throw CadenzaError.failure(
                "native_queue_unavailable",
                "Music's accessibility response exceeded its time budget. Retry after Music finishes loading.")
        }
    }

    func requireReadTime() throws {
        guard monotonicMs() < readDeadline else {
            throw CadenzaError.failure("native_queue_unavailable", "Music's queue is still loading. Try again.")
        }
    }

    func requireDeadline(_ deadline: Int64) throws {
        guard monotonicMs() < deadline else {
            throw CadenzaError.failure("expired", "The request expired before the native queue action.")
        }
    }

    var permitted: Bool { AXIsProcessTrusted() }

    /// Music's process identifier, or nil when it is not running. Unlike `root`, this never waits for a launch.
    var musicProcessId: pid_t? {
        let pid = MusicProcess.resolve(
            lookup: MusicProcess.lookup(), lastKnown: lastMusicPid, isRunning: MusicProcess.isRunning)
        lastMusicPid = pid
        return pid
    }

    /// Fails with music_permission before a command starts Music work that Accessibility cannot finish.
    func requireAccess() throws {
        _ = try root()
    }

    func requestPermission() {
        // Literal value of kAXTrustedCheckOptionPrompt, which Swift 6 rejects as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func root() throws -> AXUIElement {
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
        guard !ScreenLock.isLocked else {
            throw CadenzaError.failure("music_locked", "The Mac is locked. Unlock it to use Music's interface.")
        }
        guard let pid = runningMusic() else {
            throw CadenzaError.failure("music_unavailable", "Music is not running. Open Music, then try again.")
        }
        if currentPid != pid {
            cachedQueueTable = nil
            cachedTrackTable = nil
            emptyQueueMark = nil
        }
        currentPid = pid
        let element = AXUIElementCreateApplication(pid)
        // Music can take a few hundred milliseconds to answer while it loads. Each read is bounded by `readDeadline`.
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        application = element
        return element
    }

    // The lookup can omit a running Music for about a second after Music changes state, so a miss is retried.
    private func runningMusic() -> pid_t? {
        let deadline = monotonicMs() + 1_000
        repeat {
            if let pid = musicProcessId { return pid }
            usleep(50_000)
        } while monotonicMs() < deadline
        return nil
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
