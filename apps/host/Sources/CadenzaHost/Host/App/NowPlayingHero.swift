import SwiftUI

/// The current song, centered above its transport controls. Shows an empty state when nothing is playing.
struct NowPlayingHero: View {
    @Bindable var model: HostModel

    var body: some View {
        VStack(spacing: 16) {
            if let current = model.snapshot?.current {
                VStack(spacing: 4) {
                    Text(current.song.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(current.song.artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Requested by " + current.requesterName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                PlaybackControls(model: model)
            } else {
                ContentUnavailableView("Nothing is playing", systemImage: "music.note")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
