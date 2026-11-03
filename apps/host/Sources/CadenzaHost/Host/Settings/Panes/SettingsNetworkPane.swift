import SwiftUI

struct SettingsNetworkPane: View {
    @Bindable var model: HostModel

    var body: some View {
        Form {
            Section {
                TextField("Host name", text: $model.configuration.name)
                TextField("Port", value: $model.configuration.port, format: .number)
                TextField("Catalog storefront", text: $model.configuration.storefront)
                Picker("Address shown in pairing", selection: $model.configuration.advertisedAddress) {
                    Text("Automatic").tag("")
                    ForEach(LANAddresses.all(), id: \.self) { Text($0).tag($0) }
                }
            } footer: {
                Text("The storefront is a two-letter country code, such as id or us.")
            }
            Section {
                Toggle("Cadenza Web", isOn: $model.configuration.webEnabled)
            } footer: {
                Text(
                    "Lets a browser on this network control Cadenza Host through port \(model.configuration.webPort). "
                        + "Pairing codes then also open the web remote."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Network")
    }
}
