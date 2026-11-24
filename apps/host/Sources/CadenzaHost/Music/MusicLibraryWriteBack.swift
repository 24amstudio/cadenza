import Foundation

/// Arguments for the fixed Music write-back actions. Only library songs can be written, so a catalog or stream identity
/// is refused before Music is touched.
enum MusicLibraryWriteBack {
    static let playlistTrackLimit = 200
    static let playlistNameLimit = 100

    static func favoriteArguments(_ identity: SongIdentity, favorite: Bool) throws -> [String] {
        guard isLibraryIdentity(identity) else { throw invalidSong() }
        return ["favorite", identity.id, favorite ? "true" : "false"]
    }

    static func playlistArguments(name: String, _ identities: [SongIdentity]) throws -> [String] {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= playlistNameLimit else {
            throw CadenzaError.failure("playlist_name", "Use a playlist name of 1 to \(playlistNameLimit) characters.")
        }
        guard !identities.isEmpty, identities.count <= playlistTrackLimit else {
            throw CadenzaError.failure("playlist_tracks", "A playlist write takes 1 to \(playlistTrackLimit) songs.")
        }
        guard identities.allSatisfy(isLibraryIdentity) else { throw invalidSong() }
        return ["playlist-add", title] + identities.map(\.id)
    }

    private static func isLibraryIdentity(_ identity: SongIdentity) -> Bool {
        identity.source == "library" && identity.id.count == 16
            && identity.id.allSatisfy { "0123456789ABCDEF".contains($0) }
    }

    private static func invalidSong() -> CadenzaError {
        .failure("library_only", "Only songs in your Music library can be changed this way.")
    }
}
