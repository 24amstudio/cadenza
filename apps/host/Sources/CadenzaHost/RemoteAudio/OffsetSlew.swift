import Foundation

struct OffsetSlew: Equatable, Sendable {
    static let glideMs = 500.0
    static let maximumStepSamples = 4.0
    static let peakSlope = 1.5

    private(set) var current: Double
    private(set) var goal: Double
    private let sampleRate: Double
    private let blockMs: Double
    private var origin: Double
    private var totalSteps = 0
    private var step = 0

    init(current: Double, sampleRate: Double, blockMs: Double) {
        self.current = current
        goal = current
        origin = current
        self.sampleRate = sampleRate
        self.blockMs = blockMs
    }

    mutating func setGoal(_ goal: Double) {
        guard goal != self.goal else { return }
        self.goal = goal
        origin = current
        let changeSamples = abs(goal - current) * sampleRate / 1_000_000
        let stepsByTime = Int((Self.glideMs / blockMs).rounded())
        let stepsByChange = Int((Self.peakSlope * changeSamples / Self.maximumStepSamples).rounded(.up))
        totalSteps = max(1, stepsByTime, stepsByChange)
        step = 0
    }

    /// Advances one block and returns the offset that block uses.
    mutating func advance() -> Double {
        guard step < totalSteps else { return current }
        step += 1
        if step == totalSteps {
            current = goal
        } else {
            let t = Double(step) / Double(totalSteps)
            current = origin + (goal - origin) * (t * t * (3 - 2 * t))
        }
        return current
    }

    func peekNext() -> Double {
        var copy = self
        return copy.advance()
    }
}
