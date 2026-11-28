import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioQualityControllerTests {
    private static let calm = RemoteAudioQualityWindow()

    @Test func aTierNamesItsFormatAndBitRate() {
        #expect(RemoteAudioQuality.lossless.wireName == "lossless_24_48")
        #expect(RemoteAudioQuality.lossless.bitDepth == .int24)
        #expect(RemoteAudioQuality.lossless.payloadBitsPerSecond == 2_304_000)
        #expect(RemoteAudioQuality.standard.payloadBitsPerSecond == 1_536_000)
        #expect(RemoteAudioQuality.allCases.allSatisfy { $0.channels == 2 })
    }

    @Test func aSevereWindowStepsDownOneTierAtOnce() {
        var controller = RemoteAudioQualityController()
        var burst = RemoteAudioQualityWindow()
        burst.networkDrops = RemoteAudioQualityController.severeNetworkDrops

        #expect(controller.observe(burst) == .standard)
        #expect(controller.quality == .standard)
        #expect(controller.observe(burst) == nil)
        #expect(controller.quality == .standard)
    }

    @Test func aMildWindowHoldsTheTier() {
        var controller = RemoteAudioQualityController()
        var jitter = RemoteAudioQualityWindow()
        jitter.networkDrops = 1

        #expect(controller.observe(jitter) == nil)
        #expect(controller.quality == .lossless)
        #expect(controller.reason == .network)
    }

    @Test func aCalmStretchOfThirtySecondsStepsBackUpOneTier() {
        var controller = RemoteAudioQualityController()
        var burst = RemoteAudioQualityWindow()
        burst.networkDrops = RemoteAudioQualityController.severeNetworkDrops
        controller.observe(burst)
        #expect(controller.quality == .standard)

        for _ in 0..<(RemoteAudioQualityController.calmWindowsToUpgrade - 1) {
            #expect(controller.observe(Self.calm) == nil)
        }
        #expect(controller.observe(Self.calm) == .lossless)
        #expect(controller.reason == .recovered)
    }

    @Test func aMildWindowRestartsTheCalmCount() {
        var controller = RemoteAudioQualityController()
        var burst = RemoteAudioQualityWindow()
        burst.networkDrops = RemoteAudioQualityController.severeNetworkDrops
        controller.observe(burst)

        for _ in 0..<(RemoteAudioQualityController.calmWindowsToUpgrade - 1) {
            controller.observe(Self.calm)
        }
        var jitter = RemoteAudioQualityWindow()
        jitter.networkDrops = 1
        controller.observe(jitter)

        #expect(controller.observe(Self.calm) == nil)
        #expect(controller.quality == .standard)
    }

    @Test func theTopTierNeverClimbsPastLossless() {
        var controller = RemoteAudioQualityController()

        for _ in 0..<(RemoteAudioQualityController.calmWindowsToUpgrade * 3) {
            controller.observe(Self.calm)
        }

        #expect(controller.quality == .lossless)
        #expect(controller.reason == .steady)
    }

    @Test func remotePlayoutPressureIsNamedAsSuch() {
        var controller = RemoteAudioQualityController()
        var cut = RemoteAudioQualityWindow()
        cut.remoteUnderrunFrames = RemoteAudioQualityController.severeUnderrunFrames

        controller.observe(cut)

        #expect(controller.quality == .standard)
        #expect(controller.reason == .remotePlayout)
    }

    @Test func aConstrainedHostLowersTheTierAndIsNamedAsPower() {
        var controller = RemoteAudioQualityController()
        var hot = RemoteAudioQualityWindow()
        hot.hostBudget = .constrained

        controller.observe(hot)

        #expect(controller.quality == .standard)
        #expect(controller.reason == .hostPower)
    }

    @Test func hostCPULoadAloneLowersTheTier() {
        var controller = RemoteAudioQualityController()
        var busy = RemoteAudioQualityWindow()
        busy.hostLoad = RemoteAudioQualityController.severeHostLoad

        controller.observe(busy)

        #expect(controller.reason == .hostLoad)
        #expect(controller.quality == .standard)
    }

    @Test func networkPressureOutranksTheOtherCausesWhenNamingTheReason() {
        var window = RemoteAudioQualityWindow()
        window.networkDrops = RemoteAudioQualityController.severeNetworkDrops
        window.remoteUnderrunFrames = RemoteAudioQualityController.severeUnderrunFrames
        window.hostBudget = .survival

        #expect(RemoteAudioQualityController.verdict(for: window).reason == .network)
    }
}
