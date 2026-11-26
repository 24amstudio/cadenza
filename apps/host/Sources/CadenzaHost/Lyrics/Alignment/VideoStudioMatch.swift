/// Finds a music video's studio track so its timed lyrics can be used. When the video's length matches the studio
/// track within the fast-path tolerance, the studio timeline applies directly; otherwise the envelope aligner computes
/// the segment map from the studio preview and captured playback audio.
enum VideoStudioMatch {
    /// The first candidate with the video's title, an overlapping artist, and a length within the fast-path tolerance.
    static func pick(video: Song, candidates: [Song]) -> Song? {
        candidates.first { candidate in
            matchesIdentity(video: video, candidate: candidate)
                && lengthsMatch(studioMs: candidate.durationMs, videoMs: video.durationMs)
        }
    }

    /// Best matching studio candidate regardless of duration delta, preferring fast-path length matches first.
    static func pickBestCandidate(video: Song, candidates: [Song]) -> Song? {
        if let fastPath = pick(video: video, candidates: candidates) { return fastPath }
        return candidates.first { matchesIdentity(video: video, candidate: $0) }
    }

    static func matchesIdentity(video: Song, candidate: Song) -> Bool {
        candidate.source == "catalog"
            && candidate.mediaType != .musicVideo
            && titleKey(candidate.title) == titleKey(video.title)
            && artistsOverlap(candidate.artist, video.artist)
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
