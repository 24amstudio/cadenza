import AppKit
import SwiftUI

struct HostLaunchBridge: View {
    var model: HostModel
    var delegate: HostApplicationDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            delegate.terminate = { model.markCleanShutdown() }
            delegate.reopen = {
                model.selectedSection = .general
                openWindow(id: "host")
                NSApplication.shared.activate()
            }
        }
    }
}
