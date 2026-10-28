import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import Translation

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
                    Text(remote.name)
                    Spacer()
                    if remote.revoked {
                        Text("Unpaired").foregroundStyle(.secondary)
                    } else {
                        Button("Unpair", role: .destructive) { model.revoke(remote) }
                    }
                }.padding(.vertical, 6)
            }
        }
    }
}

private struct PairingSheetItem: Identifiable {
    var id: String { invitation.secret }
    let invitation: PairingInvitation
    init(_ invitation: PairingInvitation) { self.invitation = invitation }
}

private struct PairingSheet: View {
    let invitation: PairingInvitation
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var json: String { (try? String(decoding: Wire.encode(invitation), as: UTF8.self)) ?? "" }

    var body: some View {
        VStack(spacing: 20) {
            Text("Pair Cadenza Remote").font(.title.bold())
            Text("Scan this QR code on your tablet. It is valid for one Remote for five minutes.")
            if let image = qr(json) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 400, height: 400)
                    .accessibilityLabel("Pairing QR code")
            }
            Text("\(invitation.host):\(invitation.port)").textSelection(.enabled)
            HStack {
                Button(copied ? "Copied" : "Copy pairing details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                    copied = true
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(minWidth: 560, minHeight: 560)
    }

    private func qr(_ value: String) -> NSImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(value.utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage,
            let image = CIContext().createCGImage(
                output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8)))
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

func formatDuration(_ milliseconds: Int64?) -> String {
    guard let milliseconds else { return "Unknown" }
    let seconds = max(0, milliseconds / 1_000)
    return "\(seconds / 60):" + String(format: "%02lld", seconds % 60)
}
