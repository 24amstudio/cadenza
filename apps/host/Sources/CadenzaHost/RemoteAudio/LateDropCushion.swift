import Foundation

struct LateDropCushion: Equatable, Sendable {
    static let stepUs: UInt64 = 4_000
    static let decayUs: UInt64 = 1_000
    static let maximumBoostUs: UInt64 = 40_000

    private(set) var boostUs: UInt64 = 0
    private var lastLateDrops = 0

    mutating func observe(lateDrops: Int, remoteUnderrunFrames: Int) {
        if lateDrops > lastLateDrops || remoteUnderrunFrames > 0 {
            boostUs = min(boostUs + Self.stepUs, Self.maximumBoostUs)
        } else {
            boostUs -= min(boostUs, Self.decayUs)
        }
        lastLateDrops = lateDrops
    }
}
