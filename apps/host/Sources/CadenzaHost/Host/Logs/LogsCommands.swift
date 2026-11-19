import AppKit
import SwiftUI

/// The Window menu entry that opens the main window on the Logs section.
struct LogsCommands: Commands {
    var model: HostModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Logs") {
                model.selectedSection = .logs
                openWindow(id: "host")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
        }
    }
}
