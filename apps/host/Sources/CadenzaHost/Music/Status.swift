import Foundation

struct MusicStatus: Codable, Sendable {
    var playing: Bool
    var state: String
    var volume: Int
    var positionMs: Int64
    /// Wall-clock time at which the script read the position. Scripts older than this field omit it.
    var readAtMs: Int64?
    var song: Song?
    /// Music's shuffle switch and repeat mode ("off", "one", or "all"). Scripts older than these fields omit them.
    var shuffle: Bool = false
    var `repeat`: String = "off"
    /// Host monotonic time that `positionMs` describes. Set by the bridge; the script never reports it.
    var sampledAtMs: Int64?

    init(
        playing: Bool, state: String, volume: Int, positionMs: Int64, readAtMs: Int64? = nil, song: Song? = nil,
        shuffle: Bool = false, repeat mode: String = "off", sampledAtMs: Int64? = nil
    ) {
        self.playing = playing
        self.state = state
        self.volume = volume
        self.positionMs = positionMs
        self.readAtMs = readAtMs
        self.song = song
        self.shuffle = shuffle
        self.repeat = mode
        self.sampledAtMs = sampledAtMs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        playing = try values.decode(Bool.self, forKey: .playing)
        state = try values.decode(String.self, forKey: .state)
        volume = try values.decode(Int.self, forKey: .volume)
        positionMs = try values.decode(Int64.self, forKey: .positionMs)
        readAtMs = try values.decodeIfPresent(Int64.self, forKey: .readAtMs)
        song = try values.decodeIfPresent(Song.self, forKey: .song)
        shuffle = try values.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        self.repeat = try values.decodeIfPresent(String.self, forKey: .repeat) ?? "off"
        sampledAtMs = try values.decodeIfPresent(Int64.self, forKey: .sampledAtMs)
    }

    /// The Host monotonic time at which Music read the position. The script runs inside an osascript process that exits
    /// later, so stamping the sample at exit would place the position too late. The read is dated back from the wall
    /// clock instead, and clamped to the call so a clock step cannot produce a time outside it.
    static func sampleTime(readAtMs: Int64?, startedMs: Int64, finishedMs: Int64, nowWallMs: Int64) -> Int64? {
        guard let readAtMs else { return nil }

        let age = max(0, nowWallMs - readAtMs)

        return min(finishedMs, max(startedMs, finishedMs - age))
    }
}
