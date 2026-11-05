import Foundation

struct MusicStatus: Codable, Sendable {
    var playing: Bool
    var state: String
    var volume: Int
    var positionMs: Int64
    /// Wall-clock time at which the script read the position. Scripts older than this field omit it.
    var readAtMs: Int64?
    var song: Song?
    /// Host monotonic time that `positionMs` describes. Set by the bridge; the script never reports it.
    var sampledAtMs: Int64?

    /// The Host monotonic time at which Music read the position. The script runs inside an osascript process that exits
    /// later, so stamping the sample at exit would place the position too late. The read is dated back from the wall
    /// clock instead, and clamped to the call so a clock step cannot produce a time outside it.
    static func sampleTime(readAtMs: Int64?, startedMs: Int64, finishedMs: Int64, nowWallMs: Int64) -> Int64? {
        guard let readAtMs else { return nil }

        let age = max(0, nowWallMs - readAtMs)

        return min(finishedMs, max(startedMs, finishedMs - age))
    }
}
