import Foundation
import Observation

/// Keeps `budget` current from thermal and Low Power Mode change notifications. It reads the state once when started,
/// then only when the system reports a change. Nothing polls.
@Observable
@MainActor
final class HostEnergyMonitor {
    private(set) var budget: HostOperatingBudget
    @ObservationIgnored var onChange: ((HostOperatingBudget) -> Void)?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    init() {
        budget = HostBudgetPolicy.budget(for: Self.currentState())
    }

    func start() {
        stop()
        refresh()
        let center = NotificationCenter.default
        tokens = [
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.refresh() }
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.refresh() }
            },
        ]
    }

    func stop() {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        tokens = []
    }

    private func refresh() {
        let next = HostBudgetPolicy.budget(for: Self.currentState())
        guard next != budget else { return }
        budget = next
        onChange?(next)
    }

    private static func currentState() -> HostPowerState {
        let info = ProcessInfo.processInfo
        return HostPowerState(
            thermal: HostThermalLevel(info.thermalState), lowPowerMode: info.isLowPowerModeEnabled)
    }
}

extension HostThermalLevel {
    /// An unknown future level is treated as critical, so an unrecognised system state sheds the most work.
    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}
