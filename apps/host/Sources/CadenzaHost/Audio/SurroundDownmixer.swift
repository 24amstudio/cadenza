import Accelerate

/// Folds 5.1.2 and 7.1.4 interleaved frames into standard 5.1 (L, R, C, LFE, Ls, Rs) with -3 dB mixes of the height and
/// rear-top channels. Each output row is divided by the sum of its coefficients, so no output can exceed the largest
/// input. A 6-channel input is already 5.1 and passes through unchanged.
enum SurroundDownmixer {
    private static let halfPower: Float = 0.7071

    /// Rows are outputs and columns are inputs, in the order L, R, C, LFE, Ls, Rs.
    private static let matrices: [Int: [[Float]]] = [
        8: [
            [1, 0, 0, 0, 0, 0, halfPower, 0],
            [0, 1, 0, 0, 0, 0, 0, halfPower],
            [0, 0, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 1, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 0, 0],
        ],
        12: [
            [1, 0, 0, 0, 0, 0, 0, 0, halfPower, 0, 0, 0],
            [0, 1, 0, 0, 0, 0, 0, 0, 0, halfPower, 0, 0],
            [0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 1, 0, halfPower, 0, 0, 0, halfPower, 0],
            [0, 0, 0, 0, 0, 1, 0, halfPower, 0, 0, 0, halfPower],
        ],
    ]

    static func downmixed(_ samples: [Float], channels: Int) throws -> [Float] {
        if channels == 6 { return samples }
        guard let rows = matrices[channels].map(normalized), samples.count % channels == 0 else {
            throw CadenzaError.failure("unsupported_channels", "Cadenza can fold 5.1.2 and 7.1.4 audio into 5.1 only.")
        }
        let frames = samples.count / channels
        // vDSP_mmul multiplies frames x inputs by inputs x outputs, so the matrix is transposed into that layout.
        let transposed = (0..<channels).flatMap { input in rows.indices.map { rows[$0][input] } }
        var mixed = [Float](repeating: 0, count: frames * 6)
        vDSP_mmul(
            samples, 1, transposed, 1, &mixed, 1,
            vDSP_Length(frames), vDSP_Length(6), vDSP_Length(channels))
        var low: Float = -1
        var high: Float = 1
        var clipped = [Float](repeating: 0, count: mixed.count)
        vDSP_vclip(mixed, 1, &low, &high, &clipped, 1, vDSP_Length(mixed.count))
        return clipped
    }

    private static func normalized(_ rows: [[Float]]) -> [[Float]] {
        rows.map { row in
            let total = row.reduce(0) { $0 + abs($1) }
            return row.map { $0 / total }
        }
    }
}
