import SwiftUI

struct SettingsStoragePane: View {
    @Bindable var model: HostModel
    @State private var confirmingClear = false
    private let cacheLimits: [Int64] = [64, 128, 256, 512, 768, 1_024].map { Int64($0) * 1_048_576 }

    var body: some View {
        Form {
            RestartHostSection(model: model, settings: [.cache])
            Section {
                Picker("Maximum size", selection: model.committedBinding(\.cacheLimitBytes)) {
                    ForEach(cacheLimits, id: \.self) { value in
                        Text(ByteCountFormatter.string(fromByteCount: value, countStyle: .file)).tag(value)
                    }
                }
                if let stats = model.cacheStats {
                    LabeledContent(
                        "Used",
                        value: ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file)
                            + " in \(stats.entries) items")
                    ProgressView(value: min(stats.fractionUsed, 1))
                        .accessibilityLabel("Local cache usage")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading cache usage")
                }
                Button("Refresh") { model.refreshCacheStats() }
                Button(model.clearingCache ? "Clearing…" : "Clear Local Cache", role: .destructive) {
                    confirmingClear = true
                }
                .disabled(model.clearingCache)
            } header: {
                Text("Local cache")
            } footer: {
                Text(
                    "Changes to the maximum size apply after Host restarts. The least recently used items are removed first."
                )
            }

            Section {
                Picker(
                    "Keep logs for",
                    selection: Binding(get: { HostLogRetention.days }, set: { HostLogRetention.days = $0 })
                ) {
                    ForEach([7, 14, 30], id: \.self) { days in Text("\(days) days").tag(days) }
                }
            } header: {
                Text("System logs")
            } footer: {
                Text("Logs are stored apart from the media cache and do not count toward its size limit.")
            }
        }
        .formStyle(.grouped)
        .alert("Clear the local cache?", isPresented: $confirmingClear) {
            Button("Clear Cache", role: .destructive) { model.clearCache() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cached items are removed and fetched again when they are needed.")
        }
    }
}
