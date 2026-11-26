import Foundation

/// Records taste from queue activity. Taste is best effort: a failed write never blocks or fails a command, and a song
/// whose details the Host does not know is not scored.
extension QueueCoordinator {
    func recordTaste(_ signal: TasteSignal, identity: SongIdentity?, actor: String) {
        guard let identity, let song = knownSongs[identity] else { return }

        let fromAutoPlay = autoPlay.contains { $0.title == song.title && $0.artist == song.artist }

        writeTaste(TasteSignal.played(signal, fromAutoPlay: fromAutoPlay), song: song, actor: actor)
    }

    func writeTaste(_ signal: TasteSignal, song: Song, actor: String) {
        guard !song.artist.isEmpty else { return }

        let now = Date()

        try? TasteLedger(database: store.database).record(
            remoteId: actor, signal: signal, artist: song.artist, track: song.id, at: now,
            bucket: TasteBucket.bucket(for: now))
    }
}
