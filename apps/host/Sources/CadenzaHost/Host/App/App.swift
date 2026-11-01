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
                .background(HostLaunchBridge(model: model, delegate: delegate))
        }
    }
}
