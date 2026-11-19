import SwiftUI

struct PlayingNextSection: View {
    let queue: [QueueEntry]
    let totalRemainingMs: Int64?

    var body: some View {
        Section {
            if queue.isEmpty {
                Text("The queue is empty.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(queue) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.song.title)
                            Text(entry.song.artist + " · " + entry.requesterName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.estimatedWaitMs.map { "About " + formatDuration($0) } ?? "Wait unknown")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Playing Next")
        } footer: {
            Text("Total remaining: " + formatDuration(totalRemainingMs))
        }
    }
}

struct AutoPlaySection: View {
    let rows: [NativeQueueRow]

    var body: some View {
        Section("AutoPlay") {
            ForEach(rows, id: \.token) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                    Text(row.artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

func formatDuration(_ milliseconds: Int64?) -> String {
    guard let milliseconds else { return "Unknown" }
    let seconds = max(0, milliseconds / 1_000)
    return "\(seconds / 60):" + String(format: "%02lld", seconds % 60)
}
