import Foundation

enum LRCParser {
    static func document(_ record: LRCLIBRecord, occurrence: String) throws -> LyricDocument? {
        if record.instrumental == true { return nil }
        if let synced = record.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = parseTimed(synced, durationMs: record.duration.map { Int64($0 * 1_000) })
            guard !lines.isEmpty else { return nil }
            return LyricDocument(
                occurrenceId: occurrence, revision: identifier(), language: nil, translationSource: "none",
                lines: lines, issue: nil, source: "lrclib")
        }
        guard let plain = record.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let lines = plain.split(whereSeparator: \.isNewline).enumerated().map { index, text in
            Self.line(
                id: "lrclib-\(index)", text: String(text).trimmingCharacters(in: .whitespaces), startMs: 0, endMs: 0)
        }.filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { return nil }
        return LyricDocument(
            occurrenceId: occurrence, revision: identifier(), language: nil, translationSource: "original",
            lines: lines, issue: nil, source: "lrclib")
    }

    private static func parseTimed(_ text: String, durationMs: Int64?) -> [LyricLine] {
        var parsed: [(Int64, String, [LyricWord])] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let matches = lineMatches(in: line)
            guard let first = matches.first, let range = Range(first.range, in: line),
                let start = timestamp(String(line[range]))
            else { continue }
            let content = String(line[range.upperBound...])
                .replacingOccurrences(
                    of: #"\[\d{1,3}:\d{2}(?:\.\d{1,3})?\]"#, with: "", options: .regularExpression
                )
                .trimmingCharacters(in: .whitespaces)
            let words = parseWords(content, lineStart: start)
            let cleaned =
                words.isEmpty
                ? content.replacingOccurrences(
                    of: #"<\d{1,3}:\d{2}(?:\.\d{1,3})?>"#, with: "", options: .regularExpression)
                : words.map(\.text).joined(separator: " ")
            if !cleaned.isEmpty { parsed.append((start, cleaned, words)) }
            for extra in matches.dropFirst() {
                guard let extraRange = Range(extra.range, in: line),
                    let extraStart = timestamp(String(line[extraRange]))
                else { continue }
                if !cleaned.isEmpty { parsed.append((extraStart, cleaned, words)) }
            }
        }
        let sorted = parsed.sorted { $0.0 < $1.0 }
        return sorted.enumerated().map { index, item in
            let end = index + 1 < sorted.count ? sorted[index + 1].0 : (durationMs ?? item.0 + 4_000)
            var words = item.2
            if let last = words.indices.last { words[last].endMs = max(words[last].endMs, end) }
            return line(
                id: "lrclib-\(index)", text: item.1, startMs: item.0, endMs: max(item.0, end), words: words)
        }
    }

    private static func line(
        id: String, text: String, startMs: Int64, endMs: Int64, words: [LyricWord] = []) -> LyricLine {
        let romanized = text.applyingTransform(.toLatin, reverse: false).flatMap { $0 == text ? nil : $0 }
        return LyricLine(
            id: id, text: text, startMs: startMs, endMs: endMs, words: words, romanized: romanized)
    }

    private static func parseWords(_ text: String, lineStart: Int64) -> [LyricWord] {
        let matches = wordMatches(in: text)
        guard !matches.isEmpty else { return [] }
        return matches.enumerated().compactMap { index, match in
            guard let timestampRange = Range(match.range, in: text), let start = timestamp(String(text[timestampRange]))
            else { return nil }
            let next =
                index + 1 < matches.count
                ? timestamp(String(text[Range(matches[index + 1].range, in: text)!]))
                : nil
            let end = next ?? start + 500
            let upper =
                index + 1 < matches.count ? Range(matches[index + 1].range, in: text)!.lowerBound : text.endIndex
            let value = String(text[timestampRange.upperBound..<upper]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            return LyricWord(text: value, startMs: max(lineStart, start), endMs: max(start, end))
        }
    }

    private static func timestamp(_ value: String) -> Int64? {
        let numbers = value.filter { $0.isNumber || $0 == ":" || $0 == "." }.split(separator: ":")
        guard numbers.count == 2, let minutes = Int64(numbers[0]), let seconds = Double(numbers[1]), seconds < 60 else {
            return nil
        }
        return minutes * 60_000 + Int64((seconds * 1_000).rounded())
    }

    private static func lineMatches(in text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]"#))?.matches(
            in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }

    private static func wordMatches(in text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?>"#))?.matches(
            in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
}
