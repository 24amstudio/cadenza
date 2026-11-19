import AppKit
import SwiftUI

/// The inspector for the selected entries: every field, the message in full and the metadata as indented JSON.
struct LogDetailView: View {
    let rows: [LogRow]
    let copy: ([LogRow]) -> Void

    var body: some View {
        if rows.count == 1, let row = rows.first {
            entry(row)
        } else if rows.isEmpty {
            ContentUnavailableView(
                "No entry selected", systemImage: "text.alignleft",
                description: Text("Select a log entry to see its details."))
        } else {
            ContentUnavailableView {
                Label("\(rows.count) entries selected", systemImage: "list.bullet")
            } description: {
                Text("Select a single entry to see its details.")
            } actions: {
                Button("Copy Entries") { copy(rows) }
            }
        }
    }

    private func entry(_ row: LogRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Form {
                    LabeledContent("Time", value: row.timestamp)
                    LabeledContent("Level") { LogLevelLabel(level: row.level) }
                    LabeledContent("Source", value: row.sourceTitle)
                    LabeledContent("Category", value: row.category)
                    LabeledContent("Action", value: row.action)
                    LabeledContent("Host version", value: row.hostVersion)
                    if let remote = row.remoteVersion { LabeledContent("Remote version", value: remote) }
                }
                .formStyle(.columns)
                section("Message", text: row.message)
                if let metadata = row.prettyMetadata { section("Metadata", text: metadata, monospaced: true) }
                Button("Copy Entry") { copy([row]) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, text: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text)
                .font(monospaced ? .system(.callout, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
