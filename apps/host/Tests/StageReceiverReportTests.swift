import Foundation
import Testing

@testable import CadenzaHost

struct StageReceiverReportTests {
    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func aPlaybackReportCarriesCodecChannelsAndPath() {
        let data = json([
            "version": 1, "type": "STAGE_PLAYBACK", "codec": "ac3", "channels": 6, "path": "mse", "active": true,
        ])

        #expect(StageReceiverReport.parse(data) == .playback(codec: "ac3", channels: 6, path: "mse", active: true))
    }

    @Test func aPlaybackReportWithAnUnknownCodecIsRejected() {
        let data = json([
            "version": 1, "type": "STAGE_PLAYBACK", "codec": "flac", "channels": 2, "path": "mse", "active": true,
        ])

        #expect(StageReceiverReport.parse(data) == nil)
    }

    @Test func aLogLineKeepsItsLevelAndIsBoundedInLength() {
        let long = String(repeating: "x", count: 900)
        let data = json(["version": 1, "type": "STAGE_LOG", "level": "warn", "message": long])

        #expect(StageReceiverReport.parse(data) == .log(level: .warning, message: String(repeating: "x", count: 500)))
    }

    @Test func anEmptyLogLineIsRejected() {
        let data = json(["version": 1, "type": "STAGE_LOG", "level": "info", "message": ""])

        #expect(StageReceiverReport.parse(data) == nil)
    }

    @Test func aReceiverCannotRecordMoreThanItsLimitInOneWindow() {
        var limiter = StageLogLimiter()
        let start = Date(timeIntervalSince1970: 1_000)
        let accepted = (0..<40).filter { _ in limiter.allow(now: start) }.count

        #expect(accepted == StageLogLimiter.maximumPerWindow)
        let afterWindow = limiter.allow(now: start.addingTimeInterval(StageLogLimiter.window))
        #expect(afterWindow)
    }

    @Test func theStatusNamesTheSentRouteAndSaysWhenPlaybackIsUnreported() {
        let sent = CastSnapshot.Route(codec: "ac3", channels: 6)
        let status = CastRouteStatus.stage(
            source: "Darrell's MacBook Air", receiver: "TCL55203G", sent: sent, playback: .unreported)

        #expect(
            status.text == "Darrell's MacBook Air → TCL55203G: sends AC-3 5.1. TCL55203G has not reported playback.")
        #expect(!status.mismatch)
    }

    @Test func aMatchingPlaybackReportConfirmsTheRoute() {
        let sent = CastSnapshot.Route(codec: "ac3", channels: 6)
        let status = CastRouteStatus.stage(
            source: "Mac", receiver: "TV", sent: sent,
            playback: .playing(CastSnapshot.Route(codec: "ac3", channels: 6), path: "mse"))

        #expect(status.text == "Mac → TV: sends AC-3 5.1, and TV plays AC-3 5.1.")
        #expect(!status.mismatch)
    }

    @Test func aDifferentPlaybackReportIsFlaggedAsAMismatch() {
        let sent = CastSnapshot.Route(codec: "ac3", channels: 6)
        let status = CastRouteStatus.stage(
            source: "Mac", receiver: "TV", sent: sent,
            playback: .playing(CastSnapshot.Route(codec: "aac", channels: 2), path: "mse"))

        #expect(status.text == "Mac → TV: sends AC-3 5.1, but TV plays AAC stereo.")
        #expect(status.mismatch)
    }

    @Test func aStageRouteIsReportedWithTheChannelsTheHostSends() {
        #expect(StageCodecPlan.Route.ac3.sentRoute == CastSnapshot.Route(codec: "ac3", channels: 6))
        #expect(StageCodecPlan.Route.aac.sentRoute == CastSnapshot.Route(codec: "aac", channels: 2))
        #expect(StageCodecPlan.Route.lpcm(channels: 2).sentRoute == CastSnapshot.Route(codec: "pcm", channels: 2))
    }

    @Test func aGoogleCastLineSaysItCannotConfirmPlayback() {
        let status = CastRouteStatus.cast(
            source: "Mac", device: "Living Room", sent: CastSnapshot.Route(codec: "aac", channels: 2))

        #expect(status.text == "Mac → Living Room: sends AAC stereo. Google Cast does not report playback.")
    }
}
