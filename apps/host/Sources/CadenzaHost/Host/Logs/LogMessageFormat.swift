import Foundation

/// Readable forms of a log message that holds JSON. Web and Remote traces store their details as JSON text, which is hard
/// to scan in a table, so the list shows a summary and the details page shows the structure.
enum LogMessageFormat {
    private static let summaryLimit = 160

    /// The JSON object or array in `text`, or nil when the text is not one.
    static func object(_ text: String) -> Any? {
        guard let first = text.first, first == "{" || first == "[", let data = text.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return value is [String: Any] || value is [Any] ? value : nil
    }

    /// One line of `key: value` pairs in key order, for the list. Nested values appear as compact JSON. Text that is
    /// not JSON is returned as written.
    static func summary(_ text: String) -> String {
        guard let value = object(text) else { return text }
        let line: String
        if let dictionary = value as? [String: Any] {
            line = dictionary.keys.sorted().map { "\($0): \(display(dictionary[$0] ?? NSNull()))" }.joined(
                separator: "  ")
        } else {
            line = (value as? [Any] ?? []).map(display).joined(separator: ", ")
        }
        return line.count > summaryLimit ? String(line.prefix(summaryLimit)) + "…" : line
    }

    /// The JSON indented with keys in order, for the details page. Nil when the text is not JSON.
    static func pretty(_ text: String) -> String? {
        guard let value = object(text),
            let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func display(_ value: Any) -> String {
        if let text = value as? String { return text }
        if value is NSNull { return "null" }
        if value is [String: Any] || value is [Any] {
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
                let text = String(data: data, encoding: .utf8)
            else { return "…" }
            return text
        }
        // A JSON boolean reaches here as an NSNumber, which would otherwise print as 1 or 0.
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        return "\(value)"
    }
}
