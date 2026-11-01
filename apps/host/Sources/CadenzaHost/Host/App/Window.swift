import AppKit
import SwiftUI

struct HostWindow: View {
    @Bindable var model: HostModel

    var body: some View {
        Group {
            if !model.onboardingComplete || model.showingSetup {
                HostOnboarding(model: model)
            } else {
                settings
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(16)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .alert(item: $model.prompt) { prompt in
            Alert(title: Text(prompt.title), message: Text(prompt.message), dismissButton: .default(Text("OK")))
        }
        .sheet(item: Binding(get: { model.invitation.map(PairingSheetItem.init) }, set: { if $0 == nil { model.invitation = nil } })) { item in
            PairingSheet(invitation: item.invitation)
        }
    }

    private var settings: some View {
        NavigationSplitView {
            List(selection: $model.selectedTab) {
                Section("Cadenza Host") {
                    Label("Music", systemImage: "music.note").tag(0)
                    Label("Remotes", systemImage: "ipad.and.iphone").tag(1)
                }
                Section { Label("Settings", systemImage: "gearshape").tag(2) }
            }
            .listStyle(.sidebar)
            .navigationTitle("Cadenza Host")
        } detail: {
            Group {
                switch model.selectedTab {
                case 0: playback
                case 1: devices
                default: HostSettings(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem {
                    if model.running {
                        Label("Host is running", systemImage: "circle.fill").foregroundStyle(.green)
                    } else if model.starting {
                        ProgressView().controlSize(.small).accessibilityLabel("Starting Host")
                    } else {
                        Label("Host is stopped", systemImage: "circle").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Now Playing") {
                    if let current = model.snapshot?.current {
                        LabeledContent("Title", value: current.song.title)
                        LabeledContent("Artist", value: current.song.artist)
                        LabeledContent("Requested by", value: current.requesterName)
                        HStack {
                            Button { model.control("playback.previous") } label: { Label("Previous", systemImage: "backward.end.fill") }
                            Button { model.control(model.snapshot?.playing == true ? "playback.pause" : "playback.resume") } label: {
                                Label(model.snapshot?.playing == true ? "Pause" : "Play", systemImage: model.snapshot?.playing == true ? "pause.fill" : "play.fill")
                            }
                            Button { model.control("playback.skip") } label: { Label("Next", systemImage: "forward.end.fill") }
                            if model.controlling { ProgressView().controlSize(.small).accessibilityLabel("Applying playback request") }
                        }
                        .disabled(model.controlling)
                    } else {
                        Label("Nothing is playing", systemImage: "music.note").foregroundStyle(.secondary)
                    }
                    if let issue = model.snapshot?.issue {
                        Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    }
                }
                Section("Playing Next") {
                    if (model.snapshot?.queue ?? []).isEmpty {
                        Text("The queue is empty.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.snapshot?.queue ?? []) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.song.title)
                                    Text(entry.song.artist + " / " + entry.requesterName).foregroundStyle(.secondary).font(.callout)
                                }
                                Spacer()
                                Text("Approx. " + formatDuration(entry.estimatedWaitMs)).foregroundStyle(.secondary).font(.callout.monospacedDigit())
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Total remaining: " + formatDuration(model.snapshot?.totalRemainingMs)).foregroundStyle(.secondary)
                Spacer()
                Button("Open Music") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                Button("Reconcile queue") { model.selectedTab = 2 }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }

    private var devices: some View {
        Form {
            Section("Remote access") {
                Toggle("Allow Remotes to change other requests", isOn: Binding(get: { model.snapshot?.allowCrossRemoteEdits ?? false }, set: { model.setPolicy($0) }))
                Text("When off, a Remote can control only its own requests. Pause and resume remain shared.").foregroundStyle(.secondary)
                Button("Pair a Remote", action: model.pair).buttonStyle(.borderedProminent).disabled(!model.running)
            }
            Section("Paired Remotes") {
                if model.remotes.isEmpty {
                    ContentUnavailableView("No Remotes paired", systemImage: "ipad.and.iphone", description: Text("Pair a Remote to control Music from another device."))
                } else {
                    ForEach(model.remotes) { remote in
                        HStack {
                            RemoteStatusRow(remote: remote)
                            Spacer()
                            if !remote.revoked { Button("Unpair", role: .destructive) { model.revoke(remote) } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

func formatDuration(_ milliseconds: Int64?) -> String {
    guard let milliseconds else { return "Unknown" }
    let seconds = max(0, milliseconds / 1_000)
    return "\(seconds / 60):" + String(format: "%02lld", seconds % 60)
}
