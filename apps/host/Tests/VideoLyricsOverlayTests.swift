import CoreGraphics
import Foundation
import Testing

@testable import CadenzaHost

struct VideoLyricsOverlayTests {
    @Test func aWindowMeasuredFromTheTopLeftLandsAtTheSameSpotFromTheBottomLeft() {
        let window = CGRect(x: 100, y: 50, width: 1470, height: 923)

        let appKit = VideoLyricsOverlayGeometry.appKitFrame(accessibilityFrame: window, primaryDisplayHeight: 1080)

        #expect(appKit == CGRect(x: 100, y: 107, width: 1470, height: 923))
        #expect(VideoLyricsOverlayGeometry.lyricBand(in: appKit).height == 923 * 0.28)
        #expect(VideoLyricsOverlayGeometry.lyricBand(in: appKit).minY == 107)
    }

    @Test func theLyricsShowOnlyWhileMusicIsFrontmostWithAVideoAndAWindow() {
        let music = VideoLyricsVisibility.musicBundleIdentifier

        #expect(
            VideoLyricsVisibility.shouldShow(
                frontmostBundleIdentifier: music, videoIsCurrent: true, windowIsKnown: true))
        #expect(
            !VideoLyricsVisibility.shouldShow(
                frontmostBundleIdentifier: "com.apple.finder", videoIsCurrent: true, windowIsKnown: true))
        #expect(
            !VideoLyricsVisibility.shouldShow(
                frontmostBundleIdentifier: music, videoIsCurrent: false, windowIsKnown: true))
        #expect(
            !VideoLyricsVisibility.shouldShow(
                frontmostBundleIdentifier: music, videoIsCurrent: true, windowIsKnown: false))
    }

    @Test func theActiveLineIsTheLastOneThatHasStarted() {
        let lines = [
            LyricLine(id: "a", text: "first", startMs: 0, endMs: 1_000),
            LyricLine(id: "b", text: "second", startMs: 1_000, endMs: 2_000),
            LyricLine(id: "c", text: "third", startMs: 2_000, endMs: 3_000),
        ]

        #expect(ActiveLyricLine.at(1_500, in: lines)?.text == "second")
        #expect(ActiveLyricLine.at(2_000, in: lines)?.text == "third")
        #expect(ActiveLyricLine.at(-1, in: lines) == nil)
    }

    @Test func theCastLineCarriesTheLineAfterIt() {
        let lines = [
            LyricLine(id: "a", text: "first", startMs: 0, endMs: 1_000),
            LyricLine(id: "b", text: "second", startMs: 1_000, endMs: 2_000),
            LyricLine(id: "c", text: "third", startMs: 2_000, endMs: 3_000),
        ]

        let during = ActiveLyricLine.window(at: 1_500, in: lines)
        let before = ActiveLyricLine.window(at: -1, in: lines)

        #expect(during.current?.text == "second")
        #expect(during.next?.text == "third")
        #expect(before.current == nil)
        #expect(before.next?.text == "first")
    }
}
