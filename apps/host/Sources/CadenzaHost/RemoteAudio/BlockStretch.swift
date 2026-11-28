enum BlockStretch {
    static func resample(_ samples: [Float], channels: Int, toFrames frames: Int) -> [Float] {
        let inputFrames = samples.count / channels
        guard frames > 0, inputFrames > 0 else { return [] }
        guard frames != inputFrames else { return samples }

        var output = [Float](repeating: 0, count: frames * channels)
        let ratio = Double(inputFrames) / Double(frames)
        for index in 0..<frames {
            let position = Double(index) * ratio
            let first = min(Int(position), inputFrames - 1)
            let second = min(first + 1, inputFrames - 1)
            let fraction = Float(position - Double(first))
            for channel in 0..<channels {
                let start = samples[first * channels + channel]
                let end = samples[second * channels + channel]
                output[index * channels + channel] = start + (end - start) * fraction
            }
        }
        return output
    }
}
