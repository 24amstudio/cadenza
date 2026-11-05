import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CadenzaHost

struct ArtworkPreviewTests {
    @Test func aPreviewIsASmallJPEGOfTheCover() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 1_200, height: 1_200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_200))
        let image = try #require(context.makeImage())
        let source = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(source, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let preview = try ArtworkProvider.preview(of: source as Data)

        let decoded = try #require(CGImageSourceCreateWithData(preview as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        #expect(width <= 160)
        #expect(preview.starts(with: [0xFF, 0xD8]))
    }
}
