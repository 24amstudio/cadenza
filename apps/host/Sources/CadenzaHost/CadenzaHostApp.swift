import AppKit
import SwiftUI

@main
struct CadenzaHostApp: App {
    @State private var model = HostModel()
    @NSApplicationDelegateAdaptor(HostApplicationDelegate.self) private var delegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window("Cadenza Host", id: "host") {
            HostWindow(model: model)
                .task { if model.onboardingComplete { await model.start() } }
                .background(HostLaunchBridge(model: model, delegate: delegate))
        }
        .defaultSize(width: 800, height: 650)
        MenuBarExtra("Cadenza Host", systemImage: "waveform", isInserted: $showMenuBarIcon) {
            HostMenu(model: model)
                .task { if model.onboardingComplete { await model.start() } }
        }
    }
}

@MainActor
final class HostApplicationDelegate: NSObject, NSApplicationDelegate {
    var reopen: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopen?()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct HostLaunchBridge: View {
    var model: HostModel
    var delegate: HostApplicationDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            delegate.reopen = {
                model.selectedTab = 2
                openWindow(id: "host")
                NSApplication.shared.activate()
            }
        }
    }
}

private struct HostMenu: View {
    @Bindable var model: HostModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let current = model.snapshot?.current {
            Text(current.song.title)
            Text(current.song.artist)
            Button(model.snapshot?.playing == true ? "Pause" : "Resume") {
                model.control(model.snapshot?.playing == true ? "playback.pause" : "playback.resume")
            }.disabled(model.controlling)
        }
        if !model.running {
            Button(model.starting ? "Starting Host…" : "Start Host") { Task { await model.start() } }
                .disabled(model.starting || model.saving)
        }
        Button("Settings…") {
            model.selectedTab = 2
            openWindow(id: "host")
            NSApplication.shared.activate()
        }
        Divider()
        Button("Quit Cadenza Host") {
            model.service?.stop()
            NSApplication.shared.terminate(nil)
        }.keyboardShortcut("q")
    }
}
