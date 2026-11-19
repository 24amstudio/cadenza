import SwiftUI

struct ChangelogSheet: View {
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's New")
                .font(.title.bold())
            ScrollView {
                Text(text)
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
