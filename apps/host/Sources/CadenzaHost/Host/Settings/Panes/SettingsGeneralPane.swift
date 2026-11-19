import AppKit
import SwiftUI

struct SettingsGeneralPane: View {
    @Bindable var model: HostModel
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            RestartHostSection(model: model, settings: [.name])
            Section {
                ValidatedSettingField(
                    title: "Host name",
                    value: model.configuration.name,
                    format: { $0 },
                    parse: SettingValue.name,
                    invalidMessage: "Use a shorter name.",
                    commit: { name in
                        model.configuration.name = name
                        model.persistConfiguration()
                    })
            } footer: {
                Text("Remotes show this name when they pair with this Mac.")
            }
            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            } footer: {
                Text("When the icon is hidden, open Cadenza Host from Spotlight to return to Settings.")
            }
            Section("Setup") {
                Button("Run Setup Again") { model.showingSetup = true }
            }
            Section {
                Button("Quit Cadenza Host") {
                    model.service?.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
    }
}
