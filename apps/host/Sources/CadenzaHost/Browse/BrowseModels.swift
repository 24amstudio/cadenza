import Foundation

struct BrowseRequest: Codable, Sendable, Equatable {
    var kind: String
    var id: String? = nil
    var song: SongIdentity? = nil
    // An artist named by its text, for a song whose identity the Host does not know.
    var artistName: String? = nil
}

// A song, or a link to an album, artist, or playlist that the Remote can browse next.
struct BrowseItem: Codable, Sendable, Equatable {
    var type: String
    var song: Song? = nil
    var id: String? = nil
    var title: String? = nil
    var subtitle: String? = nil
    var artworkUrl: String? = nil

    static func song(_ song: Song) -> BrowseItem { BrowseItem(type: "song", song: song) }
}

struct BrowseSection: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var items: [BrowseItem]
}

struct BrowseResult: Codable, Sendable, Equatable {
    static let maximumSections = 8
    static let maximumSongs = 100
    static let maximumAlbums = 60
    static let maximumPlaylists = 200
    static let maximumFrameBytes = 262_144
    // A frame this large still takes several seconds to cross a Bluetooth link, and holds that Remote's lane meanwhile.
    static let maximumBluetoothFrameBytes = 32_768

    var kind: String
    var id: String
    var title: String
    var subtitle: String? = nil
    var artworkUrl: String? = nil
    var detail: String? = nil
    var sections: [BrowseSection]

    var songs: [Song] { sections.flatMap { $0.items.compactMap(\.song) } }

    /// The result trimmed to the wire limits: section count, item counts per kind, text lengths, and frame size.
    /// A Bluetooth Remote gets a smaller frame without the optional `detail`, with whole items dropped, never cut.
    func bounded(forBluetooth: Bool = false) -> BrowseResult {
        let frameBytes = forBluetooth ? Self.maximumBluetoothFrameBytes : Self.maximumFrameBytes
        var result = self
        result.title = String(title.prefix(500))
        result.subtitle = subtitle.map { String($0.prefix(500)) }
        result.detail = forBluetooth ? nil : detail.map { String($0.prefix(500)) }
        result.sections = sections.prefix(Self.maximumSections).map { section in
            var section = section
            section.title = String(section.title.prefix(500))
            section.items = Array(section.items.prefix(Self.limit(for: section.items.first?.type)))
            for index in section.items.indices {
                section.items[index].title = section.items[index].title.map { String($0.prefix(500)) }
                section.items[index].subtitle = section.items[index].subtitle.map { String($0.prefix(500)) }
            }
            return section
        }
        while result.encodedSize > frameBytes,
            let index = result.sections.indices.max(by: {
                result.sections[$0].items.count < result.sections[$1].items.count
            }), !result.sections[index].items.isEmpty
        {
            let keep = result.sections[index].items.count / 2
            result.sections[index].items.removeLast(result.sections[index].items.count - keep)
        }
        return result
    }

    private static func limit(for type: String?) -> Int {
        switch type {
        case "song": maximumSongs
        case "playlist": maximumPlaylists
        default: maximumAlbums
        }
    }

    private var encodedSize: Int {
        let frame = Frame(
            type: "browse.result", requestId: "00000000-0000-0000-0000-000000000000", browse: .result(self))
        return (try? Wire.encode(frame).count) ?? Int.max
    }
}

// "browse" is a request when it arrives and a result when the Host answers, so one wire key carries either shape.
enum BrowsePayload: Codable, Sendable {
    case request(BrowseRequest)
    case result(BrowseResult)

    init(from decoder: Decoder) throws {
        self = .request(try BrowseRequest(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let request): try request.encode(to: encoder)
        case .result(let result): try result.encode(to: encoder)
        }
    }
}
