import Foundation
import Testing

@testable import CadenzaHost

struct LogReportValidationTests {
    @Test func aBatchOfRemoteEntriesIsAcceptedAndSingleEntriesFromOlderRemotesStillParse() throws {
        let batch =
            #"{"version":1,"type":"log.report","log_entries":[{"level":"info","action":"command.sent","message":"kind=playback.pause"}]}"#
        let frame = try ProtocolValidation.decode(Data(batch.utf8))
        #expect(frame.logEntries?.first?.action == "command.sent")

        let legacy =
            #"{"version":1,"type":"log.report","log_level":"warning","log_action":"ui.error","log_message":"Denied"}"#
        #expect(try ProtocolValidation.decode(Data(legacy.utf8)).logAction == "ui.error")
    }

    @Test func anEmptyBatchAndAnUnknownLevelAreRejected() {
        let empty = #"{"version":1,"type":"log.report","log_entries":[]}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(empty.utf8)) }

        let unknownLevel =
            #"{"version":1,"type":"log.report","log_entries":[{"level":"loud","action":"x","message":"y"}]}"#
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(Data(unknownLevel.utf8)) }
    }
}
