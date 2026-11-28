import Foundation

struct SingPageState: Encodable, Equatable, Sendable {
    let type = "sing_state"
    let occurrenceId: String
    let title: String
    let artist: String
    let positionMs: Int64
    let playing: Bool

    static func make(
        from current: CurrentPlayback, playing: Bool, lipSyncOffsetMs: Int, userOffsetMs: Int
    ) -> SingPageState {
        SingPageState(
            occurrenceId: current.occurrenceId,
            title: current.song.title,
            artist: current.song.artist,
            positionMs: current.positionMs - Int64(lipSyncOffsetMs) - Int64(userOffsetMs),
            playing: playing)
    }
}
