import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CadenzaHost

struct MusicQualityTests {
    @Test func badgeLabelsMapToTheTiersTheRemoteDisplays() {
        #expect(MusicQuality.tier(forBadge: "Lossless") == "lossless")
        #expect(MusicQuality.tier(forBadge: "Hi-Res Lossless") == "hi_res_lossless")
        #expect(MusicQuality.tier(forBadge: "Dolby Atmos") == "dolby_atmos")
        #expect(MusicQuality.tier(forBadge: "") == "unknown")
    }
}

@MainActor
struct ArtworkAddressTests {
    @Test func onlyAppleCdnAndCurrentMusicArtworkAddressesAreServable() {
        let occurrence = UUID().uuidString.lowercased()
        #expect(ArtworkProvider.isServableURL(ArtworkProvider.localArtworkURL(occurrenceId: occurrence)))
        #expect(!ArtworkProvider.isServableURL("cadenza-music-artwork://not-a-track"))
        #expect(!ArtworkProvider.isServableURL("https://example.com/cover.jpg"))
        #expect(ArtworkProvider.isServableURL("https://is1-ssl.mzstatic.com/image/thumb/cover.jpg/400x400bb.jpg"))
    }

    @Test func musicArtworkIsScaledBelowTheTransferLimitAndServedFromTheCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        let database = try Database(url: directory.appendingPathComponent("cadence.sqlite"))
        let cache = try HostCache(
            database: database, mediaDirectory: directory.appendingPathComponent("media", isDirectory: true),
            limitBytes: 64 * 1_048_576)
        let provider = ArtworkProvider(cache: cache)

        let url = try provider.storeMusicArtwork(solidPNG(side: 1_200), occurrenceId: UUID().uuidString.lowercased())
        let served = try #require(try await provider.data(for: url))
        #expect(served.count <= 524_288)
        let source = try #require(CGImageSourceCreateWithData(served as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? NSNumber)
        #expect(width.intValue <= 600)
    }

    private func solidPNG(side: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return encoded as Data
    }
}

struct ArtworkRequestValidationTests {
    @Test func aRemoteMayAskForItsPlayingArtworkButNotForAnArbitraryAddress() throws {
        let occurrence = UUID().uuidString.lowercased()
        let local =
            #"{"version":1,"type":"artwork.get","request_id":"\#(occurrence)","artwork_url":"cadenza-music-artwork://\#(occurrence)"}"#
        #expect(try ProtocolValidation.decode(Data(local.utf8)).artworkUrl == "cadenza-music-artwork://\(occurrence)")

        let arbitrary =
            #"{"version":1,"type":"artwork.get","request_id":"\#(occurrence)","artwork_url":"https://example.com/cover.jpg"}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(arbitrary.utf8)) }
    }
}
