/// Maps a studio lyric timeline onto a music video whose length differs from the studio track. Lyrics are shown only
/// inside the musical segments that the mapping names. The user's nudge applies on top of the mapping.
enum VideoLyricAligner {
    /// Videos within this length of the studio track keep the studio timeline unchanged.
    static let fastPathToleranceMs: Int64 = 3_000

    struct Segment: Equatable, Sendable {
        /// Studio time from `studioStartMs` up to, but not including, `studioEndMs`.
        var studioStartMs: Int64
        var studioEndMs: Int64
        /// Added to a studio time inside this segment to find the video time.
        var videoOffsetMs: Int64
    }

    static func needsAlignment(studioDurationMs: Int64, videoDurationMs: Int64) -> Bool {
        abs(videoDurationMs - studioDurationMs) > fastPathToleranceMs
    }

    /// The video time for a studio lyric time, or nil when that time falls outside every musical segment.
    static func videoTime(forStudioMs time: Int64, segments: [Segment], userOffsetMs: Int64) -> Int64? {
        guard let segment = segments.first(where: { time >= $0.studioStartMs && time < $0.studioEndMs }) else {
            return nil
        }
        return time + segment.videoOffsetMs + userOffsetMs
    }
}
