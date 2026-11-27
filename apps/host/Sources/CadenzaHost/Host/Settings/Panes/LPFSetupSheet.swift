import AVFoundation
import SwiftUI

/// Sets up a new subwoofer environment: which Remote plays the mains, the crossover, the trims, and a room measurement.
/// Done saves the setup, starts the split, and measures the room if microphone access was allowed.
struct LPFSetupSheet: View {
    @Bindable var model: HostModel
    @Binding var isPresented: Bool
    @State private var draft = RemoteAudioStreamConfig(enabled: true, streamMode: .crossoverSplit, targetClientId: nil)
    @State private var askingMicrophone = false

    private var hub: RemoteAudioHub? { model.service?.publishedState.remoteAudio }

    private var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let remotes = hub?.connectedRemotes, !remotes.isEmpty {
                        Picker("Mains Remote", selection: $draft.targetClientId) {
                            ForEach(remotes) { remote in
                                Text(remote.name).tag(Optional(remote.id))
                            }
                        }
                    } else {
                        Text("Connect a Remote on Wi-Fi to choose the mains.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Mains")
                }

                Section {
                    LabeledContent("Crossover \(Int(draft.crossoverHz)) Hz") {
                        Slider(value: $draft.crossoverHz, in: 40...160, step: 1)
                            .frame(width: 220)
                    }
                    LabeledContent("Sub gain \(draft.subGainDb.formatted(.number.precision(.fractionLength(1)))) dB") {
                        Slider(value: $draft.subGainDb, in: -12...12, step: 0.5)
                            .frame(width: 220)
                    }
                    Toggle("Invert sub phase (180°)", isOn: $draft.phaseInvert)
                    LabeledContent(
                        "Distance trim \(draft.manualDistanceOffsetMs.formatted(.number.precision(.fractionLength(1)))) ms"
                    ) {
                        Slider(value: $draft.manualDistanceOffsetMs, in: -50...50, step: 0.5)
                            .frame(width: 220)
                    }
                } header: {
                    Text("Crossover")
                }

                Section {
                    if microphoneStatus == .notDetermined {
                        Button("Allow Microphone…") { askingMicrophone = true }
                    } else if microphoneStatus != .authorized {
                        Text(
                            "Allow Cadenza Host in System Settings › Privacy & Security › Microphone to measure the room."
                        )
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Room")
                } footer: {
                    Text("Measuring takes two seconds of music from this Mac and the mains. Nothing is recorded.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set Up New LPF Output Environment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .disabled(draft.targetClientId == nil)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .onAppear {
            draft = hub?.setup ?? draft
            if draft.targetClientId == nil {
                draft.targetClientId = hub?.connectedRemotes.first?.id
            }
        }
        .alert("Allow the microphone?", isPresented: $askingMicrophone) {
            Button("Continue") { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("macOS asks once. Cadenza uses the microphone only to measure the room for the subwoofer split.")
        }
    }

    /// Saves the setup and measures a new environment. The stream starts with the saved setup.
    private func finish() {
        guard let hub else { return }
        hub.updateSetup(draft)
        hub.startNewEnvironment()
        isPresented = false
    }
}
