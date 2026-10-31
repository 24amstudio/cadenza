import Foundation

enum SingStemMixer {
    static func render(mix: Float, vocal: Float, vocalPercent: Int) -> Float {
        let ratio = Float(vocalPercent.clamped(to: 0...100)) / 100
        let reconstructed = (mix - vocal) + vocal * ratio
        return min(1, max(-1, reconstructed))
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
