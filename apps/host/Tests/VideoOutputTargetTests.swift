import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct VideoOutputTargetTests {
    private func command(_ action: String) -> Data {
        let commandId = UUID().uuidString.lowercased()
        let epoch = UUID().uuidString.lowercased()
        let frame =
            #"{"version":1,"type":"command","command_id":"\#(commandId)","host_epoch":"\#(epoch)","#
            + #""expires_at_host_ms":9007199254740,"expected_revision":1,"action":\#(action)}"#
        return Data(frame.utf8)
    }

    @Test func theLyricsGoToTheMacUnlessAnotherTargetWasChosen() {
        let suite = "cadenza-video-output-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard

        #expect(VideoOutputTarget.stored(in: defaults) == .hostDisplay)

        defaults.set(VideoOutputTarget.castTransmitter.rawValue, forKey: VideoOutputTarget.defaultsKey)
        #expect(VideoOutputTarget.stored(in: defaults) == .castTransmitter)
    }

    @Test func aTargetCommandNamesOneOfTheTwoOutputsOnly() throws {
        let mac = #"{"kind":"video.output","video_output":"host_display"}"#
        let cast = #"{"kind":"video.output","video_output":"cast_transmitter"}"#
        let unknown = #"{"kind":"video.output","video_output":"airplay"}"#

        #expect(try ProtocolValidation.decode(command(mac)).action?.videoOutput == "host_display")
        #expect(try ProtocolValidation.decode(command(cast)).action?.videoOutput == "cast_transmitter")
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(command(unknown)) }
    }

    @Test func aCastModeAndAnAVROffsetAreAcceptedOnlyWithinTheirLimits() throws {
        let mode = #"{"kind":"cast.presentation","presentation":"full_suite"}"#
        let unknownMode = #"{"kind":"cast.presentation","presentation":"surround"}"#
        let offset = #"{"kind":"lip_sync.offset","lip_sync_offset_ms":-120}"#
        let tooLate = #"{"kind":"lip_sync.offset","lip_sync_offset_ms":900}"#

        #expect(try ProtocolValidation.decode(command(mode)).action?.presentation == "full_suite")
        #expect(try ProtocolValidation.decode(command(offset)).action?.lipSyncOffsetMs == -120)
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(command(unknownMode)) }
        #expect(throws: (any Error).self) { try ProtocolValidation.decode(command(tooLate)) }
    }
}
