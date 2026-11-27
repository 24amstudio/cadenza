import SwiftUI

/// The Mac's audio output, and the Wi-Fi subwoofer split. The split's setup is saved here, and a Remote can change the
/// same setup from its own controls.
struct SettingsOutputPane: View {
    @Bindable var model: HostModel
    @State private var outputs: [AudioOutput] = []
    @State private var settingUp = false

    private var hub: RemoteAudioHub? { model.service?.publishedState.remoteAudio }

    private var setup: RemoteAudioStreamConfig? { hub?.setup }

    private var remoteText: String {
        guard let target = setup?.targetClientId else { return "None chosen" }
        let name = model.remotes.first { $0.id == target }?.name ?? hub?.remoteName(target) ?? "Remote"
        let online = model.wifiSplitRemotes.contains { $0.id == target }
        return online ? name : "\(name), offline"
    }

    private var roomText: String {
        switch hub?.roomStatus ?? .notMeasured {
        case .notMeasured: "Not measured"
        case .measuring: "Measuring for 2 seconds"
        case .measured:
            "Sub aligned by \((hub?.acousticOffsetMs ?? 0).formatted(.number.precision(.fractionLength(1)))) ms"
        case .needsMicrophone: "Needs microphone access"
        case .failed: "Measurement failed"
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(outputs, id: \.id) { output in
                    LabeledContent(output.name) {
                        Text(output.isDefault ? "Default" : output.transport)
                            .foregroundStyle(output.isDefault ? Color.primary : Color.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        _ = AudioOutputs.select(output.id)
                        outputs = AudioOutputs.current()
                    }
                }
            } header: {
                Text("Mac output")
            } footer: {
                Text("Music plays to the default output. Select an output to make it the default.")
            }

            Section {
                LabeledContent("Remote", value: remoteText)
                LabeledContent(
                    "Crossover", value: "\(Int(setup?.crossoverHz ?? RemoteAudioStreamConfig.defaultCrossoverHz)) Hz")
                LabeledContent(
                    "Sub gain", value: (setup?.subGainDb ?? 0).formatted(.number.precision(.fractionLength(1))) + " dB")
                LabeledContent("Phase", value: setup?.phaseInvert == true ? "Inverted" : "Normal")
                LabeledContent(
                    "Distance trim",
                    value: (setup?.manualDistanceOffsetMs ?? 0).formatted(.number.precision(.fractionLength(1))) + " ms"
                )
                LabeledContent("Room", value: roomText)
                Button("Set Up New LPF Output Environment") { settingUp = true }
                Button("Re-calibrate Room") { hub?.startNewEnvironment() }
                    .disabled(hub == nil)
            } header: {
                Text("Wi-Fi subwoofer split")
            } footer: {
                Text(
                    "The Mac plays the low frequencies, and the Remote plays the high frequencies. A Remote can change "
                        + "these settings too. Cadenza listens for two seconds of music to measure the room, with no test tone."
                )
            }
        }
        .formStyle(.grouped)
        .onAppear { outputs = AudioOutputs.current() }
        .sheet(isPresented: $settingUp) {
            LPFSetupSheet(model: model, isPresented: $settingUp)
        }
    }
}
