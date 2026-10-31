import Foundation

// Apple's suggestion payload. Terms are completions the user may mean; songs are the top song matches.
struct CatalogSuggestions: Sendable, Equatable {
    var terms: [String]
    var songs: [Song]

    static func parse(_ data: Data) -> CatalogSuggestions {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [String: Any],
            let items = results["suggestions"] as? [[String: Any]]
        else { return CatalogSuggestions(terms: [], songs: []) }
        var terms: [String] = []
        var songItems: [[String: Any]] = []
        for item in items {
            switch item["kind"] as? String {
            case "terms":
                if let term = item["searchTerm"] as? String, !term.isEmpty { terms.append(term) }
            case "topResults":
                if let content = item["content"] as? [String: Any], content["type"] as? String == "songs" {
                    songItems.append(content)
                }
            default:
                continue
            }
        }
        return CatalogSuggestions(terms: terms, songs: Catalog.parseSongs(songItems))
    }
}
