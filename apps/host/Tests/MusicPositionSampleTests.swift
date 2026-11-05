import Foundation
import Testing

@testable import CadenzaHost

struct MusicPositionSampleTests {
    @Test func datesThePositionToTheMomentMusicReadIt() {
        // Music read the position 130 ms before the process exited, and the call started 280 ms before it exited.
        let sample = MusicStatus.sampleTime(
            readAtMs: 5_000_000 - 130, startedMs: 9_720, finishedMs: 10_000, nowWallMs: 5_000_000)

        #expect(sample == 9_870)
    }

    @Test func neverDatesThePositionBeforeTheCallStarted() {
        let sample = MusicStatus.sampleTime(
            readAtMs: 5_000_000 - 1_000, startedMs: 9_720, finishedMs: 10_000, nowWallMs: 5_000_000)

        #expect(sample == 9_720)
    }

    @Test func fallsBackWhenTheScriptDoesNotReportTheReadTime() {
        let sample = MusicStatus.sampleTime(
            readAtMs: nil, startedMs: 9_720, finishedMs: 10_000, nowWallMs: 5_000_000)

        #expect(sample == nil)
    }

    @Test func decodesTheReadTimeFromTheScriptOutput() throws {
        let json = #"{"playing":true,"state":"playing","volume":40,"position_ms":1200,"read_at_ms":77,"song":null}"#
        let status = try Wire.decode(MusicStatus.self, from: Data(json.utf8))

        #expect(status.readAtMs == 77)
        #expect(status.positionMs == 1_200)
        #expect(status.sampledAtMs == nil)
    }
}
