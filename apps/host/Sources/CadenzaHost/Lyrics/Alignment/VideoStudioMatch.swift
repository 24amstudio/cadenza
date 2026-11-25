/// Finds a music video's studio track, so its timed lyrics can be used when the two have the same length. A video that
/// is longer or shorter than the studio track by more than the aligner's fast-path tolerance is not matched: its lyrics
/// would be misplaced, and the segment map that would correct them needs the video's audio.
enum VideoStudioMatch {
    /// The first candidate with the video's title, an overlapping artist, and a length within the fast-path tolerance.
    static func pick(video: Song, candidates: [Song]) -> Song? {
        candidates.first { candidate in
            candidate.source == "catalog"
                && titleKey(candidate.title) == titleKey(video.title)
                && artistsOverlap(candidate.artist, video.artist)
                && lengthsMatch(studioMs: candidate.durationMs, videoMs: video.durationMs)
        }
    }

    static func lengthsMatch(studioMs: Int64?, videoMs: Int64?) -> Bool {
        guard let studioMs, let videoMs else { return false }
        return !VideoLyricAligner.needsAlignment(studioDurationMs: studioMs, videoDurationMs: videoMs)
    }

    // Videos often add a featured artist or a version name in brackets, which the studio title does not carry.
    static func titleKey(_ title: String) -> String {
        normalized(title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression))
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // Music often credits a video with the featured artists too, so one name containing the other counts as a match.
    static func artistsOverlap(_ first: String, _ second: String) -> Bool {
        let left = normalized(first)
        let right = normalized(second)
        return !left.isEmpty && !right.isEmpty && (left.contains(right) || right.contains(left))
    }
}
