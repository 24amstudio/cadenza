import Foundation
import IOKit.pwr_mgt

/// Holds an idle-system-sleep assertion while Music plays or an authenticated Remote is connected, so a sleeping Mac
/// cannot drop a control session. Once both stop, the assertion is released after `idleTimeout`. It prevents idle
/// system sleep only, not display sleep.
@MainActor
final class SleepAssertion {
    static let reason = "Cadenza Host keeps the Mac awake during playback and Remote control"

    private let idleTimeout: Duration
    private var assertionID: IOPMAssertionID = 0
    private var release: Task<Void, Never>?
    private(set) var isHolding = false

    init(idleTimeout: Duration = .seconds(600)) {
        self.idleTimeout = idleTimeout
    }

    /// Call whenever playback or the authenticated Remote set changes. It holds at once while active, and it schedules
    /// a single release when activity stops. No work runs per progress sample.
    func update(active: Bool) {
        if active {
            release?.cancel()
            release = nil
            acquire()
        } else if isHolding, release == nil {
            let timeout = idleTimeout
            release = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.releaseNow()
            }
        }
    }

    /// Releases the assertion now. Host stops call this so a quit Host does not keep the Mac awake.
    func releaseNow() {
        release?.cancel()
        release = nil
        guard isHolding else { return }
        IOPMAssertionRelease(assertionID)
        isHolding = false
    }

    private func acquire() {
        guard !isHolding else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.reason as CFString,
            &assertionID)
        isHolding = result == kIOReturnSuccess
    }
}
