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

    /// macOS declines a background app's own activation requests (`NSRunningApplication.activate` and an AX frontmost
    /// write both fail while another app is in front), but asking Launch Services to open the application by its
    /// bundle path is honored. The request is fire-and-forget: the caller polls the frontmost application for the outcome.
    func activate(_ application: FrontApplication) {
        let running = NSRunningApplication(processIdentifier: application.processId)
        guard let path = running?.bundleURL?.path else {
            running?.activate()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", path]
        guard (try? process.run()) != nil else { return }
        DispatchQueue.global(qos: .utility).async { process.waitUntilExit() }
    }

    private static func describe(_ application: NSRunningApplication) -> FrontApplication {
        FrontApplication(processId: application.processIdentifier, bundleId: application.bundleIdentifier)
    }
}
