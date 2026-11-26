import Testing

@testable import CadenzaHost

struct CastStageDownmixTests {
    @Test func aFullScaleCentreFoldsToEqualBoundedStereo() throws {
        let centre: [Float] = [0, 0, 1, 0, 0, 0]
        let stereo = try SurroundDownmixer.stereo(fromFiveOne: centre)
        #expect(stereo.count == 2)
        #expect(abs(stereo[0] - stereo[1]) < 1e-6)
        #expect(stereo[0] > 0 && stereo[0] < 1)
    }

    @Test func aFullScaleFiveOneFrameNeverExceedsTheRange() throws {
        let frame = [Float](repeating: 1, count: 6)
        let stereo = try SurroundDownmixer.stereo(fromFiveOne: frame)
        #expect(stereo.allSatisfy { $0 >= -1 && $0 <= 1 })
    }

    @Test func aSampleCountThatIsNotWholeFramesIsRefused() {
        #expect(throws: CadenzaError.self) {
            try SurroundDownmixer.stereo(fromFiveOne: [0, 0, 0, 0, 0])
        }
    }
}
