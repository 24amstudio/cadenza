import Accelerate
import Foundation

/// The fourth-order Linkwitz-Riley crossover behind the Host sub and the Remote mains. Each filter cascades two
/// second-order Butterworth sections (Q = 1/√2), so the low and high bands sum flat and stay in phase at the crossover.
///
/// vDSP keeps each section's state in a preallocated delay buffer, and every buffer is allocated in `init`. Rendering
/// does not allocate. The engine is not thread-safe: one serial queue calls both rendering and `setCrossover`.
final class CrossoverDspEngine: @unchecked Sendable {
    static let sectionCount = 2
    private static let delayLength = 2 * sectionCount + 2

    let sampleRate: Double
    let maximumFrames: Int
    private(set) var crossoverHz: Double
    private var lowSetup: vDSP_biquad_Setup
    private var highSetup: vDSP_biquad_Setup
    private let lowDelayMono: UnsafeMutablePointer<Float>
    private let lowDelayLeft: UnsafeMutablePointer<Float>
    private let lowDelayRight: UnsafeMutablePointer<Float>
    private let highDelayLeft: UnsafeMutablePointer<Float>
    private let highDelayRight: UnsafeMutablePointer<Float>
    private let monoScratch: UnsafeMutablePointer<Float>

    enum Failure: Error {
        case invalidFrequency
        case setupUnavailable
    }

    init(sampleRate: Double, crossoverHz: Double, maximumFrames: Int) throws {
        guard (40...160).contains(crossoverHz), sampleRate > 0, maximumFrames > 0 else {
            throw Failure.invalidFrequency
        }
        self.sampleRate = sampleRate
        self.maximumFrames = maximumFrames
        self.crossoverHz = crossoverHz
        let coefficients = Self.coefficients(hz: crossoverHz, sampleRate: sampleRate)
        guard
            let low = Self.createSetup(coefficients.low),
            let high = Self.createSetup(coefficients.high)
        else { throw Failure.setupUnavailable }
        lowSetup = low
        highSetup = high
        lowDelayMono = Self.zeroedDelay()
        lowDelayLeft = Self.zeroedDelay()
        lowDelayRight = Self.zeroedDelay()
        highDelayLeft = Self.zeroedDelay()
        highDelayRight = Self.zeroedDelay()
        monoScratch = UnsafeMutablePointer<Float>.allocate(capacity: maximumFrames)
        monoScratch.initialize(repeating: 0, count: maximumFrames)
    }

    deinit {
        vDSP_biquad_DestroySetup(lowSetup)
        vDSP_biquad_DestroySetup(highSetup)
        for delay in [lowDelayMono, lowDelayLeft, lowDelayRight, highDelayLeft, highDelayRight] {
            delay.deallocate()
        }
        monoScratch.deallocate()
    }

    /// Replaces the crossover frequency. The new coefficients build into fresh setups before the old ones go, so the
    /// engine never renders with a half-written filter. The delay state carries over, which avoids a click.
    func setCrossover(hz: Double) throws {
        guard (40...160).contains(hz) else { throw Failure.invalidFrequency }
        let coefficients = Self.coefficients(hz: hz, sampleRate: sampleRate)
        guard
            let low = Self.createSetup(coefficients.low),
            let high = Self.createSetup(coefficients.high)
        else { throw Failure.setupUnavailable }
        vDSP_biquad_DestroySetup(lowSetup)
        vDSP_biquad_DestroySetup(highSetup)
        lowSetup = low
        highSetup = high
        crossoverHz = hz
    }

    /// The Host sub: the mono sum `0.5 × (L + R)`, low-passed, then scaled by `subGainDb` and optionally inverted.
    func renderSub(
        left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int, subGainDb: Double, phaseInvert: Bool,
        into output: UnsafeMutablePointer<Float>
    ) {
        precondition(count <= maximumFrames)
        var half: Float = 0.5
        vDSP_vadd(left, 1, right, 1, monoScratch, 1, vDSP_Length(count))
        vDSP_vsmul(monoScratch, 1, &half, monoScratch, 1, vDSP_Length(count))
        vDSP_biquad(lowSetup, lowDelayMono, monoScratch, 1, output, 1, vDSP_Length(count))
        var gain = Float(pow(10.0, subGainDb / 20.0)) * (phaseInvert ? -1 : 1)
        vDSP_vsmul(output, 1, &gain, output, 1, vDSP_Length(count))
    }

    /// The Remote mains: each channel high-passed on its own, with the same section pair as the sub.
    func renderMains(
        left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int,
        outputLeft: UnsafeMutablePointer<Float>, outputRight: UnsafeMutablePointer<Float>
    ) {
        precondition(count <= maximumFrames)
        vDSP_biquad(highSetup, highDelayLeft, left, 1, outputLeft, 1, vDSP_Length(count))
        vDSP_biquad(highSetup, highDelayRight, right, 1, outputRight, 1, vDSP_Length(count))
    }

    /// The second-order Butterworth coefficients from the RBJ cookbook, cascaded `sectionCount` times. Each section is
    /// `[b0, b1, b2, a1, a2]`, normalized by `a0`, in the sign convention that vDSP_biquad applies.
    static func coefficients(hz: Double, sampleRate: Double) -> (low: [Double], high: [Double]) {
        let q = 1 / 2.0.squareRoot()
        let omega = 2 * Double.pi * hz / sampleRate
        let cosine = cos(omega)
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha
        let a1 = -2 * cosine / a0
        let a2 = (1 - alpha) / a0
        let lowB0 = (1 - cosine) / 2 / a0
        let lowB1 = (1 - cosine) / a0
        let highB0 = (1 + cosine) / 2 / a0
        let highB1 = -(1 + cosine) / a0
        let low = [lowB0, lowB1, lowB0, a1, a2]
        let high = [highB0, highB1, highB0, a1, a2]
        return (
            Array(repeating: low, count: sectionCount).flatMap { $0 },
            Array(repeating: high, count: sectionCount).flatMap { $0 }
        )
    }

    private static func createSetup(_ coefficients: [Double]) -> vDSP_biquad_Setup? {
        coefficients.withUnsafeBufferPointer { buffer in
            vDSP_biquad_CreateSetup(buffer.baseAddress!, vDSP_Length(sectionCount))
        }
    }

    private static func zeroedDelay() -> UnsafeMutablePointer<Float> {
        let delay = UnsafeMutablePointer<Float>.allocate(capacity: delayLength)
        delay.initialize(repeating: 0, count: delayLength)
        return delay
    }
}
