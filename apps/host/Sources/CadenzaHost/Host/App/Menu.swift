import AppKit
import SwiftUI

struct HostMenu: View {
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
