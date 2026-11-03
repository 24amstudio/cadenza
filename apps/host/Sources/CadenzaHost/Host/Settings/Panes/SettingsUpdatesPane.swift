import SwiftUI

struct SettingsUpdatesPane: View {
    @Bindable var model: HostModel

    var body: some View {
        Form {
            Section {
                TextField("Repository, owner/name", text: $model.configuration.updates.repository)
                TextField("Public P-256 key, SPKI base64", text: $model.configuration.updates.publicKeySpkiBase64)
                Toggle("Check and install updates automatically", isOn: $model.configuration.automaticUpdates)
                    .disabled(!HostBuild.updatesEnabled)
            } header: {
                Text("GitHub releases")
            } footer: {
                if HostBuild.updatesEnabled {
                    Text("Save settings to apply the repository and key. Updates keep your database and pairings.")
                } else {
                    Text("Automatic updates are disabled in this build.")
                }
            }

            Section {
                Button(
                    model.updateBusy
                        ? "Checking…"
                        : (model.stagedVersion == nil ? "Check and install updates" : "Install update")
                ) {
                    if model.stagedVersion == nil { model.checkUpdates() } else { model.installUpdate() }
                }
                .disabled(model.updateBusy || !HostBuild.updatesEnabled)
                if model.updateBusy { ProgressView(value: model.updateProgress) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Updates")
    }
}
