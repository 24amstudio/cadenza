import SwiftUI

/// Download, progress, and removal for the optional Sing model. Nothing downloads until the user presses Download,
/// except replacing a model that this build no longer expects.
struct SingModelSection: View {
    let manager: SingModelManager
    let showError: (String, String) -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        Section {
            switch manager.state {
            case .notInstalled:
                LabeledContent("Download", value: sizeText(manager.spec?.sizeBytes))
                Button("Download") { manager.download() }
                    .disabled(manager.spec?.url == nil)
            case .downloading(let progress, let isAutoUpdate):
                ProgressView(value: progress) {
                    Text(isAutoUpdate ? "Updating Sing Model…" : "Downloading Sing Model…")
                }
                Button("Cancel") { manager.cancel() }
            case .ready(let version, let sizeBytes):
                LabeledContent("Status") {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                }
                LabeledContent("Version", value: "\(version) · \(sizeText(sizeBytes))")
                Button("Remove", role: .destructive) { confirmingRemoval = true }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Retry") { manager.download() }
                    .disabled(manager.spec?.url == nil)
            }
        } header: {
            Text("Sing Model")
        } footer: {
            Text("Vocal separation uses a model that Cadenza Host downloads from its release and verifies before use.")
        }
        .alert("Remove the Sing model?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) {
                do {
                    try manager.remove()
                } catch {
                    showError("Sing model could not be removed", error.localizedDescription)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sing stays unavailable until you download the model again.")
        }
    }

    private func sizeText(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unavailable in this build" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
