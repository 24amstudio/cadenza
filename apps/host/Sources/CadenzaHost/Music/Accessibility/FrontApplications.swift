import AppKit
import ApplicationServices
import Foundation

/// An application as the window server reports it.
struct FrontApplication: Equatable, Sendable {
    let processId: pid_t
    let bundleId: String?
}

/// What `ActivationFallback` needs from the system: who is frontmost, and a request to bring an application forward.
@MainActor
protocol FrontApplications {
    var frontmost: FrontApplication? { get }
    func running(bundleId: String) -> FrontApplication?
    func activate(_ application: FrontApplication)
}

@MainActor
struct WorkspaceApplications: FrontApplications {
    var frontmost: FrontApplication? {
        NSWorkspace.shared.frontmostApplication.map(Self.describe)
    }

    func running(bundleId: String) -> FrontApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first.map(Self.describe)
    }

    func activate(_ application: FrontApplication) {
        NSRunningApplication(processIdentifier: application.processId)?.activate()
        // Cooperative activation can be declined while Host is in the background, so Accessibility asks the process
        // to come forward as well.
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(application.processId), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func describe(_ application: NSRunningApplication) -> FrontApplication {
        FrontApplication(processId: application.processIdentifier, bundleId: application.bundleIdentifier)
    }
}
