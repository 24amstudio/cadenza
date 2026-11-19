import SwiftUI

struct NowPlayingScreen: View {
    @Bindable var model: HostModel

    var body: some View {
        Form {
            if let issue = model.snapshot?.issue {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Fix in Settings") { model.selectedSection = .music }
                    }
                }
            }
            Section {
                NowPlayingHero(model: model)
            }
            PlayingNextSection(
                queue: model.snapshot?.queue ?? [],
                totalRemainingMs: model.snapshot?.totalRemainingMs
            )
            if let autoPlay = model.service?.queue.autoPlay, !autoPlay.isEmpty {
                AutoPlaySection(rows: autoPlay)
            }
        }
        .formStyle(.grouped)
    }
}
