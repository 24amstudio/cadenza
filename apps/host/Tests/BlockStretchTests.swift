import Testing

@testable import CadenzaHost

struct BlockStretchTests {
    @Test func anEqualLengthBlockPassesThroughUnchanged() {
        let stereo: [Float] = [0.1, -0.1, 0.2, -0.2]

        #expect(BlockStretch.resample(stereo, channels: 2, toFrames: 2) == stereo)
    }

    @Test func aLongerBlockKeepsItsFirstSampleAndStaysWithinItsRange() {
        let stretched = BlockStretch.resample([0, 1, 2, 3], channels: 1, toFrames: 5)

        #expect(stretched.count == 5)
        #expect(stretched.first == 0)
        #expect(zip(stretched, stretched.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(stretched.last == 3)
    }

    @Test func eachChannelIsStretchedOnItsOwn() {
        let stretched = BlockStretch.resample([0, 10, 1, 11, 2, 12], channels: 2, toFrames: 4)

        #expect(stretched.count == 8)
        for frame in 0..<4 {
            #expect((0.0...2.0).contains(stretched[frame * 2]))
            #expect((10.0...12.0).contains(stretched[frame * 2 + 1]))
        }
    }
}
