import SwiftUI

/// The entries as a native table that follows the newest row until the user scrolls away.
struct LogTable: View {
    let rows: [LogRow]
    let isPaused: Bool
    let loadedToken: Int
    @Binding var selection: Set<LogRow.ID>
    let copy: ([LogRow]) -> Void
    // Whether the newest row is on screen. It is the only signal that the user has scrolled away from the tail.
    @State private var newestVisible = true

    var body: some View {
        ScrollViewReader { proxy in
            Table(rows, selection: $selection) {
                TableColumn("Time") { row in
                    Text(row.time)
                        .monospacedDigit()
                        .onAppear { if row.id == rows.last?.id { newestVisible = true } }
                        .onDisappear { if row.id == rows.last?.id { newestVisible = false } }
                }
                .width(min: 108, ideal: 116, max: 140)
                TableColumn("Level") { LogLevelLabel(level: $0.level) }
                    .width(min: 78, ideal: 92, max: 110)
                TableColumn("Source") { Text($0.sourceTitle) }
                    .width(min: 60, ideal: 110, max: 150)
                TableColumn("Category") { Text($0.category).lineLimit(1) }
                    .width(min: 40, ideal: 100, max: 160)
                TableColumn("Action") { Text($0.action).lineLimit(1) }
                    .width(min: 50, ideal: 130, max: 260)
                TableColumn("Message") { Text($0.listMessage).lineLimit(1) }
                    .width(min: 80)
            }
            .onCopyCommand {
                let chosen = rows.filter { selection.contains($0.id) }
                guard !chosen.isEmpty else { return [] }
                return [NSItemProvider(object: LogTranscript.text(chosen) as NSString)]
            }
            .contextMenu(forSelectionType: LogRow.ID.self) { ids in
                let chosen = rows.filter { ids.contains($0.id) }
                Button("Copy") { copy(chosen) }.disabled(chosen.isEmpty)
            }
            .onChange(of: rows.last?.id) {
                guard newestVisible, !isPaused else { return }
                scrollToNewest(proxy)
            }
            .onChange(of: loadedToken) { scrollToNewest(proxy) }
            // The table only exists once there are rows, so the first read finishes before it can observe the token.
            .onAppear { scrollToNewest(proxy) }
            .overlay(alignment: .bottomTrailing) {
                if !newestVisible, !rows.isEmpty {
                    Button {
                        scrollToNewest(proxy)
                    } label: {
                        Label("Jump to Latest", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .padding(16)
                    .shadow(radius: 4, y: 1)
                }
            }
        }
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        guard let id = rows.last?.id else { return }
        Task { @MainActor in
            proxy.scrollTo(id, anchor: .bottomLeading)
            newestVisible = true
        }
    }
}
