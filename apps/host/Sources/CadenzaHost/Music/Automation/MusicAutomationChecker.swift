import AppKit
import Foundation
import Observation

/// Tracks whether macOS lets Cadenza Host send Apple events to Music. Passive probes never prompt, so launch, focus and
/// Music starting can refresh the status silently. Only an explicit Check Automation action may show macOS's prompt.
@MainActor
@Observable
final class MusicAutomationChecker {
    nonisolated static let musicBundleIdentifier = "com.apple.Music"
    static let previouslyGrantedKey = "cadenza.musicAutomationPreviouslyGranted"

    private static let notPermitted: OSStatus = -1743
    private static let consentRequired: OSStatus = -1744

    private(set) var state: PermissionState = .notChecked
    private let defaults: UserDefaults
    private let probe: @Sendable (_ promptUser: Bool) -> OSStatus
    private var observers: [NSObjectProtocol] = []

    init(
        defaults: UserDefaults = .standard,
        probe: @escaping @Sendable (_ promptUser: Bool) -> OSStatus = MusicAutomationChecker.systemProbe
    ) {
        self.defaults = defaults
        self.probe = probe
        if defaults.bool(forKey: Self.previouslyGrantedKey) { state = .granted }
    }

    /// Refreshes at launch, when Cadenza becomes active, and when Music starts. Each refresh is passive.
    func startObserving() {
        guard observers.isEmpty else { return }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.refresh(promptUser: false) }
            })
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let launched = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier
                guard launched == Self.musicBundleIdentifier else { return }
                Task { @MainActor in await self?.refresh(promptUser: false) }
            })
        Task { @MainActor in await refresh(promptUser: false) }
    }

    /// Probes Music and returns the resulting state. Pass `promptUser: true` only for an explicit user action.
    @discardableResult
    func refresh(promptUser: Bool) async -> PermissionState {
        if promptUser { state = .checking }
        let probe = self.probe
        let status = await Task.detached(priority: .utility) { probe(promptUser) }.value
        apply(status)
        return state
    }

    /// A Music command that succeeds proves the grant, so the state needs no separate probe.
    func markGranted() {
        defaults.set(true, forKey: Self.previouslyGrantedKey)
        state = .granted
    }

    func apply(_ status: OSStatus) {
        switch status {
        case 0:
            markGranted()
        case Self.notPermitted, Self.consentRequired:
            defaults.set(false, forKey: Self.previouslyGrantedKey)
            state = .needed
        default:
            // Music being closed (procNotFound) or any other probe error says nothing new about the grant.
            if defaults.bool(forKey: Self.previouslyGrantedKey) {
                state = .granted
            } else if state == .checking {
                state = .notChecked
            }
        }
    }

    nonisolated static func systemProbe(promptUser: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: musicBundleIdentifier)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, promptUser)
    }
}
