import SwiftUI

/// Google Cast output and the Cadenza TV page. Both send audio and lyrics to a TV or speaker, so they share one pane.
struct SettingsCastPane: View {
    @Bindable var model: HostModel
    @AppStorage("castPresentationMode") private var castMode: CastPresentationMode = .auto

    private var castDevices: [CastDiscovery.Device] { model.service?.publishedState.castDiscovery.devices ?? [] }

    var body: some View {
        Form {
            Section {
                Picker("Presentation", selection: $castMode) {
                    ForEach(CastPresentationMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                ForEach(castDevices, id: \.name) { device in
                    LabeledContent(device.name, value: device.display.label)
                }
                if let status = model.snapshot?.cast?.transmit?.status {
                    Text(status.text)
                        .foregroundStyle(status.mismatch ? Color.orange : Color.secondary)
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
        }
        .formStyle(.grouped)
    }
}
