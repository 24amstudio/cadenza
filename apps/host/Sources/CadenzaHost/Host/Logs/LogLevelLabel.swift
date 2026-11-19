import SwiftUI

struct LogLevelLabel: View {
    let level: HostLogLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color)
                .accessibilityHidden(true)
            Text(level.title)
        }
        .accessibilityElement(children: .combine)
    }
}
