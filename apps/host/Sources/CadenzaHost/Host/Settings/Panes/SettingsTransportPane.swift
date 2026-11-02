import SwiftUI

struct SettingsTransportPane: View {
    @Bindable var model: HostModel

    var body: some View {
        Form {
            Section {
                Picker("Host preference", selection: $model.hostTransportPolicy.preference) {
                    Text("Balanced").tag(TransportPreference.balanced)
                    Text("Prefer latency").tag(TransportPreference.latency)
                    Text("Prefer Host efficiency").tag(TransportPreference.hostEfficiency)
                    Text("Prefer Remote efficiency").tag(TransportPreference.remoteEfficiency)
                    Text("Prefer reliability").tag(TransportPreference.reliability)
                }
                Stepper(
                    "Maximum latency: \(model.hostTransportPolicy.constraints.maximumLatencyMs) ms",
                    value: $model.hostTransportPolicy.constraints.maximumLatencyMs,
                    in: 50...5_000,
                    step: 50)
                Slider(value: $model.hostTransportPolicy.constraints.maximumLossPercent, in: 0...100, step: 1) {
                    Text(
                        "Maximum packet loss: \(model.hostTransportPolicy.constraints.maximumLossPercent, specifier: "%.0f")%"
                    )
                }
                Slider(value: $model.hostTransportPolicy.constraints.minimumReliabilityPercent, in: 0...100, step: 1) {
                    Text(
                        "Minimum reliability: \(model.hostTransportPolicy.constraints.minimumReliabilityPercent, specifier: "%.0f")%"
                    )
                }
                Picker(
                    "Path selection",
                    selection: Binding(
                        get: { model.hostTransportPolicy.manualPath ?? "auto" },
                        set: { model.hostTransportPolicy.manualPath = $0 == "auto" ? nil : $0 })
                ) {
                    Text("Auto").tag("auto")
                    Text("Use LAN").tag("lan")
                    Text("Use Bluetooth").tag("ble")
                }
                Stepper(
                    "Minimum dwell: \(model.hostTransportPolicy.minimumDwellMs / 1000) seconds",
                    value: $model.hostTransportPolicy.minimumDwellMs,
                    in: 0...300_000,
                    step: 5_000)
                Button("Save transport policy") { model.saveTransportPolicy() }
            } header: {
                Text("Defaults")
            } footer: {
                Text(
                    "Host limits always exclude paths that exceed these thresholds. Preferences blend with each Remote's preference."
                )
            }

            ForEach(model.remotes) { remote in
                Section(remote.name) {
                    Picker(
                        "Preference",
                        selection: Binding(
                            get: {
                                model.remoteTransportPreferences[remote.id] ?? model.hostTransportPolicy.preference
                            },
                            set: { model.remoteTransportPreferences[remote.id] = $0 })
                    ) {
                        Text("Balanced").tag(TransportPreference.balanced)
                        Text("Prefer latency").tag(TransportPreference.latency)
                        Text("Prefer Host efficiency").tag(TransportPreference.hostEfficiency)
                        Text("Prefer Remote efficiency").tag(TransportPreference.remoteEfficiency)
                        Text("Prefer reliability").tag(TransportPreference.reliability)
                    }
                    Picker(
                        "Path",
                        selection: Binding(
                            get: { model.remoteTransportManualPaths[remote.id] ?? "auto" },
                            set: { model.remoteTransportManualPaths[remote.id] = $0 })
                    ) {
                        Text("Auto").tag("auto")
                        Text("Use LAN").tag("lan")
                        Text("Use Bluetooth").tag("ble")
                    }
                    Button("Use global default") {
                        model.remoteTransportPreferences.removeValue(forKey: remote.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Transport")
    }
}
