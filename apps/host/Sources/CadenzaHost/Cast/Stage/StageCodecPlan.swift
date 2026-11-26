import Foundation

/// Chooses the encoder for one stage receiver from its profile, the channel count Music sends, and the transmit format.
/// Pure, so every rule can be tested without audio hardware.
enum StageCodecPlan {
    enum Route: Hashable, Sendable {
        /// Raw interleaved float PCM with two or six channels, with no container.
        case lpcm(channels: Int)
        /// AAC-LC fragments. Sources above stereo are folded to stereo.
        case aac
        /// AC-3 fragments for 5.1. Sources above 5.1 are folded to 5.1 first.
        case ac3
    }

    /// `nil` when the receiver cannot play any route for this source, so the Host sends it nothing.
    /// `stereoOnly` is set at the `survival` thermal budget. Then every receiver gets two channels, and AC-3 is not used.
    static func route(
        sourceChannels: Int, profile: StageReceiverProfile, format: CastTransmitChannelFormat, ac3Encoder: Bool,
        stereoOnly: Bool = false
    ) -> Route? {
        guard [2, 6, 8, 12].contains(sourceChannels) else { return nil }
        let supports: (String) -> Bool = { profile.supportedCodecs.contains($0) }
        let fiveOneReceiver = profile.maxAudioChannels >= 6 && !stereoOnly
        switch format {
        case .bitstream:
            guard supports("pcm") else { return nil }
            return .lpcm(channels: sourceChannels > 2 && fiveOneReceiver ? 6 : 2)
        case .transcodeAuto:
            if sourceChannels > 2, ac3Encoder, supports("ac-3"), fiveOneReceiver { return .ac3 }
            if supports("aac") { return .aac }
            if supports("pcm") { return .lpcm(channels: 2) }
            return nil
        }
    }
}

/// The transmit format that the listener chooses. Its wire names match Settings.
enum CastTransmitChannelFormat: String, Sendable, Equatable {
    case transcodeAuto = "transcode_auto"
    case bitstream
}
