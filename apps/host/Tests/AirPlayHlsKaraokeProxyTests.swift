import Foundation
import Testing

@testable import CadenzaHost

struct AirPlayHlsKaraokeProxyTests {
    @Test func webVTTFormatsTimedLinesTranslationsAndOffsets() {
        let doc = LyricDocument(
            occurrenceId: "occ-1",
            revision: "rev-1",
            language: "ja",
            translationSource: "apple",
            lines: [
                LyricLine(id: "1", text: "First line", startMs: 1_000, endMs: 3_500, translation: "Line one"),
                LyricLine(id: "2", text: "Second line", startMs: 4_000, endMs: 4_000),
            ])

        let vtt = WebVTTKaraoke.render(document: doc, userOffsetMs: 500, lipSyncOffsetMs: -100)

        #expect(vtt.hasPrefix("WEBVTT\n\n"))
        #expect(vtt.contains("00:00:01.400 --> 00:00:03.900\nFirst line\nLine one"))
        #expect(vtt.contains("00:00:04.400 --> 00:00:08.400\nSecond line"))
    }

    @Test func injectsWebVTTSubtitlesAndResolvesRelativeCDNPathsWithoutProxyingSegments() throws {
        let base = try #require(URL(string: "https://mvod.itunes.apple.com/itunes-assets/HLSVideo/v4/master.m3u8"))
        let master = [
            "#EXTM3U",
            "#EXT-X-VERSION:6",
            "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aac\",NAME=\"Audio\",URI=\"audio/eng.m3u8\"",
            "#EXT-X-STREAM-INF:BANDWIDTH=3500000,CODECS=\"avc1.640028\",AUDIO=\"aac\"",
            "video/1080p.m3u8",
        ].joined(separator: "\n")

        let proxied = AirPlayHlsKaraokeProxy.injectSubtitles(
            masterPlaylist: master,
            baseURL: base,
            subtitlesPlaylistURL: "http://192.168.1.20:9100/airplay/karaoke/s1/subs.m3u8")

        #expect(
            proxied.contains(
                "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"cadenza-karaoke\",NAME=\"Cadenza Lyrics\",DEFAULT=YES,AUTOSELECT=YES,FORCED=YES,LANGUAGE=\"en\",URI=\"http://192.168.1.20:9100/airplay/karaoke/s1/subs.m3u8\""
            ))
        #expect(proxied.contains("URI=\"https://mvod.itunes.apple.com/itunes-assets/HLSVideo/v4/audio/eng.m3u8\""))
        #expect(proxied.contains("https://mvod.itunes.apple.com/itunes-assets/HLSVideo/v4/video/1080p.m3u8"))
        #expect(proxied.contains("SUBTITLES=\"cadenza-karaoke\""))
    }

    @Test func parsesFairPlayAndWidevineAssetsFromWebPlaybackJSON() {
        let json = Data(
            #"""
            {
              "songList": [{
                "assets": [
                  {
                    "flavor": "hls-fairplay",
                    "URL": "https://mvod.itunes.apple.com/fairplay/master.m3u8"
                  },
                  {
                    "flavor": "hls-widevine",
                    "URL": "https://mvod.itunes.apple.com/widevine/master.m3u8",
                    "widevine-license-url": "https://play.itunes.apple.com/WebObjects/MZPlay.woa/wa/widevineLicense",
                    "widevine-cert-url": "https://play.itunes.apple.com/widevine/cert.bin"
                  },
                  {
                    "flavor": "hls-fairplay",
                    "URL": "https://untrusted.example.com/evil.m3u8"
                  }
                ]
              }]
            }
            """#.utf8)

        let assets = AppleWebPlayback.parseAssets(from: json)

        #expect(assets.count == 2)
        #expect(assets[0].flavor == "hls-fairplay")
        #expect(assets[1].flavor == "hls-widevine")
        #expect(assets[1].licenseServerURL?.host == "play.itunes.apple.com")
        #expect(assets[1].certURL?.host == "play.itunes.apple.com")
    }
}
