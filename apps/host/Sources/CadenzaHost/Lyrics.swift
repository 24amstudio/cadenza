import Foundation
import FoundationXML
import NaturalLanguage
import Translation

actor Lyrics {
    private var cache: [String: LyricDocument] = [:]

    func document(song: Song, occurrence: String) async throws -> LyricDocument {
        let key = song.source + ":" + song.id
        if var known = cache[key] {
            known.occurrenceId = occurrence
            return known
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.apple.Music/fsCachedData", isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ).prefix(2_048)
        let files = candidates.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true, values.isSymbolicLink != true,
                let size = values.fileSize, size <= 4_194_304
            else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 > $1.2 }
        var bytes = 0
        for (url, size, _) in files {
            bytes += size
            if bytes > 33_554_432 { break }
            guard var data = try? Data(contentsOf: url) else { continue }
            while data.last == 0 { data.removeLast() }
            guard data.range(of: Data("ttmlLocalizations".utf8)) != nil,
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = root["data"] as? [[String: Any]]
            else { continue }
            for item in items where matches(item, song: song) {
                guard let relationships = item["relationships"] as? [String: Any] else { continue }
                for kind in ["syllable-lyrics", "lyrics"] {
                    guard let relationship = relationships[kind] as? [String: Any],
                        let records = relationship["data"] as? [[String: Any]],
                        let attributes = records.first?["attributes"] as? [String: Any],
                        let ttml = attributes["ttmlLocalizations"] as? String
                    else { continue }
                    let document = try TTMLDocument.parse(Data(ttml.utf8), occurrence: occurrence)
                    if cache.count >= 8 { cache.removeAll(keepingCapacity: true) }
                    cache[key] = document
                    return document
                }
            }
        }
        throw CadenzaError.failure(
            "lyrics_unavailable",
            "Timed lyrics are not in Music's cache yet. Open Music's lyrics pane and keep the song playing."
        )
    }

    func english(_ document: LyricDocument, song: Song) async -> LyricDocument {
        guard document.language?.hasPrefix("en") != true,
            document.lines.contains(where: { $0.translation == nil })
        else { return document }
        let translated = await EnglishTranslation.translate(document)
        if !Task.isCancelled { cache[song.source + ":" + song.id] = translated }
        return translated
    }

    private func matches(_ item: [String: Any], song: Song) -> Bool {
        if song.source == "catalog" { return item["id"] as? String == song.id }
        // A library persistent ID is not a catalog ID. Require an unambiguous metadata
        // match including duration, rather than treating one identifier as the other.
        guard let attributes = item["attributes"] as? [String: Any],
            attributes["name"] as? String == song.title,
            attributes["artistName"] as? String == song.artist,
            attributes["albumName"] as? String == song.album,
            let duration = (attributes["durationInMillis"] as? NSNumber)?.int64Value,
            let expected = song.durationMs, abs(duration - expected) < 1_000
        else { return false }
        return true
    }
}

final class TTMLDocument: NSObject, XMLParserDelegate {
    private var lines: [LyricLine] = []
    private var language: String?
    private var translationLanguage: String?
    private var translationTarget: String?
    private var translationText = ""
    private var translations: [String: String] = [:]
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
        for index in lines.indices {
            lines[index].translation = handler.translations[lines[index].id]
            if lines[index].endMs <= lines[index].startMs {
                lines[index].endMs = index + 1 < lines.count ? lines[index + 1].startMs : lines[index].startMs + 10_000
            }
        }
        guard !lines.isEmpty else {
            throw CadenzaError.failure("lyrics_unavailable", "No supported line timings were found.")
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
        if name == "p", metadataDepth == 0, let start = Self.milliseconds(attributes["begin"]) {
            paragraph = LyricLine(
                id: attributes["itunes:key"] ?? attributes["xml:id"] ?? "line-\(lines.count)",
                text: "", startMs: start, endMs: Self.milliseconds(attributes["end"]) ?? start
            )
            paragraphDepth = depth
        }
        if name == "br", paragraph != nil { paragraph?.text += "\n" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if translationTarget != nil { translationText += string }
        if paragraph != nil { paragraph?.text += string }
        if (paragraph?.text.utf8.count ?? 0) > 20_000 || translationText.utf8.count > 20_000 {
            failure = "A lyric line is too large."
            parser.abortParsing()
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "p", paragraphDepth == depth, var line = paragraph {
            line.text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

@MainActor
enum EnglishTranslation {
    static func translate(_ document: LyricDocument) async -> LyricDocument {
        var document = document
        document.issue = nil
        let text = document.lines.prefix(12).map(\.text).joined(separator: "\n")
        let detected = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
        guard let language = document.language ?? detected, !language.hasPrefix("en") else { return document }
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: language), target: Locale.Language(identifier: "en")
        )
        let supplied = ["apple", "apple_and_machine"].contains(document.translationSource)
        var changed = false
        do {
            for index in document.lines.indices where document.lines[index].translation == nil {
                try Task.checkCancellation()
                let result = try await session.translate(document.lines[index].text)
                document.lines[index].translation = result.targetText
                changed = true
            }
        } catch {
            document.issue =
                "English translation needs an installed language pair. Prepare it in Cadenza Host settings."
        }
        if changed { document.translationSource = supplied ? "apple_and_machine" : "machine" }
        document.revision = identifier()
        return document
    }
}
