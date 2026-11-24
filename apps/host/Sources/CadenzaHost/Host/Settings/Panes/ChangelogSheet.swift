import SwiftUI

struct ChangelogSheet: View {
    let text: String
    let close: () -> Void

    // Release notes are Markdown from GitHub. Inline styling applies, while line breaks and list markers stay visible.
    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's New")
                .font(.title.bold())
            ScrollView {
                Text(rendered)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 420)
    }
}
