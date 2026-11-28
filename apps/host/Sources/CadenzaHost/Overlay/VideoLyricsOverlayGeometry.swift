import CoreGraphics

/// Where the karaoke line sits relative to Music's video window. Accessibility measures from the top-left of the primary
/// display, while AppKit measures from the bottom-left, so the window frame is converted before it is used.
enum VideoLyricsOverlayGeometry {
    static func appKitFrame(accessibilityFrame frame: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryDisplayHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The bottom band of the video, where lyrics are read.
    static func lyricBand(in windowFrame: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX, y: windowFrame.minY, width: windowFrame.width, height: windowFrame.height * 0.28)
    }
}
