import SwiftUI

enum PermissionState: Equatable {
    case notChecked, checking, granted, needed
}

/// One macOS permission with its current state and the single action that moves it forward.
struct PermissionStatusRow: View {
    let title: String
    let explanation: String
    let state: PermissionState
    let actionTitle: String?
    let actionDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                statusLabel
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .disabled(actionDisabled)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusLabel: some View {
        switch state {
        case .notChecked:
            Label("Not checked", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
            .foregroundStyle(.secondary)
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needed:
            Label("Needs permission", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
