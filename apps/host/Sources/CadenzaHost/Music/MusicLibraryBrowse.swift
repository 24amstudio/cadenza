import Foundation

// Read-only library listings for browsing: playlists, and the tracks of a playlist, album, or artist. They run the
// same fixed music.js entry point as every other Music action and take only validated text as arguments.
struct MusicLibraryBrowser: BrowseLibrarySource {
    let bridge: MusicBridge

    func song(_ identity: SongIdentity) async throws -> Song { try await bridge.resolve(identity) }
    func playlists() async throws -> [BrowsePlaylistSummary] { try await bridge.browsePlaylists() }
    func playlist(id: String) async throws -> (name: String, total: Int, songs: [Song]) {
        try await bridge.browsePlaylist(id: id)
    }
    func songs(onAlbum album: String, artist: String) async throws -> [Song] {
        try await bridge.browseSongs(onAlbum: album, artist: artist)
    }
    func songs(byArtist artist: String) async throws -> [Song] { try await bridge.browseSongs(byArtist: artist) }
}

extension MusicBridge {
    private struct PlaylistTracks: Decodable {
        var name: String
        var total: Int
        var songs: [Song]
    }

    fileprivate func browsePlaylists() async throws -> [BrowsePlaylistSummary] {
        try Wire.decode([BrowsePlaylistSummary].self, from: await browseScript(["playlists"]))
    }

    fileprivate func browsePlaylist(id: String) async throws -> (name: String, total: Int, songs: [Song]) {
        guard id.range(of: "^[0-9A-F]{16}$", options: .regularExpression) != nil else {
            throw CadenzaError.failure("invalid_command", "Invalid playlist.")
        }
        let tracks = try Wire.decode(PlaylistTracks.self, from: await browseScript(["playlist", id]))
        return (tracks.name, tracks.total, tracks.songs)
    }

    fileprivate func browseSongs(onAlbum album: String, artist: String) async throws -> [Song] {
        try Wire.decode([Song].self, from: await browseScript(["album-tracks", album, artist]))
    }

    fileprivate func browseSongs(byArtist artist: String) async throws -> [Song] {
        try Wire.decode([Song].self, from: await browseScript(["artist-tracks", artist]))
    }

    private func browseScript(_ arguments: [String]) async throws -> Data {
        guard let url = HostResources.bundle.url(forResource: "music", withExtension: "js", subdirectory: "Resources")
        else {
            throw CadenzaError.failure("music_unavailable", "The Music automation script is missing.")
        }
        do {
            // A large library takes longer to list than a transport action takes to dispatch.
            return try await Subprocess.run(
                "/usr/bin/osascript", ["-l", "JavaScript", url.path] + arguments, timeout: 10)
        } catch let error as CadenzaError where error.localizedDescription.contains("is unavailable") {
            throw CadenzaError.failure("not_found", "This item is no longer in the Music library.")
        }
    }
}
