import SwiftUI

/// Previous, play or pause, and next. Icons carry the meaning, and each button keeps its name for VoiceOver.
struct PlaybackControls: View {
    @Bindable var model: HostModel

    var body: some View {
        let playing = model.snapshot?.playing == true
        HStack(spacing: 18) {
            Button {
                model.control("playback.previous")
            } label: {
                Label("Previous", systemImage: "backward.fill")
            }
            .help("Previous")
            Button {
                model.control(playing ? "playback.pause" : "playback.resume")
            } label: {
                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .help(playing ? "Pause" : "Play")
            Button {
                model.control("playback.skip")
            } label: {
                Label("Next", systemImage: "forward.fill")
            }
            .help("Next")
            if model.controlling {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Applying playback request")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(model.controlling)
    }
}
