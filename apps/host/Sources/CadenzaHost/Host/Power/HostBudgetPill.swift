import SwiftUI

/// A compact status for the Host's thermal and power budget. It appears only when the Host is shedding optional work.
struct HostBudgetPill: View {
    let budget: HostOperatingBudget

    var body: some View {
        Label(budget.title, systemImage: "thermometer.medium")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.18), in: Capsule())
            .accessibilityLabel("Power budget: \(budget.title)")
    }
}

extension HostOperatingBudget {
    var title: String {
        switch self {
        case .unrestricted: "Full power"
        case .balanced: "Balanced"
        case .constrained: "Constrained"
        case .survival: "Survival"
        }
    }
}
