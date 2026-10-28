import Foundation
import NaturalLanguage
import Translation

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
