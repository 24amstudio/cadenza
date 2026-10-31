import AppKit
import SwiftUI

struct HostLaunchBridge: View {
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
