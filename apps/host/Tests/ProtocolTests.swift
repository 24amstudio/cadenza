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

    @Test func sessionRejectsCallerIdentityInjectionAndFractionalCounters() throws {
        let auth = #"{"version":1,"type":"hello","auth":{"remote_id":"00000000-0000-4000-8000-000000000001","token":"00000000000000000000000000000000","last_credit_sequence":0}}"#
        #expect(try ProtocolValidation.decode(Data(auth.utf8)).auth?.lastCreditSequence == 0)
        let injected = auth.replacingOccurrences(of: #""token":"#, with: #""requested_by":"other","token":"#)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(injected.utf8)) }
        let fraction = auth.replacingOccurrences(of: #""last_credit_sequence":0"#, with: #""last_credit_sequence":0.5"#)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(fraction.utf8)) }
        let boolean = auth.replacingOccurrences(of: #""last_credit_sequence":0"#, with: #""last_credit_sequence":true"#)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(boolean.utf8)) }
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
        #expect(document.translationSource == "apple")
    }

    @Test func malformedOrExternalLyricsCannotBecomeATimeline() throws {
        #expect(TTMLDocument.milliseconds("bad:01:02") == nil)
        #expect(TTMLDocument.milliseconds("00:65") == nil)
        #expect(TTMLDocument.milliseconds("1::02") == nil)
        #expect(TTMLDocument.milliseconds("-1s") == nil)
        let xml = #"<!DOCTYPE tt [<!ENTITY secret SYSTEM "file:///etc/passwd">]><tt><body><p begin="0s">&secret;</p></body></tt>"#
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
        let xml = #"<tt><body><p begin="0s" end="1s" xml:id="same">First</p><p begin="1s" end="2s" xml:id="same">Second</p></body></tt>"#
        #expect(throws: (any Error).self) { try TTMLDocument.parse(Data(xml.utf8), occurrence: id) }
    }
}
