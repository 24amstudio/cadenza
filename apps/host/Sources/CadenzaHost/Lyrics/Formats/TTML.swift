import Foundation

final class TTMLDocument: NSObject, XMLParserDelegate {
    private var lines: [LyricLine] = []
    private var language: String?
    private var translationLanguage: String?
    private var translationTarget: String?
    private var translationText = ""
    private var translations: [String: String] = [:]
    private struct WordCapture {
        var depth: Int
        var startMs: Int64
        var endMs: Int64
        var text: String
    }
    private var wordCaptures: [WordCapture] = []
    private var metadataDepth = 0
    private var paragraph: LyricLine?
    private var paragraphDepth = 0
    private var depth = 0
    private var failure: String?

    static func parse(_ data: Data, occurrence: String) throws -> LyricDocument {
        guard data.count <= 1_048_576 else {
            throw CadenzaError.failure("lyrics_unavailable", "The lyric document is too large.")
        }
        let text = String(decoding: data, as: UTF8.self)
        guard !text.localizedCaseInsensitiveContains("<!DOCTYPE"),
            !text.localizedCaseInsensitiveContains("<!ENTITY")
        else {
            throw CadenzaError.failure("lyrics_unavailable", "Unsafe XML declarations are not allowed in lyrics.")
        }
        let handler = TTMLDocument()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = handler
        guard parser.parse(), handler.failure == nil else {
            throw CadenzaError.failure(
                "lyrics_unavailable", handler.failure ?? "Music's lyric format could not be read.")
        }
        var lines = handler.lines.sorted { $0.startMs < $1.startMs }
        guard Set(lines.map(\.id)).count == lines.count,
            lines.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 128 })
        else {
            throw CadenzaError.failure(
                "lyrics_unavailable", "Music's lyric document contains missing, repeated, or oversized line identities."
            )
        }
        for index in lines.indices where lines[index].endMs <= lines[index].startMs {
            let nextStart = index + 1 < lines.count ? lines[index + 1].startMs : lines[index].startMs + 4_000
            lines[index].endMs = max(lines[index].startMs + 1, nextStart)
        }
        for index in lines.indices {
            lines[index].translation = handler.translations[lines[index].id]
            lines[index].romanized = lines[index].text.applyingTransform(.toLatin, reverse: false)
                .flatMap { $0 == lines[index].text ? nil : $0 }
        }
        guard !lines.isEmpty else {
            throw CadenzaError.failure("lyrics_unavailable", "No lyric lines were found.")
        }
        let supplied = lines.contains { $0.translation != nil }
        return LyricDocument(
            occurrenceId: occurrence, revision: identifier(), language: handler.language,
            translationSource: supplied ? "apple" : "none", lines: lines
        )
    }

    static func milliseconds(_ text: String?) -> Int64? {
        guard let text else { return nil }
        if text.hasSuffix("ms"), let value = Double(text.dropLast(2)), value.isFinite, value >= 0, value < 86_400_000 {
            return Int64(value.rounded())
        }
        if text.hasSuffix("s"), let value = Double(text.dropLast()), value.isFinite, value >= 0, value < 86_400 {
            return Int64((value * 1_000).rounded())
        }
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        let parts = fields.compactMap { Double($0) }
        guard (2...3).contains(parts.count), fields.count == parts.count,
            parts.allSatisfy({ $0.isFinite && $0 >= 0 }),
            (parts.last ?? 60) < 60, parts.count != 3 || parts[1] < 60
        else { return nil }
        let seconds = parts.reversed().enumerated().reduce(0.0) { $0 + $1.element * pow(60, Double($1.offset)) }
        guard seconds < 86_400 else { return nil }
        return Int64((seconds * 1_000).rounded())
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes: [String: String]
    ) {
        depth += 1
        if depth > 64 || lines.count >= 2_000 {
            failure = "The lyric document exceeds its structural limit."
            parser.abortParsing()
            return
        }
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "tt" { language = attributes["xml:lang"] }
        if name == "metadata" { metadataDepth = depth }
        if name == "translation" {
            translationLanguage = attributes["type"] == "subtitle" ? attributes["xml:lang"] : nil
        }
        if name == "text", translationLanguage?.hasPrefix("en") == true {
            translationTarget = attributes["for"]
            translationText = ""
        }
        if name == "p", metadataDepth == 0 {
            paragraph = LyricLine(
                id: attributes["itunes:key"] ?? attributes["xml:id"] ?? "line-\(lines.count)",
                text: "", startMs: Self.milliseconds(attributes["begin"]) ?? 0,
                endMs: Self.milliseconds(attributes["end"]) ?? 0
            )
            paragraphDepth = depth
        }
        if name == "span", paragraph != nil,
            let start = Self.milliseconds(attributes["begin"]),
            let end = Self.milliseconds(attributes["end"]), end >= start
        {
            guard wordCaptures.count < 1_000 else {
                failure = "A lyric line contains too many timed words."
                parser.abortParsing()
                return
            }
            wordCaptures.append(WordCapture(depth: depth, startMs: start, endMs: end, text: ""))
        }
        if name == "br", paragraph != nil { paragraph?.text += "\n" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if translationTarget != nil { translationText += string }
        if paragraph != nil { paragraph?.text += string }
        if !wordCaptures.isEmpty { wordCaptures[wordCaptures.count - 1].text += string }
        if wordCaptures.isEmpty, string.allSatisfy(\.isWhitespace), var line = paragraph,
            let last = line.words.indices.last
        {
            line.words[last].text += " "
            paragraph = line
        }
        if (paragraph?.text.utf8.count ?? 0) > 20_000 || translationText.utf8.count > 20_000 {
            failure = "A lyric line is too large."
            parser.abortParsing()
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "span", let capture = wordCaptures.last, capture.depth == depth {
            wordCaptures.removeLast()
            let hasTrailingSpace = capture.text.last?.isWhitespace == true
            let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                paragraph?.words.append(
                    LyricWord(
                        text: text + (hasTrailingSpace ? " " : ""),
                        startMs: capture.startMs,
                        endMs: capture.endMs))
            }
        }
        if name == "p", paragraphDepth == depth, var line = paragraph {
            line.text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.words.isEmpty {
                let wordStart = line.words.map(\.startMs).min() ?? line.startMs
                let wordEnd = line.words.map(\.endMs).max() ?? line.endMs
                if line.startMs == 0 { line.startMs = wordStart }
                if line.endMs <= line.startMs { line.endMs = wordEnd }
            }
            if !line.text.isEmpty { lines.append(line) }
            paragraph = nil
        }
        if name == "text", let target = translationTarget {
            translations[target] = translationText.trimmingCharacters(in: .whitespacesAndNewlines)
            translationTarget = nil
        }
        if name == "translation" { translationLanguage = nil }
        if name == "metadata", depth == metadataDepth { metadataDepth = 0 }
        depth -= 1
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        failure = "External XML entities are not allowed."
        parser.abortParsing()
        return nil
    }
}
