import SwiftUI

/// Connection preferences for this Mac and for each paired Remote. A Remote's own choice blends with the Host default.
/// Changes are saved by the Network pane, which owns the auto-save.
struct ConnectionPreferenceSections: View {
    @Bindable var model: HostModel

    var body: some View {
        Section {
            Picker("Preferred connection", selection: $model.hostTransportPolicy.preference) {
                preferenceOptions
            }
            Picker(
                "Connection path",
                selection: Binding(
                    get: { model.hostTransportPolicy.manualPath ?? "auto" },
                    set: { model.hostTransportPolicy.manualPath = $0 == "auto" ? nil : $0 })
            ) {
                pathOptions
            }
            DisclosureGroup("Limits") {
                Stepper(
                    "Maximum delay: \(model.hostTransportPolicy.constraints.maximumLatencyMs) ms",
                    value: $model.hostTransportPolicy.constraints.maximumLatencyMs,
                    in: 50...5_000,
                    step: 50)
                LabeledContent(
                    "Maximum packet loss: \(Int(model.hostTransportPolicy.constraints.maximumLossPercent))%"
                ) {
                    Slider(value: $model.hostTransportPolicy.constraints.maximumLossPercent, in: 0...100, step: 1)
                        .labelsHidden()
                }
                LabeledContent(
                    "Minimum reliability: \(Int(model.hostTransportPolicy.constraints.minimumReliabilityPercent))%"
                ) {
                    Slider(
                        value: $model.hostTransportPolicy.constraints.minimumReliabilityPercent, in: 0...100, step: 1
                    )
                    .labelsHidden()
                }
                Stepper(
                    "Minimum time before switching: \(model.hostTransportPolicy.minimumDwellMs / 1000) seconds",
                    value: $model.hostTransportPolicy.minimumDwellMs,
                    in: 0...300_000,
                    step: 5_000)
            }
        } header: {
            Text("Connection preference")
        } footer: {
            Text(
                "Limits exclude any connection that goes beyond them. Each Remote's preference is combined with this one."
            )
        }

        if !model.remotes.isEmpty {
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
                        preferenceOptions
                    }
                    Picker(
                        "Connection path",
                        selection: Binding(
                            get: { model.remoteTransportManualPaths[remote.id] ?? "auto" },
                            set: { model.remoteTransportManualPaths[remote.id] = $0 })
                    ) {
                        pathOptions
                    }
                    Button("Use Host Preference") {
                        model.remoteTransportPreferences.removeValue(forKey: remote.id)
                    }
                }
            }
        }
    }

    @ViewBuilder private var preferenceOptions: some View {
        Text("Balanced").tag(TransportPreference.balanced)
        Text("Lowest delay").tag(TransportPreference.latency)
        Text("Save power on this Mac").tag(TransportPreference.hostEfficiency)
        Text("Save power on Remotes").tag(TransportPreference.remoteEfficiency)
        Text("Most reliable").tag(TransportPreference.reliability)
    }

    @ViewBuilder private var pathOptions: some View {
        Text("Automatic").tag("auto")
        Text("Local network").tag("lan")
        Text("Bluetooth").tag("ble")
    }
}
