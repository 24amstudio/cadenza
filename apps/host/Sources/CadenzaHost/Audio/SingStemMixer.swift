import Foundation

enum SingStemMixer {
    static func render(mix: Float, vocal: Float, vocalPercent: Int) -> Float {
        let ratio = Float(vocalPercent.clamped(to: 0...100)) / 100
        let reconstructed = (mix - vocal) + vocal * ratio
        return Swift.min(1, Swift.max(-1, reconstructed))
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
