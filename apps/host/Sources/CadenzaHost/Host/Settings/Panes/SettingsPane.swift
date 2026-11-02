import Foundation

/// The categories listed in Settings. Each one opens a pane that owns only its own controls.
enum SettingsPane: CaseIterable, Hashable, Identifiable {
    case general, network, transport, music, recommendations, lyrics, storage, updates

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .network: "Network"
        case .transport: "Transport"
        case .music: "Music"
        case .recommendations: "Recommendations"
        case .lyrics: "Lyrics and Translation"
        case .storage: "Storage and Logs"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .network: "network"
        case .transport: "arrow.left.arrow.right"
        case .music: "music.note"
        case .recommendations: "sparkles"
        case .lyrics: "text.quote"
        case .storage: "internaldrive"
        case .updates: "arrow.down.circle"
        }
    }
}
