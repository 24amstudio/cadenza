import Foundation

/// The one status line a Remote or the web Remote shows for a transmission. The Host builds it from the route it sends
/// and, for TV stage receivers, the playback the receiver reports. A line never names a codec or layout that the
/// receiver did not report playing.
struct CastRouteStatus: Codable, Equatable, Sendable {
    var text: String
    /// True when the receiver reports playing a different codec or layout than the Host sends.
    var mismatch: Bool

    /// The Mac's name as Remotes show it, such as "Darrell's MacBook Air".
    static let sourceName: String = Host.current().localizedName ?? "This Mac"

    /// "AC-3 5.1", "AAC stereo", or "PCM stereo".
    static func format(_ route: CastSnapshot.Route) -> String {
        let name: String
        switch route.codec {
        case "aac": name = "AAC"
        case "ac3": name = "AC-3"
        case "pcm": name = "PCM"
        default: name = route.codec.uppercased()
        }
        let layout: String
        switch route.channels {
        case 1: layout = "mono"
        case 2: layout = "stereo"
        case 6: layout = "5.1"
        case 8: layout = "7.1"
        default: layout = "\(route.channels) channels"
        }

        return "\(name) \(layout)"
    }

    /// A Google Cast line. Cast devices do not report playback, so the line says that it cannot be confirmed.
    static func cast(source: String, device: String, sent: CastSnapshot.Route) -> CastRouteStatus {
        CastRouteStatus(
            text: "\(source) → \(device): sends \(format(sent)). Google Cast does not report playback.",
            mismatch: false)
    }

    /// A TV stage line, from what the Host sends and what the receiver reported.
    static func stage(
        source: String, receiver: String, sent: CastSnapshot.Route, playback: StagePlayback
    ) -> CastRouteStatus {
        let sentText = "\(source) → \(receiver): sends \(format(sent))"
        switch playback {
        case .unreported:
            return CastRouteStatus(text: "\(sentText). \(receiver) has not reported playback.", mismatch: false)
        case .stopped:
            return CastRouteStatus(text: "\(sentText). \(receiver) is not playing.", mismatch: false)
        case .playing(let playing, _) where playing == sent:
            return CastRouteStatus(text: "\(sentText), and \(receiver) plays \(format(playing)).", mismatch: false)
        case .playing(let playing, _):
            return CastRouteStatus(text: "\(sentText), but \(receiver) plays \(format(playing)).", mismatch: true)
        }
    }
}

extension StageCodecPlan.Route {
    /// The route as the Host reports it: the codec, and the channel count the receiver is sent.
    var sentRoute: CastSnapshot.Route {
        switch self {
        case .lpcm(let channels): CastSnapshot.Route(codec: "pcm", channels: channels)
        case .aac: CastSnapshot.Route(codec: "aac", channels: 2)
        case .ac3: CastSnapshot.Route(codec: "ac3", channels: 6)
        }
    }
}
