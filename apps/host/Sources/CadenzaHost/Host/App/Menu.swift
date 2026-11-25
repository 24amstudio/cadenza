import AppKit
import SwiftUI

struct HostMenu: View {
    @Bindable var model: HostModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let current = model.snapshot?.current {
            Section("Now Playing") {
                Text("Now Playing").font(.headline)
                Text(current.song.title)
                Text(current.song.artist).foregroundStyle(.secondary)
                Button(model.snapshot?.playing == true ? "Pause" : "Resume") {
                    model.control(model.snapshot?.playing == true ? "playback.pause" : "playback.resume")
                }.disabled(model.controlling)
                // Favorite the current song in Apple Music (library only)
                if current.song.source == "library" {
                    Button("Favorite") {
                        Task { await model.control("library.favorite") }
                    }
                }
            }
            Divider()
            // Add current song to a Host playlist
            if current.song.source == "library" {
                Button("Add to Host Playlist") {
                    Task { await model.control("library.addToPlaylist") }
                }
            }
            // Share menu
            Menu("Share") {
                Button("Play now") {
                    Task { await model.control("queue.play_now") }
                }
                Button("Play next") {
                    Task { await model.control("queue.play_next") }
                }
                Button("Add to queue") {
                    Task { await model.control("queue.add") }
                }
            }
        }
        if !model.running {
            Button(model.starting ? "Starting Host..." : "Start Host") { Task { await model.start() } }
                .disabled(model.starting || model.saving)
        } else {
            Label("Host is running", systemImage: "circle.fill").foregroundStyle(.green)
            if model.energy.budget != .unrestricted {
                Label("Power: \(model.energy.budget.title)", systemImage: "thermometer.medium")
            }
        }
        Button("Settings...") {
            model.selectedSection = .general
            openWindow(id: "host")
            NSApplication.shared.activate()
        }
        Button("Logs…") {
            model.selectedSection = .logs
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
