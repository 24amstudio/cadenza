import Foundation

struct SongIdentity: Codable, Hashable, Sendable {
    var source: String
    var id: String
}

// Search can return music videos beside songs. A video is listed for discovery only; it is never queued as a song.
enum MediaType: String, Codable, Sendable {
    case song
    case musicVideo
}

struct Song: Codable, Identifiable, Equatable, Sendable {
    var source: String
    var id: String
    var title: String
    var artist: String
    var album: String = ""
    var durationMs: Int64? = nil
    var artworkUrl: String? = nil
    var url: String? = nil
    // Optional so a Remote's song metadata from before this field still decodes.
    var mediaType: MediaType? = nil

    var identity: SongIdentity { SongIdentity(source: source, id: id) }
}
