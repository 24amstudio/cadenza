import Testing

@testable import CadenzaHost

struct SurroundDownmixerTests {
    /// One frame with the given channel levels and silence elsewhere.
    private func frame(channels: Int, levels: [Int: Float]) -> [Float] {
        (0..<channels).map { levels[$0] ?? 0 }
    }

    private func isClose(_ actual: [Float], _ expected: [Float]) -> Bool {
        zip(actual, expected).allSatisfy { abs($0 - $1) < 0.001 } && actual.count == expected.count
    }

    @Test func aFiveDotOneInputPassesThroughUnchanged() throws {
        let input: [Float] = [0.1, -0.2, 0.3, -0.4, 0.5, -0.6]

        #expect(try SurroundDownmixer.downmixed(input, channels: 6) == input)
    }

    @Test func fullScaleInputsNeverExceedTheInputPeak() throws {
        let sevenOneFour = try SurroundDownmixer.downmixed(Array(repeating: 1, count: 12), channels: 12)
        let fiveOneTwo = try SurroundDownmixer.downmixed(Array(repeating: 1, count: 8), channels: 8)

        #expect(sevenOneFour.allSatisfy { $0 <= 1.0001 && $0 >= -1.0001 })
        #expect(fiveOneTwo.allSatisfy { $0 <= 1.0001 && $0 >= -1.0001 })
    }

    @Test func aTopFrontLeftSignalFoldsOnlyIntoTheLeftFrontChannel() throws {
        let topFrontLeft = 6
        let output = try SurroundDownmixer.downmixed(
            frame(channels: 8, levels: [topFrontLeft: 1]), channels: 8)

        // The -3 dB fold shares the 1.7071 row total, so the left output is 0.7071 / 1.7071.
        #expect(isClose(output, [0.4142, 0, 0, 0, 0, 0]))
    }

    @Test func aTopRearLeftSignalFoldsIntoTheLeftSurroundChannel() throws {
        let topRearLeft = 10
        let output = try SurroundDownmixer.downmixed(
            frame(channels: 12, levels: [topRearLeft: 1]), channels: 12)

        // Ls adds two -3 dB sources, so the surround output is 0.7071 / 2.4142.
        #expect(isClose(output, [0, 0, 0, 0, 0.2929, 0]))
    }

    @Test func aLayoutOtherThanFiveDotOneTwoOrSevenDotOneFourIsRefused() {
        #expect(throws: CadenzaError.self) {
            try SurroundDownmixer.downmixed([0, 0], channels: 2)
        }
    }
}
