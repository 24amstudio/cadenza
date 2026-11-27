import Foundation

/// Decides what the Host plays and what the Remote receives for one captured block. Pure Transfer copies the input
/// bit for bit and never calls the crossover, so `CrossoverDspEngine` is not reached in those modes.
enum RemoteAudioRouter {
    /// What the Host's own output carries. `silent` is Exclusive, where the process tap mutes Music locally.
    enum HostOutput: Equatable {
        case silent
        case stereo
        case mono
    }

    struct Blocks: Equatable {
        let hostOutput: HostOutput
        /// Host output: left and right for `.stereo`, the mono sub for `.mono`, and empty for `.silent`.
        let host: [Float]
        let remoteLeft: [Float]
        let remoteRight: [Float]
        let flag: RemoteAudioWire.StreamFlag
    }

    /// Routes one block of stereo Float32 samples. Returns nil for a crossover block when no DSP engine is available,
    /// and the caller then keeps the Remote silent instead of sending unfiltered audio.
    static func route(
        mode: RemoteAudioStreamMode, left: [Float], right: [Float], dsp: CrossoverDspEngine?, subGainDb: Double,
        phaseInvert: Bool
    ) -> Blocks? {
        precondition(left.count == right.count)
        switch mode {
        case .pureTransferExclusive:
            return Blocks(
                hostOutput: .silent, host: [], remoteLeft: left, remoteRight: right, flag: .pureFullRange)
        case .pureTransferMirror:
            return Blocks(
                hostOutput: .stereo, host: interleave(left, right), remoteLeft: left, remoteRight: right,
                flag: .pureFullRange)
        case .crossoverSplit:
            guard let dsp else { return nil }
            let count = left.count
            guard count > 0 else {
                return Blocks(hostOutput: .mono, host: [], remoteLeft: [], remoteRight: [], flag: .crossoverHPFMains)
            }
            var sub = [Float](repeating: 0, count: count)
            var mainsLeft = [Float](repeating: 0, count: count)
            var mainsRight = [Float](repeating: 0, count: count)
            left.withUnsafeBufferPointer { l in
                right.withUnsafeBufferPointer { r in
                    sub.withUnsafeMutableBufferPointer { s in
                        dsp.renderSub(
                            left: l.baseAddress!, right: r.baseAddress!, count: count, subGainDb: subGainDb,
                            phaseInvert: phaseInvert, into: s.baseAddress!)
                    }
                    mainsLeft.withUnsafeMutableBufferPointer { ml in
                        mainsRight.withUnsafeMutableBufferPointer { mr in
                            dsp.renderMains(
                                left: l.baseAddress!, right: r.baseAddress!, count: count,
                                outputLeft: ml.baseAddress!, outputRight: mr.baseAddress!)
                        }
                    }
                }
            }
            return Blocks(
                hostOutput: .mono, host: sub, remoteLeft: mainsLeft, remoteRight: mainsRight,
                flag: .crossoverHPFMains)
        }
    }

    /// Interleaves two channels as `L0 R0 L1 R1 …`, the order the Host's stereo output expects.
    static func interleave(_ left: [Float], _ right: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: left.count * 2)
        for index in left.indices {
            output[index * 2] = left[index]
            output[index * 2 + 1] = right[index]
        }
        return output
    }
}
