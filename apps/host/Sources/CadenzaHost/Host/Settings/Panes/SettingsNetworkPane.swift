import SwiftUI

struct SettingsNetworkPane: View {
    @Bindable var model: HostModel

    private var webBundled: Bool { HostService.bundledWebRoot != nil }

    var body: some View {
        Form {
            RestartHostSection(model: model, settings: [.port, .advertisedAddress, .web])
            Section {
                ValidatedSettingField(
                    title: "Port",
                    value: model.configuration.port,
                    format: { String($0) },
                    parse: SettingValue.port,
                    invalidMessage: "Use a port from 1024 to 65535.",
                    commit: { port in
                        model.configuration.port = port
                        model.persistConfiguration()
                    })
                Picker("Address shown to Remotes (optional)", selection: model.committedBinding(\.advertisedAddress)) {
                    Text("Automatic").tag("")
                    ForEach(LANAddresses.all(), id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text(
                    "Remotes reach this Mac on this port. Choose an address only if Automatic doesn't work on your network."
                )
            }
            Section {
                Toggle("Cadenza Web", isOn: model.committedBinding(\.webEnabled))
            } footer: {
                Text(
                    "Cadenza Web is a browser remote. It lets a browser on this network control Cadenza Host through port "
                        + "\(model.configuration.webPort)."
                        + (webBundled ? " Pairing codes also open it." : "")
                )
                if !webBundled {
                    Text(
                        "This build does not include the Cadenza Web page. The page hosted on GitHub Pages can still connect "
                            + "through this port."
                    )
                }
            }
            ConnectionPreferenceSections(model: model)
        }
        .formStyle(.grouped)
        .onChange(of: model.hostTransportPolicy) { _, _ in model.saveTransportPolicy() }
        .onChange(of: model.remoteTransportPreferences) { _, _ in model.saveTransportPolicy() }
        .onChange(of: model.remoteTransportManualPaths) { _, _ in model.saveTransportPolicy() }
    }
}
