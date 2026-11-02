import AppKit
import SwiftUI

struct SettingsGeneralPane: View {
    @Bindable var model: HostModel
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var changelog: String?
    @State private var comparingChanges = false

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: HostBuild.version + " · " + HostBuild.profile)
                LabeledContent("Build") {
                    Text(HostBuild.identity).textSelection(.enabled)
                }
                Button("Changes in this build") { changelog = HostChangelog.bundled() }
                Button(comparingChanges ? "Comparing…" : "Compare published changes") {
                    comparingChanges = true
                    Task { @MainActor in
                        defer { comparingChanges = false }
                        do {
                            changelog = try await HostChangelog.compare(configuration: model.configuration.updates)
                        } catch { model.showError("Changes could not be compared", error.localizedDescription) }
                    }
                }
                .disabled(comparingChanges)
            }
            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            } footer: {
                Text("When the icon is hidden, open Cadenza Host from Spotlight to return to Settings.")
            }
            Section("Setup") {
                Button("Run setup again") { model.showingSetup = true }
            }
            Section {
                Button("Quit Cadenza Host") {
                    model.service?.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .sheet(isPresented: Binding(get: { changelog != nil }, set: { if !$0 { changelog = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Changelog").font(.title.bold())
                ScrollView {
                    Text(changelog ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Close") { changelog = nil }.keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .frame(width: 560, height: 420)
        }
    }
}
