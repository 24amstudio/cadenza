import AppKit
import SwiftUI

struct SettingsGeneralPane: View {
    @Bindable var model: HostModel
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage(HostPresentation.menuBarOnlyKey) private var menuBarOnly = false
    @AppStorage("castPresentationMode") private var castMode: CastPresentationMode = .auto

    private var castDevices: [CastDiscovery.Device] { model.service?.publishedState.castDiscovery.devices ?? [] }

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
                Toggle("Menu bar only (hide Dock icon)", isOn: $menuBarOnly)
                    .onChange(of: menuBarOnly) { HostPresentation.apply(menuBarOnly: menuBarOnly) }
            } footer: {
                Text(
                    "When the icon is hidden, open Cadenza Host from Spotlight to return to Settings. "
                        + "Menu bar only keeps Cadenza Host out of the Dock."
                )
            }
            Section {
                Picker("Presentation", selection: $castMode) {
                    ForEach(CastPresentationMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                ForEach(castDevices, id: \.name) { device in
                    LabeledContent(device.name, value: device.display.label)
                }
            } header: {
                Text("Google Cast")
            } footer: {
                Text(
                    "Full Cadenza Suite needs a Cast device with a screen. Speakers always receive audio only. "
                        + "Devices are found while Cadenza Host runs."
                )
            }
            StageSettingsSection(model: model)
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
