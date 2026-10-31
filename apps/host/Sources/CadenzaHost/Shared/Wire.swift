import Foundation

enum Wire {
    static let maximumMessageBytes = 1_048_576
    static let maximumCounter: Int64 = 9_007_199_254_740_991

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    static func isIdentifier(_ value: String) -> Bool {
        UUID(uuidString: value) != nil && value == value.lowercased()
    }

    static func validate(_ identity: SongIdentity) -> Bool {
        let pattern = identity.source == "catalog" ? "^[0-9]{1,20}$" : "^[0-9A-F]{16}$"
        return ["catalog", "library"].contains(identity.source)
            && identity.id.range(of: pattern, options: .regularExpression) != nil
    }

    static func validate(_ song: Song) -> Bool {
        validate(song.identity) && (1...500).contains(song.title.count) && (1...500).contains(song.artist.count)
            && song.album.count <= 500
    }
}
