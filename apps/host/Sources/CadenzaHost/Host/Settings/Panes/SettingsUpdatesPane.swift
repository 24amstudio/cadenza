import SwiftUI

struct SettingsUpdatesPane: View {
    @Bindable var model: HostModel
    @State private var changelog: String?
    @State private var comparingChanges = false
    @State private var confirmingInstall = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: HostBuild.version)
                LabeledContent("Build") {
                    Text(HostBuild.identity)
                        .textSelection(.enabled)
                }
            }

            Section {
                Toggle("Automatically check for updates", isOn: model.committedBinding(\.automaticUpdates))
                    .disabled(!HostBuild.updatesEnabled)
                    .onChange(of: model.configuration.automaticUpdates) { _, _ in model.scheduleUpdates() }
                updateStatusLine
                Button("Check for Updates") { model.checkUpdates() }
                    .disabled(model.updateBusy || !HostBuild.updatesEnabled)
                if model.stagedVersion != nil {
                    Button("Install Update") { confirmingInstall = true }
                        .disabled(model.updateBusy)
                }
            } footer: {
                Text(
                    HostBuild.updatesEnabled
                        ? "Cadenza Host checks once a day and installs verified updates. Your database and pairings are kept."
                        : "Automatic updates are turned off in this build."
                )
            }

            Section("What's New") {
                Button("What's New in This Build") { changelog = HostChangelog.bundled() }
                Button(comparingChanges ? "Comparing…" : "Compare With Latest Release", action: compareChanges)
                    .disabled(comparingChanges)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { changelog != nil }, set: { if !$0 { changelog = nil } })) {
            ChangelogSheet(text: changelog ?? "") { changelog = nil }
        }
        .alert(
            "Install Cadenza Host \(model.stagedVersion ?? "update")?",
            isPresented: $confirmingInstall
        ) {
            Button("Install and Restart") { model.installUpdate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cadenza Host restarts to finish the update. Your database and pairings are kept.")
        }
    }

    @ViewBuilder private var updateStatusLine: some View {
        if model.updateBusy {
            VStack(alignment: .leading, spacing: 6) {
                Text("Checking for updates…")
                ProgressView(value: model.updateProgress)
            }
            .foregroundStyle(.secondary)
        } else if let version = model.stagedVersion {
            Label("Version \(version) is ready to install.", systemImage: "arrow.down.circle.fill")
        } else if let status = model.updateStatus {
            Text(status)
                .foregroundStyle(.secondary)
        }
    }

    private func compareChanges() {
        comparingChanges = true
        Task { @MainActor in
            defer { comparingChanges = false }
            do {
                changelog = try await HostChangelog.compare(configuration: model.configuration.updates)
            } catch {
                model.showError("Changes could not be compared", error.localizedDescription)
            }
        }
    }
}
