import AppKit

@MainActor
final class HostApplicationDelegate: NSObject, NSApplicationDelegate {
    var reopen: (() -> Void)?
    var terminate: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopen?()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { terminate?() }
}
