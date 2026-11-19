/// Every pane the main window can show. The selection lives on the model, so it survives closing and reopening the
/// window, and menu-bar commands can choose a pane.
enum HostSection: Hashable, Identifiable {
    case nowPlaying, remotes, logs
    case general, network, music, lyrics, storage, updates

    static let settings: [HostSection] = [.general, .network, .music, .lyrics, .storage, .updates]

    var id: Self { self }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .remotes: "Remotes"
        case .logs: "Logs"
        case .general: "General"
        case .network: "Network"
        case .music: "Music"
        case .lyrics: "Lyrics"
        case .storage: "Storage"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .remotes: "ipad.and.iphone"
        case .logs: "list.bullet.rectangle"
        case .general: "gearshape"
        case .network: "network"
        case .music: "music.note.list"
        case .lyrics: "text.quote"
        case .storage: "internaldrive"
        case .updates: "arrow.down.circle"
        }
    }
}
