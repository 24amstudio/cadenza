import Testing

@testable import CadenzaHost

struct LateDropCushionTests {
    @Test func aGrowingLateDropCountRaisesTheBoost() {
        var cushion = LateDropCushion()

        cushion.observe(lateDrops: 3)
        #expect(cushion.boostUs == LateDropCushion.stepUs)

        cushion.observe(lateDrops: 5)
        #expect(cushion.boostUs == 2 * LateDropCushion.stepUs)
    }

    @Test func aQuietLinkDecaysTheBoostBackToTheBaseCushion() {
        var cushion = LateDropCushion()
        cushion.observe(lateDrops: 1)
        #expect(cushion.boostUs == LateDropCushion.stepUs)

        for _ in 0..<10 {
            cushion.observe(lateDrops: 1)
        }

        #expect(cushion.boostUs == 0)
    }

    @Test func theBoostNeverExceedsItsCeiling() {
        var cushion = LateDropCushion()

        for drops in 1...100 {
            cushion.observe(lateDrops: drops)
        }

        #expect(cushion.boostUs == LateDropCushion.maximumBoostUs)
    }

    @Test func droppedCountsThatExpireDoNotRaiseTheBoost() {
        var cushion = LateDropCushion()
        cushion.observe(lateDrops: 4)
        let raised = cushion.boostUs

        cushion.observe(lateDrops: 1)

        #expect(cushion.boostUs == raised - LateDropCushion.decayUs)
    }
}
