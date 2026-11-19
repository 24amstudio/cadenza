import AppKit
import SwiftUI

/// The main window after setup: one sidebar of Host screens and settings panes beside the selected pane.
struct HostWorkspace: View {
    @Bindable var model: HostModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSection) {
                Section("Cadenza Host") {
                    sidebarRow(.nowPlaying)
                    sidebarRow(.remotes)
                }
                Section("Settings") {
                    ForEach(HostSection.settings) { section in
                        sidebarRow(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail
                .navigationTitle(model.selectedSection.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HostStatusItem(running: model.running, starting: model.starting)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                        } label: {
                            Label("Open Music", systemImage: "music.note")
                        }
                        .help("Open Music")
                    }
                }
        }
    }

    private func sidebarRow(_ section: HostSection) -> some View {
        Label(section.title, systemImage: section.symbol).tag(section)
    }

    @ViewBuilder private var detail: some View {
        switch model.selectedSection {
        case .nowPlaying: NowPlayingScreen(model: model)
        case .remotes: RemotesScreen(model: model)
        case .general: SettingsGeneralPane(model: model)
        case .network: SettingsNetworkPane(model: model)
        case .music: SettingsMusicPane(model: model)
        case .lyrics: SettingsLyricsPane(model: model)
        case .storage: SettingsStoragePane(model: model)
        case .updates: SettingsUpdatesPane(model: model)
        }
    }
}
