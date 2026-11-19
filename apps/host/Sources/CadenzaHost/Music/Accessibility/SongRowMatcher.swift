import Foundation

/// Scores how well the text of a Music row describes a requested song. Pure, so row matching is testable without Music.
enum SongRowMatcher {
    /// A row below this score is not the requested song. An exact title alone is enough for a catalog song, because
    /// Music's own link already named it. A library song needs its artist, album, duration or selection as well.
    static let acceptance = 70

    private static let ellipses = ["\u{2026}", "..."]
    private static let separators = CharacterSet(charactersIn: ",\u{2014}\u{00B7}|\n")
    private static let decoration =
        #"(feat|featuring|ft|with|remaster|deluxe|bonus|explicit|clean|mono|stereo|single|expanded|anniversary|album version|from )"#

    /// Case, diacritic, width and punctuation insensitive form. Music draws an explicit badge as U+FFFC.
    static func normalize(_ value: String) -> String {
        let kept = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        let folded =
            value
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        let spaced = String(folded.unicodeScalars.map { kept.contains($0) ? Character($0) : " " })
        return spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The title without release decorations such as "(feat. X)", "- Remastered 2011" or "[Deluxe]". Live, remix and
    /// acoustic markers are kept, because they name a different recording.
    static func undecorated(_ title: String) -> String {
        var text = title
        let bracketed = #"[\(\[][^\)\]]*"# + decoration + #"[^\)\]]*[\)\]]"#
        text = text.replacingOccurrences(of: bracketed, with: " ", options: [.regularExpression, .caseInsensitive])
        let suffix = #"\s[-–—]\s[^-–—]*"# + decoration + #".*$"#
        text = text.replacingOccurrences(of: suffix, with: "", options: [.regularExpression, .caseInsensitive])
        let featuring = #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#
        text = text.replacingOccurrences(of: featuring, with: "", options: [.regularExpression, .caseInsensitive])
        return normalize(text)
    }

    static func titleScore(_ wanted: String, in text: String) -> Int {
        let target = normalize(wanted)
        let candidate = normalize(text)
        guard !target.isEmpty, !candidate.isEmpty else { return 0 }
        if target == candidate { return 60 }
        let plain = undecorated(wanted)
        if !plain.isEmpty, plain == undecorated(text) { return 45 }
        // Music truncates long labels with an ellipsis, so the visible prefix is compared.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ellipsis = ellipses.first(where: { trimmed.hasSuffix($0) }) {
            let prefix = normalize(String(trimmed.dropLast(ellipsis.count)))
            if prefix.count >= 4, target.hasPrefix(prefix) || plain.hasPrefix(prefix) { return 40 }
        }
        // A combined label reads "Title, Artist, Album". Only labels with a separator are split.
        if text.rangeOfCharacter(from: separators) != nil {
            let parts = text.components(separatedBy: separators).map(normalize)
            if parts.contains(target) { return 55 }
            if candidate.hasPrefix(target + " ") { return 50 }
        }
        return 0
    }

    static func artistScore(_ artist: String, in texts: [String]) -> Int {
        let wanted = normalize(artist)
        guard !wanted.isEmpty else { return 0 }
        let primary = primaryArtist(artist)
        var best = 0
        for text in texts {
            // The Up Next and album rows read "Artist \u{2014} Album", so the first component is the artist.
            let leading = normalize(text.components(separatedBy: " \u{2014} ").first ?? text)
            if leading == wanted || normalize(text) == wanted { return 30 }
            if !primary.isEmpty, containsWords(normalize(text), primary) { best = max(best, 25) }
        }
        return best
    }

    static func albumScore(_ album: String, in texts: [String]) -> Int {
        let wanted = normalize(album)
        guard !wanted.isEmpty else { return 0 }
        return texts.contains { containsWords(normalize($0), wanted) } ? 10 : 0
    }

    static func durationScore(_ durationMs: Int64?, in texts: [String]) -> Int {
        guard let durationMs, durationMs > 0 else { return 0 }
        let seconds = Int((Double(durationMs) / 1_000).rounded())
        let shown = Set([seconds - 1, seconds, seconds + 1].map { String(format: "%d:%02d", $0 / 60, $0 % 60) })
        return texts.contains { shown.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ? 10 : 0
    }

    /// 0 means the row is not this song. A deep link or identifier match is definitive.
    static func score(_ song: Song, texts: [String], linked: Bool, selected: Bool) -> Int {
        if linked { return 1_000 }
        let title = texts.map { titleScore(song.title, in: $0) }.max() ?? 0
        guard title > 0 else { return 0 }
        var total = title + artistScore(song.artist, in: texts) + albumScore(song.album, in: texts)
        total += durationScore(song.durationMs, in: texts)
        if selected { total += 15 }
        if song.source == "catalog" { total += 10 }
        return total
    }

    /// The best acceptable row. Equal scores keep the earlier row, which is the one nearer the top of the page.
    static func best<Row>(_ rows: [(row: Row, score: Int)]) -> Row? {
        var winner: (row: Row, score: Int)?
        for candidate in rows where candidate.score >= acceptance && candidate.score > (winner?.score ?? 0) {
            winner = candidate
        }
        return winner?.row
    }

    private static func primaryArtist(_ artist: String) -> String {
        let first = artist.components(separatedBy: [",", "&"]).first ?? artist
        let name = first.components(separatedBy: " feat").first ?? first
        return normalize(name)
    }

    private static func containsWords(_ text: String, _ words: String) -> Bool {
        text == words || (" " + text + " ").contains(" " + words + " ")
    }
}
