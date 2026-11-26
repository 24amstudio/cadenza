import SwiftUI

/// Shown in Logs after Host ended from a fatal signal in its previous session. The full record is already in the logs,
/// and exporting the diagnostic logs includes it.
struct CrashReportBanner: View {
    let export: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cadenza Host ended unexpectedly last time")
                    .font(.headline)
                Text(
                    "The fatal signal, the time, the track that was playing, and a stack trace are in the diagnostic logs."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Export Diagnostic Logs…", action: export)
            Button("Dismiss", action: dismiss)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1))
        .accessibilityElement(children: .contain)
    }
}
