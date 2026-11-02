import SwiftUI

/// Settings lists its categories the way macOS System Settings does. Choosing one opens its pane.
struct HostSettings: View {
    @Bindable var model: HostModel

    var body: some View {
        NavigationStack {
            List(SettingsPane.allCases) { pane in
                NavigationLink(value: pane) {
                    Label(pane.title, systemImage: pane.symbol)
                }
            }
            .listStyle(.inset)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsPane.self) { pane in
                content(for: pane)
            }
            .toolbar {
                ToolbarItem {
                    Button("Save settings", action: model.save).disabled(model.saving)
                }
            }
        }
    }

    @ViewBuilder
    private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: SettingsGeneralPane(model: model)
        case .network: SettingsNetworkPane(model: model)
        case .transport: SettingsTransportPane(model: model)
        case .music: SettingsMusicPane(model: model)
        case .recommendations: SettingsRecommendationsPane(model: model)
        case .lyrics: SettingsLyricsPane(model: model)
        case .storage: SettingsStoragePane(model: model)
        case .updates: SettingsUpdatesPane(model: model)
        }
    }
}
