import Foundation

struct LyricWord: Codable, Sendable {
    var text: String
    var startMs: Int64
    var endMs: Int64
}

struct LyricLine: Codable, Identifiable, Sendable {
    var id: String
    var text: String
    var startMs: Int64
    var endMs: Int64
    var words: [LyricWord] = []
    var romanized: String? = nil
    var translation: String? = nil
    // "end" places a second singer's line at the end; absent means start.
    var align: String? = nil
}

struct LyricDocument: Codable, Sendable {
    var occurrenceId: String
    var revision: String
    var language: String?
    var translationSource: String
    var lines: [LyricLine]
    var issue: String? = nil
    var source: String = "apple_music"
    // The nudge the person saved for this track, in milliseconds. Remotes start their nudge from it.
    var userOffsetMs: Int? = nil

    enum CodingKeys: String, CodingKey {
        case occurrenceId, revision, language, translationSource, lines, issue, source, userOffsetMs
    }

    init(
        occurrenceId: String, revision: String, language: String?, translationSource: String,
        lines: [LyricLine], issue: String? = nil, source: String = "apple_music", userOffsetMs: Int? = nil
    ) {
        self.occurrenceId = occurrenceId
        self.revision = revision
        self.language = language
        self.translationSource = translationSource
        self.lines = lines
        self.issue = issue
        self.source = source
        self.userOffsetMs = userOffsetMs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        occurrenceId = try values.decode(String.self, forKey: .occurrenceId)
        revision = try values.decode(String.self, forKey: .revision)
        language = try values.decodeIfPresent(String.self, forKey: .language)
        translationSource = try values.decode(String.self, forKey: .translationSource)
        lines = try values.decode([LyricLine].self, forKey: .lines)
        issue = try values.decodeIfPresent(String.self, forKey: .issue)
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "apple_music"
        userOffsetMs = try values.decodeIfPresent(Int.self, forKey: .userOffsetMs)
    }
}
