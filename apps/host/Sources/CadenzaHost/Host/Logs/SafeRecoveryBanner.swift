import SwiftUI

/// Shown in Logs while Host is in safe recovery after repeated crashes. Automatic Music polling stays paused until the
/// user resumes it here.
struct SafeRecoveryBanner: View {
    let resume: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Safe recovery is on")
                    .font(.headline)
                Text(
                    "Cadenza Host crashed three times within thirty seconds, so automatic Music polling is paused. "
                        + "Review the entries below, then resume once Music responds normally."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Resume Music Polling", action: resume)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}
