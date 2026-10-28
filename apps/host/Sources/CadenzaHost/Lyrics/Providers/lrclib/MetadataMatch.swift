import Foundation
enum LyricMatch {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    static func artistMatches(_ actual: String, expected: String) -> Bool {
        let expected = normalized(expected)
        return normalized(actual) == expected || actual.split(separator: ",").contains { normalized(String($0)) == expected }
    }
}
