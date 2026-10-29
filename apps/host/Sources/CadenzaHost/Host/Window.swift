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
                Text(toast).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(16)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .alert(item: $model.prompt) { prompt in
            Alert(title: Text(prompt.title), message: Text(prompt.message), dismissButton: .default(Text("OK")))
        }
        .sheet(
            item: Binding(
                get: { model.invitation.map(PairingSheetItem.init) },
                set: { if $0 == nil { model.invitation = nil } }
            )
        ) { item in PairingSheet(invitation: item.invitation) }
    }

    private var settings: some View {
        TabView(selection: $model.selectedTab) {
            playback.tabItem { Label("Music", systemImage: "music.note") }.tag(0)
            devices.tabItem { Label("Remotes", systemImage: "ipad.and.iphone") }.tag(1)
            HostSettings(model: model).tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .padding(20)
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Music").font(.largeTitle.bold())
            if model.starting { ProgressView("Starting Host") }
            if let current = model.snapshot?.current {
                Text(current.song.title).font(.title.bold())
                Text(current.song.artist).font(.title3).foregroundStyle(.secondary)
                Text("Requested by \(current.requesterName)")
                HStack(spacing: 16) {
                    Button {
                        model.control("playback.previous")
                    } label: {
                        Label("Previous", systemImage: "backward.end.fill")
                    }
                    Button {
                        model.control(model.snapshot?.playing == true ? "playback.pause" : "playback.resume")
                    } label: {
                        Label(
                            model.snapshot?.playing == true ? "Pause" : "Resume",
                            systemImage: model.snapshot?.playing == true ? "pause.fill" : "play.fill")
                    }
                    Button {
                        model.control("playback.skip")
                    } label: {
                        Label("Next", systemImage: "forward.end.fill")
                    }
                    if model.controlling {
                        ProgressView().controlSize(.small).accessibilityLabel("Applying playback request")
                    }
                }.disabled(model.controlling)
            } else {
                Text("Nothing is playing").font(.title2)
            }
            if let issue = model.snapshot?.issue { Text(issue).foregroundStyle(.secondary) }
            List(model.snapshot?.queue ?? []) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.song.title).font(.headline)
                        Text("\(entry.song.artist) · \(entry.requesterName)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("≈ " + formatDuration(entry.estimatedWaitMs))
                }.padding(.vertical, 4)
            }
            HStack {
                Text("Total remaining ≈ " + formatDuration(model.snapshot?.totalRemainingMs))
                Spacer()
                Button("Open Music") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                Button("Reconcile queue") { model.selectedTab = 2 }
            }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Remotes").font(.largeTitle.bold())
            Toggle(
                "Allow Remotes to change others' requests",
                isOn: Binding(
                    get: { model.snapshot?.allowCrossRemoteEdits ?? false }, set: { model.setPolicy($0) }
                ))
            Text(
                "When off, a Remote cannot skip, seek, stop, or rearrange another Remote's request. Pause and resume are shared."
            )
            .foregroundStyle(.secondary)
            Button("Pair a Remote", action: model.pair).disabled(!model.running)
            List(model.remotes) { remote in
                HStack {
                    RemoteStatusRow(remote: remote)
                    Spacer()
                    if !remote.revoked {
                        Button("Unpair", role: .destructive) { model.revoke(remote) }
                    }
                }
            }
        }
    }
}
