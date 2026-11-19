import Foundation

/// A defensive pass over log text before it is shown, copied or exported. The logger never writes credentials on
/// purpose, so this catches a value that slipped into a message or metadata by mistake.
enum LogRedaction {
    static let placeholder = "[redacted]"

    private static let sensitiveKeyValue = regex(
        #"(["']?[A-Za-z0-9_.-]*(?:token|secret|password|passcode|credential|authorization|api[_-]?key|private[_-]?key|pairing[_-]?(?:code|pin))[A-Za-z0-9_.-]*["']?\s*[:=]\s*)("[^"]*"|'[^']*'|(?:(?:Bearer|Basic)\s+)?[^\s,;&}\]]+)"#
    )
    private static let bearer = regex(#"(\bBearer\s+)[A-Za-z0-9._~+/=-]{8,}"#)
    private static let longToken = regex(#"(?<![A-Za-z0-9_+=-])[A-Za-z0-9_+=-]{40,}(?![A-Za-z0-9_+=-])"#)

    static func redact(_ text: String) -> String {
        var result = replace(sensitiveKeyValue, in: text, with: "$1\"\(placeholder)\"")
        result = replace(bearer, in: result, with: "$1\(placeholder)")
        // A long run of letters and digits is a token in all but a few cases, so it is hidden unless it reads as a
        // plain word, such as a long identifier made only of letters.
        let range = NSRange(result.startIndex..., in: result)
        for match in longToken.matches(in: result, range: range).reversed() {
            guard let span = Range(match.range, in: result) else { continue }
            let candidate = result[span]
            guard candidate.contains(where: \.isNumber), candidate.contains(where: \.isLetter) else { continue }
            result.replaceSubrange(span, with: placeholder)
        }
        return result
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) } catch {
            preconditionFailure("Invalid log redaction pattern: \(error)")
        }
    }
}
