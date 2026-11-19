import SwiftUI

struct LogStatusBar: View {
    let shown: Int
    let held: Int
    let isPaused: Bool
    let totalStored: Int
    let retentionDays: Int

    var body: some View {
        HStack(spacing: 12) {
            if isPaused {
                Label(
                    held == 0 ? "Paused" : "Paused · \(held.formatted()) new",
                    systemImage: "pause.circle.fill"
                )
                .foregroundStyle(.orange)
            }
            Text("\(shown.formatted()) shown")
            Spacer(minLength: 8)
            Text("\(totalStored.formatted()) stored · kept \(retentionDays) days")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
