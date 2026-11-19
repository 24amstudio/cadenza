import SwiftUI

/// The toolbar's Host state. Each state has its own symbol and text, so color is never the only signal.
struct HostStatusItem: View {
    let running: Bool
    let starting: Bool

    var body: some View {
        if running {
            Label("Running", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if starting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Starting…")
            }
            .accessibilityElement(children: .combine)
        } else {
            Label("Stopped", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        }
    }
}
