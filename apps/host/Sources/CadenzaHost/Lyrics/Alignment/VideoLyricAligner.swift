/// Maps a studio lyric timeline onto a music video whose length differs from the studio track. Lyrics are shown only
/// inside the musical segments that the mapping names. The user's nudge applies on top of the mapping.
enum VideoLyricAligner {
    /// Videos within this length of the studio track keep the studio timeline unchanged.
    static let fastPathToleranceMs: Int64 = 3_000

    struct Segment: Codable, Equatable, Sendable {
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

    /// Rewrites a studio lyric document onto the music video's timeline, hiding lines during non-musical story scenes.
    static func remap(_ document: LyricDocument, segments: [Segment]) -> LyricDocument {
        guard !segments.isEmpty else { return document }
        var remapped = document
        remapped.lines = document.lines.compactMap { line in
            let match = segments.first { line.startMs >= $0.studioStartMs && line.startMs < $0.studioEndMs }
            guard let segment = match else {
                return nil
            }
            var copy = line
            copy.startMs = max(0, line.startMs + segment.videoOffsetMs)
            copy.endMs = max(copy.startMs, line.endMs + segment.videoOffsetMs)
            copy.words = line.words.map { word in
                var mappedWord = word
                mappedWord.startMs = max(0, word.startMs + segment.videoOffsetMs)
                mappedWord.endMs = max(mappedWord.startMs, word.endMs + segment.videoOffsetMs)
                return mappedWord
            }
            return copy
        }
        return remapped
    }
}
