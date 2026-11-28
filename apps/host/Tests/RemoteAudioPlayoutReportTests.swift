import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioPlayoutReportTests {
    private static func message(_ fields: String) -> Data {
        Data("{\"version\":1,\"type\":\"REMOTE_AUDIO_PLAYOUT\",\(fields)}".utf8)
    }

    @Test func aWellFormedReportDecodes() {
        let report = RemoteAudioPlayoutReport.decode(
            Self.message("\"underrunFrames\":96,\"concealedFrames\":256,\"longTaskMs\":12.5"))

        #expect(report == RemoteAudioPlayoutReport(underrunFrames: 96, concealedFrames: 256, longTaskMs: 12.5))
    }

    @Test func otherMessagesAndOutOfRangeValuesAreRefused() {
        #expect(RemoteAudioPlayoutReport.decode(Data("{\"version\":1,\"type\":\"REMOTE_AUDIO_SYNC\"}".utf8)) == nil)
        #expect(
            RemoteAudioPlayoutReport.decode(
                Self.message("\"underrunFrames\":-1,\"concealedFrames\":0,\"longTaskMs\":0")) == nil)
        #expect(
            RemoteAudioPlayoutReport.decode(
                Self.message("\"underrunFrames\":0,\"concealedFrames\":0,\"longTaskMs\":1e9")) == nil)
    }

    @Test func reportsAddUpWithinAWindow() {
        let first = RemoteAudioPlayoutReport(underrunFrames: 10, concealedFrames: 20, longTaskMs: 5)
        let second = RemoteAudioPlayoutReport(underrunFrames: 1, concealedFrames: 2, longTaskMs: 7)

        #expect(
            first.adding(second) == RemoteAudioPlayoutReport(underrunFrames: 11, concealedFrames: 22, longTaskMs: 12))
        #expect(RemoteAudioPlayoutReport.empty.adding(first) == first)
    }
}
