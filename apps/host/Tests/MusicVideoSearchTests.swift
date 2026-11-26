import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct MusicVideoSearchTests {
    @Test func aLibraryMusicVideoCannotBeResolvedAsASong() async throws {
        let bridge = MusicBridge()
        bridge.scriptRunner = { _ in
            Data(
                #"{"source":"library","id":"0123456789ABCDEF","title":"Akad","artist":"Payung Teduh","album":"","media_type":"musicVideo"}"#
                    .utf8)
        }

        do {
            _ = try await bridge.resolve(SongIdentity(source: "library", id: "0123456789ABCDEF"))
            Issue.record("A library music video was resolved as a song.")
        } catch let error as CadenzaError {
            #expect(error.code == "unsupported_media")
        }
    }

    @Test func aVideoFoundBySearchCannotBeResolvedAsASong() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let catalog = Catalog(credentials: CredentialFile(url: url))
        let video = Song(source: "catalog", id: "1440", title: "Akad", artist: "Payung Teduh", mediaType: .musicVideo)
        _ = await catalog.remember([video])

        do {
            _ = try await catalog.resolve(SongIdentity(source: "catalog", id: "1440"))
            Issue.record("A music video was resolved as a song.")
        } catch let error as CadenzaError {
            #expect(error.code == "unsupported_media")
        }
    }

    @Test func theMediaTypeIsAddedOnlyForVideosSoOlderRemotesStillDecodeSongs() throws {
        let legacy = try Wire.decode(
            Song.self, from: Data(#"{"source":"catalog","id":"1","title":"T","artist":"A","album":""}"#.utf8))
        #expect(legacy.mediaType == nil)

        let video = Song(source: "catalog", id: "1440", title: "T", artist: "A", mediaType: .musicVideo)
        let encoded = try JSONSerialization.jsonObject(with: Wire.encode(video)) as? [String: Any]
        #expect(encoded?["media_type"] as? String == "musicVideo")
    }
}
