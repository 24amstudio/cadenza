import Foundation

struct MusicStatus: Codable, Sendable {
    var playing: Bool
    var state: String
    var volume: Int
    var positionMs: Int64
    var song: Song?
}
