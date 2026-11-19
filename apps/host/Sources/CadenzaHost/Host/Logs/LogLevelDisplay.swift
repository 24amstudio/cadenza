import SwiftUI

extension HostLogLevel: CaseIterable, Comparable {
    static var allCases: [HostLogLevel] { [.debug, .info, .warning, .error] }

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        }
    }

    static func < (lhs: HostLogLevel, rhs: HostLogLevel) -> Bool { lhs.rank < rhs.rank }

    var title: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    /// The level menu is a minimum, so each choice says what it lets through.
    var minimumTitle: String {
        switch self {
        case .debug: "All levels"
        case .info: "Info and above"
        case .warning: "Warnings and errors"
        case .error: "Errors only"
        }
    }

    /// Each level has its own glyph and word, so color is never the only signal.
    var symbol: String {
        switch self {
        case .debug: "ant"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
