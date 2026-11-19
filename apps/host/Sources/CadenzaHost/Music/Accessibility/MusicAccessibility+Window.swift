import ApplicationServices
import Foundation

/// Some applications expose no Accessibility window until one is visible, so a backgrounded Music can look empty.
extension MusicAccessibility {
    /// Fails with `music_window_unavailable` when Music exposes no window, instead of waiting on an empty tree.
    func requireWindow() throws {
        beginRead(deadline: monotonicMs() + 800)
        let application = try root()
        let windows: [AXUIElement]
        switch read(application, kAXChildrenAttribute) {
        case .value(let value): windows = value as? [AXUIElement] ?? []
        case .absent: windows = []
        case .timedOut:
            // A slow answer says nothing about the window, so the caller's poll tries again.
            throw CadenzaError.failure(
                "native_queue_unavailable", "Music is slow to answer Accessibility requests. Try again.")
        }
        guard windows.contains(where: { string($0, kAXRoleAttribute) == kAXWindowRole as String }) else {
            throw CadenzaError.failure(
                "music_window_unavailable", "Music exposes no window to Accessibility. Open a Music window.")
        }
    }

    /// Looks for Music's window without activating it, and only brings Music forward when none is exposed.
    func ensureWindow(deadline: Int64) async throws {
        try await escalating(deadline: deadline, routes: [.accessibility, .system]) { route, limit in
            // A slow answer is retried for the attempt's time. A window Music does not expose ends the quiet route at
            // once, so Music is brought forward, and is retried in the activating route.
            while true {
                do { return try self.requireWindow() } catch let error as CadenzaError
                    where error.code == "native_queue_unavailable"
                    || (route == .system && error.code == "music_window_unavailable")
                {
                    if monotonicMs() >= limit { throw error }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }
}
