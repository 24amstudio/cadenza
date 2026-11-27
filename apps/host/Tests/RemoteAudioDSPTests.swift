import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioDSPTests {
    private static let sampleRate = 48_000.0
    private static let blockFrames = 1_024
    private static let totalFrames = 96_000

    /// Gain in dB of the sub, the mains, and their sum for one sine. Each is measured over the second second, after the
    /// filter state has settled.
    private func response(hz: Double, crossoverHz: Double = 80) throws -> (sub: Double, mains: Double, sum: Double) {
        let engine = try CrossoverDspEngine(
            sampleRate: Self.sampleRate, crossoverHz: crossoverHz, maximumFrames: Self.blockFrames)
        let input = UnsafeMutablePointer<Float>.allocate(capacity: Self.blockFrames)
        let sub = UnsafeMutablePointer<Float>.allocate(capacity: Self.blockFrames)
        let mainsLeft = UnsafeMutablePointer<Float>.allocate(capacity: Self.blockFrames)
        let mainsRight = UnsafeMutablePointer<Float>.allocate(capacity: Self.blockFrames)
        defer {
            input.deallocate()
            sub.deallocate()
            mainsLeft.deallocate()
            mainsRight.deallocate()
        }
        var inputEnergy = 0.0
        var subEnergy = 0.0
        var mainsEnergy = 0.0
        var sumEnergy = 0.0
        var start = 0
        while start < Self.totalFrames {
            for index in 0..<Self.blockFrames {
                input[index] = Float(sin(2 * Double.pi * hz * Double(start + index) / Self.sampleRate))
            }
            engine.renderSub(
                left: input, right: input, count: Self.blockFrames, subGainDb: 0, phaseInvert: false, into: sub)
            engine.renderMains(
                left: input, right: input, count: Self.blockFrames, outputLeft: mainsLeft, outputRight: mainsRight)
            if start >= Self.totalFrames / 2 {
                for index in 0..<Self.blockFrames {
                    inputEnergy += Double(input[index] * input[index])
                    subEnergy += Double(sub[index] * sub[index])
                    mainsEnergy += Double(mainsLeft[index] * mainsLeft[index])
                    let sum = Double(sub[index] + mainsLeft[index])
                    sumEnergy += sum * sum
                }
            }
            start += Self.blockFrames
        }
        return (
            sub: 10 * log10(subEnergy / inputEnergy),
            mains: 10 * log10(mainsEnergy / inputEnergy),
            sum: 10 * log10(sumEnergy / inputEnergy)
        )
    }

    @Test func bothBandsAreMinus6dBAtTheCrossover() throws {
        let measured = try response(hz: 80)
        // Each second-order Butterworth section is −3 dB at its cutoff, and the fourth-order pair is −6 dB.
        #expect(abs(measured.sub - -6.02) < 0.1, "sub \(measured.sub) dB")
        #expect(abs(measured.mains - -6.02) < 0.1, "mains \(measured.mains) dB")
    }

    @Test func fourthOrderSlopeIsAbout24dBPerOctave() throws {
        let belowLow = try response(hz: 40)
        let aboveHigh = try response(hz: 160)
        // Two sections at 2× the cutoff give about −24.6 dB. The stated slope is 24 dB per octave.
        #expect(abs(aboveHigh.sub - -24.6) < 0.5, "sub at 2×fc \(aboveHigh.sub) dB")
        #expect(abs(belowLow.mains - -24.6) < 0.5, "mains at ½×fc \(belowLow.mains) dB")
    }

    @Test func summedBandsStayFlatAcrossTheAudibleRange() throws {
        for hz in [20.0, 50, 80, 200, 1_000, 5_000, 15_000, 20_000] {
            let measured = try response(hz: hz)
            #expect(abs(measured.sum) < 0.1, "sum at \(hz) Hz is \(measured.sum) dB")
        }
    }

    @Test func phaseInvertNegatesTheSubSample() throws {
        let engine = try CrossoverDspEngine(sampleRate: Self.sampleRate, crossoverHz: 80, maximumFrames: 256)
        let input = (0..<256).map { Float(sin(Double($0) * 0.05)) }
        let normal = try renderSub(engine, input, phaseInvert: false)
        let inverted = try renderSub(
            CrossoverDspEngine(sampleRate: Self.sampleRate, crossoverHz: 80, maximumFrames: 256), input,
            phaseInvert: true)
        #expect(zip(normal, inverted).allSatisfy { $0 == -$1 })
    }

    @Test func crossoverOutsideTheContractIsRefused() throws {
        let engine = try CrossoverDspEngine(sampleRate: Self.sampleRate, crossoverHz: 80, maximumFrames: 64)
        #expect(throws: CrossoverDspEngine.Failure.invalidFrequency) { try engine.setCrossover(hz: 39.9) }
        try engine.setCrossover(hz: 120)
        #expect(engine.crossoverHz == 120)
    }

    private func renderSub(
        _ engine: CrossoverDspEngine, _ input: [Float], phaseInvert: Bool
    ) throws -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { samples in
            output.withUnsafeMutableBufferPointer { out in
                engine.renderSub(
                    left: samples.baseAddress!, right: samples.baseAddress!, count: input.count, subGainDb: 0,
                    phaseInvert: phaseInvert, into: out.baseAddress!)
            }
        }
        return output
    }
}

struct RemoteAudioRouterTests {
    private let left: [Float] = [0.1234567, -0.9999999, 1e-30, 0.5]
    private let right: [Float] = [-0.25, 0.75, -1e-30, 0.125]

    @Test func pureTransferCopiesFullRangeFramesBitForBit() throws {
        // No engine is passed, which proves the pure modes never reach the crossover.
        let blocks = try #require(
            RemoteAudioRouter.route(
                mode: .pureTransferExclusive, left: left, right: right, dsp: nil, subGainDb: 0, phaseInvert: false))
        #expect(blocks.remoteLeft == left)
        #expect(blocks.remoteRight == right)
        #expect(blocks.flag == .pureFullRange)
    }

    @Test func exclusiveMutesTheHostAndMirrorPlaysStereoOnBoth() throws {
        let exclusive = try #require(
            RemoteAudioRouter.route(
                mode: .pureTransferExclusive, left: left, right: right, dsp: nil, subGainDb: 0, phaseInvert: false))
        #expect(exclusive.hostOutput == .silent)
        #expect(exclusive.host.isEmpty)

        let mirror = try #require(
            RemoteAudioRouter.route(
                mode: .pureTransferMirror, left: left, right: right, dsp: nil, subGainDb: 0, phaseInvert: false))
        #expect(mirror.hostOutput == .stereo)
        #expect(mirror.host == RemoteAudioRouter.interleave(left, right))
    }

    @Test func crossoverSplitsIntoAMonoSubAndStereoMains() throws {
        let dsp = try CrossoverDspEngine(sampleRate: 48_000, crossoverHz: 80, maximumFrames: 4)
        let blocks = try #require(
            RemoteAudioRouter.route(
                mode: .crossoverSplit, left: left, right: right, dsp: dsp, subGainDb: 0, phaseInvert: false))
        #expect(blocks.hostOutput == .mono)
        #expect(blocks.host.count == left.count)
        #expect(blocks.remoteLeft.count == left.count)
        #expect(blocks.flag == .crossoverHPFMains)
    }

    @Test func crossoverWithoutAnEngineStaysSilentRatherThanSendingFullRange() {
        let blocks = RemoteAudioRouter.route(
            mode: .crossoverSplit, left: left, right: right, dsp: nil, subGainDb: 0, phaseInvert: false)
        #expect(blocks == nil)
    }
}
