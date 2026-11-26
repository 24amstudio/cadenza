import Foundation

/// Decides where Music's audio and a music video's picture go. The Host alone makes this choice. A receiver never picks
/// its own route, and a standard Cast device never receives a catalog video.
enum CastRoutingCoordinator {
    enum Target: Equatable, Sendable {
        /// A Google Cast device found through `_googlecast._tcp`. Its screen comes from the `ca` record.
        case googleCast(CastDisplay)
        /// A Cadenza stage browser or Android TV receiver on the Host's stage channel.
        case stage
        /// An AirPlay 2 output such as an Apple TV, HomePod, or AirPlay TV.
        case airPlay
    }

    enum Content: Equatable, Sendable {
        case song
        /// A music video whose file is DRM-free and on disk in the Music library.
        case localMusicVideo
        /// A music video from the Apple Music catalog. Its picture is FairPlay or Widevine protected.
        case protectedMusicVideo
    }

    enum Route: Equatable, Sendable {
        /// The Default Media Receiver (`CC1AD845`) plays audio with track metadata.
        case defaultReceiverAudio
        /// The Default Media Receiver plays a DRM-free local music video with native WebVTT karaoke subtitles.
        case defaultReceiverVideo
        /// A stage receiver shows the Full Cadenza Suite beside the audio stream.
        case stageFullSuite
        /// A stage receiver plays audio alone.
        case stageAudio
        /// AirPlay plays audio alone.
        case airPlayAudio
        /// AirPlay plays a catalog video through the FairPlay HLS karaoke manifest proxy.
        case airPlayKaraokeProxy
    }

    /// The Default Media Receiver cannot draw the Full Cadenza Suite, so it plays audio unless a local video can show.
    static func route(for target: Target, content: Content, presentation: CastPresentationMode) -> Route {
        switch target {
        case .googleCast(let display):
            let showsLocalVideo = content == .localMusicVideo && display == .display && presentation != .audioOnly

            return showsLocalVideo ? .defaultReceiverVideo : .defaultReceiverAudio
        case .stage:
            return presentation == .audioOnly ? .stageAudio : .stageFullSuite
        case .airPlay:
            return content == .protectedMusicVideo ? .airPlayKaraokeProxy : .airPlayAudio
        }
    }
}
