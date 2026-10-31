import Foundation
import Testing

@testable import CadenzaHost

struct ProtocolTests {
    private let id = "00000000-0000-4000-8000-000000000001"

    @Test func commandRoundTripPreservesExplicitNullGuards() throws {
        var command = Frame(type: "command")
        command.commandId = id
        command.hostEpoch = id
        command.expectedRevision = 0
        command.expiresAtHostMs = 900
        command.action = CommandAction(kind: "queue.play_now", song: SongIdentity(source: "catalog", id: "100"))
        let encoded = try Wire.encode(command)
        let decoded = try ProtocolValidation.decode(encoded)
        #expect(decoded.action?.song?.id == "100")
        #expect(decoded.action?.occurrenceId == nil)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let action = try #require(object["action"] as? [String: Any])
        #expect(action["occurrence_id"] is NSNull)
    }

    @Test func hostUpdateRequestsAcceptOnlyCheckAndInstall() throws {
        let check = #"{"version":1,"type":"host.update","request_id":"\#(id)","update_action":"check"}"#
        #expect(try ProtocolValidation.decode(Data(check.utf8)).updateAction == "check")
        let download = check.replacingOccurrences(of: #""check""#, with: #""download""#)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(download.utf8)) }
        let withoutRequest = #"{"version":1,"type":"host.update","update_action":"check"}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(withoutRequest.utf8)) }
    }

    @Test func sessionRejectsCallerIdentityInjectionAndFractionalCounters() throws {
        let auth =
            #"{"version":1,"type":"hello","auth":{"remote_id":"00000000-0000-4000-8000-000000000001","token":"00000000000000000000000000000000","last_credit_sequence":0}}"#
        #expect(try ProtocolValidation.decode(Data(auth.utf8)).auth?.lastCreditSequence == 0)
        let injected = auth.replacingOccurrences(of: #""token":"#, with: #""requested_by":"other","token":"#)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(injected.utf8)) }
        let fraction = auth.replacingOccurrences(of: #""last_credit_sequence":0"#, with: #""last_credit_sequence":0.5"#)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(fraction.utf8)) }
        let boolean = auth.replacingOccurrences(of: #""last_credit_sequence":0"#, with: #""last_credit_sequence":true"#)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(boolean.utf8)) }
    }

    @Test func sessionAcceptsFourDigitPairingPinAndRejectsAmbiguousCredentials() throws {
        let valid = #"{"version":1,"type":"pair","pair":{"name":"Phone","pin":"0427"}}"#
        #expect(try ProtocolValidation.decode(Data(valid.utf8)).pair?.pin == "0427")
        let both =
            #"{"version":1,"type":"pair","pair":{"name":"Phone","pin":"0427","secret":"00000000000000000000000000000000"}}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(both.utf8)) }
        let unicodeDigits = #"{"version":1,"type":"pair","pair":{"name":"Phone","pin":"٠٤٢٧"}}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(unicodeDigits.utf8)) }
    }

    @Test func songPreparationMayCarryFavoriteMetadataForLibraryRecovery() throws {
        let frame =
            #"{"version":1,"type":"song.prepare","request_id":"00000000-0000-4000-8000-000000000001","song":{"source":"library","id":"0123456789ABCDEF"},"song_metadata":{"source":"library","id":"0123456789ABCDEF","title":"Saved song","artist":"Artist","album":"Album","duration_ms":120000}}"#
        let decoded = try ProtocolValidation.decode(Data(frame.utf8))
        #expect(decoded.songMetadata?.title == "Saved song")
    }

    @Test func timedLyricsKeepOriginalTextAndEnglishTranslation() throws {
        let xml = """
            <tt xml:lang="ja" xmlns:itunes="http://music.apple.com/lyric-ttml-internal">
              <head><metadata><itunes:translation type="subtitle" xml:lang="en"><itunes:text for="L1">English text</itunes:text></itunes:translation></metadata></head>
              <body><div><p begin="00:01.250" end="00:03.500" itunes:key="L1"><span>Original</span> text</p><p begin="4s" end="6s" itunes:key="L2">Next line</p></div></body>
            </tt>
            """
        let document = try TTMLDocument.parse(Data(xml.utf8), occurrence: id)
        #expect(document.occurrenceId == id)
        #expect(document.lines.count == 2)
        #expect(document.lines[0].text == "Original text")
        #expect(document.lines[0].startMs == 1_250)
        #expect(document.lines[0].endMs == 3_500)
        #expect(document.lines[0].translation == "English text")
        #expect(document.lines[0].romanized == nil)
        #expect(document.translationSource == "apple")
    }

    @Test func timedWordsRepairMissingLineBounds() throws {
        let xml =
            #"<tt xmlns:itunes="http://music.apple.com/lyric-ttml-internal"><body><p itunes:key="L1"><span begin="1s" end="2s">First</span></p></body></tt>"#
        let line = try #require(TTMLDocument.parse(Data(xml.utf8), occurrence: id).lines.first)
        #expect(line.startMs == 1_000)
        #expect(line.endMs == 2_000)
    }

    @Test func timedWordSpacingDoesNotSplitSyllables() throws {
        let xml =
            #"<tt><body><p begin="1s" end="2s"><span begin="1s" end="1.2s">Dan</span> <span begin="1.2s" end="1.4s">me</span><span begin="1.4s" end="1.6s">ne</span><span begin="1.6s" end="1.8s">ma</span><span begin="1.8s" end="2s">ni</span> <span begin="1.8s" end="2s">aku,</span></p></body></tt>"#
        let line = try #require(TTMLDocument.parse(Data(xml.utf8), occurrence: id).lines.first)
        #expect(line.text == "Dan menemani aku,")
        #expect(line.words.map(\.text).joined() == "Dan menemani aku,")
    }

    @Test func timedLinesInferMissingEndBounds() throws {
        let xml =
            #"<tt><body><p xml:id="L1" begin="1s">First</p><p xml:id="L2" begin="2s">Second</p></body></tt>"#
        let lines = try TTMLDocument.parse(Data(xml.utf8), occurrence: id).lines
        #expect(lines[0].endMs == 2_000)
        #expect(lines[1].endMs == 6_000)
    }

    @Test func malformedOrExternalLyricsCannotBecomeATimeline() throws {
        #expect(TTMLDocument.milliseconds("bad:01:02") == nil)
        #expect(TTMLDocument.milliseconds("00:65") == nil)
        #expect(TTMLDocument.milliseconds("1::02") == nil)
        #expect(TTMLDocument.milliseconds("-1s") == nil)
        let xml =
            #"<!DOCTYPE tt [<!ENTITY secret SYSTEM "file:///etc/passwd">]><tt><body><p begin="0s">&secret;</p></body></tt>"#
        #expect(throws: (any Error).self) { try TTMLDocument.parse(Data(xml.utf8), occurrence: id) }
    }

    @Test func aDeadlineAfterDispatchCannotClaimTheMutationNeverHappened() {
        let late = CommandFailure(dispatched: true, code: "expired")
        #expect(late.outcome == "unconfirmed")
        #expect(late.code == "outcome_unknown")
        let early = CommandFailure(dispatched: false, code: "expired")
        #expect(early.outcome == "expired")
        let failedRead = CommandFailure(dispatched: false, code: "outcome_unknown")
        #expect(failedRead.outcome == "rejected")
        #expect(failedRead.code == "music_unavailable")
    }

    @Test func repeatedLyricLineIdentitiesAreRejectedBeforeRendering() {
        let xml =
            #"<tt><body><p begin="0s" end="1s" xml:id="same">First</p><p begin="1s" end="2s" xml:id="same">Second</p></body></tt>"#
        #expect(throws: (any Error).self) { try TTMLDocument.parse(Data(xml.utf8), occurrence: id) }
    }

    @Test func lrclibLrcParserBuildsLineAndWordTimings() throws {
        let record = LRCLIBRecord(
            trackName: "Example", artistName: "Example Artist", albumName: "Album", duration: 12,
            instrumental: false,
            plainLyrics: nil,
            syncedLyrics: "[00:01.00]<00:01.00>Hello <00:01.50>world\n[00:03.00]Next line")
        let document = try #require(try LRCParser.document(record, occurrence: id))
        #expect(document.source == "lrclib")
        #expect(document.lines.count == 2)
        #expect(document.lines[0].startMs == 1_000)
        #expect(document.lines[0].words.count == 2)
        #expect(document.lines[0].words[1].startMs == 1_500)
        #expect(document.lines[0].endMs == 3_000)
    }

    @Test func lrclibLyricsExposeLatinTransliterationForNonLatinText() throws {
        let record = LRCLIBRecord(
            trackName: "Example", artistName: "Example Artist", albumName: "Album", duration: 12,
            instrumental: false, plainLyrics: nil, syncedLyrics: "[00:01.00]こんにちは")
        let document = try #require(try LRCParser.document(record, occurrence: id))
        #expect(document.lines[0].romanized?.isEmpty == false)
        #expect(document.lines[0].romanized != document.lines[0].text)
    }

    @Test func lrclibMatchRejectsWrongTrackAndLargeDurationDrift() {
        let record = LRCLIBRecord(
            trackName: "Other", artistName: "Example Artist", albumName: nil, duration: 180,
            instrumental: false, plainLyrics: "text", syncedLyrics: nil)
        #expect(
            !record.matches(
                Song(source: "catalog", id: "1", title: "Example", artist: "Example Artist", durationMs: 180_000)))
    }

    @Test func artworkProviderAcceptsOnlyAppleCdnArtworkURLs() {
        #expect(ArtworkProvider.isAllowedURL("https://is1-ssl.mzstatic.com/image/thumb/Music.jpg"))
        #expect(!ArtworkProvider.isAllowedURL("http://is1-ssl.mzstatic.com/image/thumb/Music.jpg"))
        #expect(!ArtworkProvider.isAllowedURL("https://example.com/image.jpg"))
        #expect(!ArtworkProvider.isAllowedURL("https://mzstatic.com/image.jpg"))
    }
}
