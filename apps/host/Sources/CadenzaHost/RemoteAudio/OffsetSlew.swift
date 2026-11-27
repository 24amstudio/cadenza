import Foundation

/// Moves a playout offset to a new goal in equal steps, so a calibration change is a glide over 500 ms, not a jump. The
/// offset is in microseconds, and each `advance` covers one capture block.
struct OffsetSlew: Equatable, Sendable {
    static let glideMs = 500.0

    private(set) var current: Double
    private(set) var goal: Double
    private var stepsLeft = 0

    init(current: Double) {
        self.current = current
        goal = current
    }

    /// Starts gliding toward `goal`. The glide takes `glideMs`, rounded to whole blocks, and it starts from `current`.
    mutating func setGoal(_ goal: Double, blockMs: Double) {
        guard goal != self.goal else { return }
        self.goal = goal
        stepsLeft = max(1, Int((Self.glideMs / blockMs).rounded()))
    }

    /// Advances one block and returns the offset that block uses.
    mutating func advance() -> Double {
        guard stepsLeft > 0 else { return current }
        stepsLeft -= 1
        current = stepsLeft == 0 ? goal : current + (goal - current) / Double(stepsLeft + 1)
        return current
    }
}
