import SwiftUI

struct RemotesScreen: View {
    @Bindable var model: HostModel
    @State private var remoteToUnpair: PairedRemote?

    var body: some View {
        Form {
            Section {
                Button("Pair a Remote…", action: model.pair)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.running)
            } footer: {
                Text(
                    model.running
                        ? "Open Cadenza Remote on your device and scan the code that appears."
                        : "Start Host before pairing a Remote."
                )
            }

            Section("Paired Remotes") {
                if model.remotes.isEmpty {
                    ContentUnavailableView(
                        "No Remotes paired",
                        systemImage: "ipad.and.iphone",
                        description: Text("Pair a Remote to control Music from another device.")
                    )
                } else {
                    ForEach(model.remotes) { remote in
                        HStack(alignment: .top) {
                            RemoteStatusRow(remote: remote)
                            Spacer()
                            if !remote.revoked {
                                Button("Unpair", role: .destructive) { remoteToUnpair = remote }
                            }
                        }
                    }
                }
            }

            Section {
                Toggle(
                    "Allow Remotes to change other requests",
                    isOn: Binding(
                        get: { model.snapshot?.allowCrossRemoteEdits ?? false },
                        set: { model.setPolicy($0) }
                    )
                )
            } footer: {
                Text(
                    "When off, each Remote can change only its own requests. Pause, resume, and volume are always shared."
                )
            }
        }
        .formStyle(.grouped)
        .alert(
            "Unpair Remote?",
            isPresented: Binding(
                get: { remoteToUnpair != nil },
                set: { if !$0 { remoteToUnpair = nil } }
            ),
            presenting: remoteToUnpair
        ) { remote in
            Button("Unpair \(remote.name)", role: .destructive) { model.revoke(remote) }
            Button("Cancel", role: .cancel) {}
        } message: { remote in
            Text("\(remote.name) stops controlling Music through Cadenza Host. Pair it again to reconnect.")
        }
    }
}
