import Foundation

struct RemoteAudioQualityWindow: Equatable, Sendable {
    var networkDrops = 0
    var hostLoad = 0.0
    var hostBudget: HostOperatingBudget = .unrestricted
    var remoteUnderrunFrames = 0
    var remoteConcealedFrames = 0
    var remoteLongTaskMs = 0.0
}

enum RemoteAudioQualityReason: String, Sendable, Equatable {
    case steady
    case network
    case remotePlayout = "remote_playout"
    case hostLoad = "host_load"
    case hostPower = "host_power"
    case recovered
}

struct RemoteAudioQualityController: Equatable, Sendable {
    static let calmWindowsToUpgrade = 15
    static let severeNetworkDrops = 4
    static let severeUnderrunFrames = 48
    static let severeConcealedFrames = 96
    static let severeHostLoad = 0.6
    static let mildHostLoad = 0.35
    static let mildRemoteLongTaskMs = 100.0

    enum Severity: Equatable, Sendable { case calm, mild, severe }

    private(set) var quality: RemoteAudioQuality = .lossless
    private(set) var reason: RemoteAudioQualityReason = .steady
    private var calmWindows = 0

    static func verdict(
        for window: RemoteAudioQualityWindow
    ) -> (severity: Severity, reason: RemoteAudioQualityReason) {
        if window.networkDrops >= severeNetworkDrops {
            return (.severe, .network)
        }
        if window.remoteUnderrunFrames >= severeUnderrunFrames
            || window.remoteConcealedFrames >= severeConcealedFrames
        {
            return (.severe, .remotePlayout)
        }
        if window.hostBudget >= .constrained {
            return (.severe, .hostPower)
        }
        if window.hostLoad >= severeHostLoad {
            return (.severe, .hostLoad)
        }
        if window.networkDrops > 0 {
            return (.mild, .network)
        }
        if window.remoteLongTaskMs >= mildRemoteLongTaskMs {
            return (.mild, .remotePlayout)
        }
        if window.hostLoad >= mildHostLoad {
            return (.mild, .hostLoad)
        }
        if window.hostBudget >= .balanced {
            return (.mild, .hostPower)
        }
        return (.calm, .steady)
    }

    @discardableResult
    mutating func observe(_ window: RemoteAudioQualityWindow) -> RemoteAudioQuality? {
        let before = quality
        let verdict = Self.verdict(for: window)

        switch verdict.severity {
        case .severe:
            calmWindows = 0
            quality = RemoteAudioQuality(rawValue: quality.rawValue - 1) ?? .compact
            reason = verdict.reason
        case .mild:
            calmWindows = 0
            reason = verdict.reason
        case .calm:
            calmWindows += 1
            if calmWindows >= Self.calmWindowsToUpgrade, quality < .lossless {
                quality = RemoteAudioQuality(rawValue: quality.rawValue + 1) ?? .lossless
                calmWindows = 0
                reason = .recovered
            } else if quality == .lossless {
                reason = .steady
            }
        }

        return quality == before ? nil : quality
    }
}
