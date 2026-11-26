import Foundation

/// How much optional work Host may run. Each tier only sheds background and optional work. Transport controls, queue
/// commands, and Remote connections are never gated by a tier.
enum HostOperatingBudget: String, Sendable, Codable, Comparable {
    case unrestricted, balanced, constrained, survival

    private var rank: Int {
        switch self {
        case .unrestricted: 0
        case .balanced: 1
        case .constrained: 2
        case .survival: 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    /// New Sing separation starts only below the constrained tier. A session already running is not interrupted here.
    var allowsSingInference: Bool { self < .constrained }
}

/// A thermal level, mirrored from `ProcessInfo` so the policy stays pure and testable.
enum HostThermalLevel: Sendable {
    case nominal, fair, serious, critical
}

struct HostPowerState: Equatable, Sendable {
    var thermal: HostThermalLevel
    var lowPowerMode: Bool
}

enum HostBudgetPolicy {
    /// Thermal pressure sets the tier. Low Power Mode lifts an unrestricted tier to balanced, and never lowers a tier.
    static func budget(for state: HostPowerState) -> HostOperatingBudget {
        let thermal: HostOperatingBudget
        switch state.thermal {
        case .nominal: thermal = .unrestricted
        case .fair: thermal = .balanced
        case .serious: thermal = .constrained
        case .critical: thermal = .survival
        }
        return state.lowPowerMode ? max(thermal, .balanced) : thermal
    }
}
