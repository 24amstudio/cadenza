import Foundation

protocol LyricsProvider: Sendable {
    var id: String { get }
    func document(song: Song, occurrence: String) async throws -> LyricDocument?
}
