import Foundation

struct SongIdentity: Codable, Hashable, Sendable {
    var source: String
    var id: String
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

    var identity: SongIdentity { SongIdentity(source: source, id: id) }
}
