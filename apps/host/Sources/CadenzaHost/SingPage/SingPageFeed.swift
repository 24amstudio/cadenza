import Foundation

@MainActor
final class SingPageFeed {
    private var pages: [UUID: @MainActor (Data) -> Bool] = [:]
    private var state: SingPageState?
    private var lyricsFrame: Data?
    private var lyricsKey: String?

    func attach(send: @escaping @MainActor (Data) -> Bool) -> UUID {
        let id = UUID()
        pages[id] = send
        if let lyricsFrame { _ = send(lyricsFrame) }
        if let state, let data = try? Wire.encode(state) { _ = send(data) }
        return id
    }

    func detach(_ id: UUID) {
        pages.removeValue(forKey: id)
    }

    func update(state next: SingPageState, lyrics: LyricDocument?) {
        if let lyrics {
            let key = Self.key(for: lyrics)
            if key != lyricsKey, let data = try? Wire.encode(Frame(type: "lyrics", lyrics: lyrics)) {
                lyricsKey = key
                lyricsFrame = data
                broadcast(data)
            }
        } else {
            lyricsKey = nil
            lyricsFrame = nil
        }
        guard next != state, let data = try? Wire.encode(next) else { return }
        state = next
        broadcast(data)
    }

    private func broadcast(_ data: Data) {
        for send in pages.values { _ = send(data) }
    }

    private static func key(for lyrics: LyricDocument) -> String {
        "\(lyrics.occurrenceId)|\(lyrics.revision)|\(lyrics.userOffsetMs ?? 0)"
    }
}
