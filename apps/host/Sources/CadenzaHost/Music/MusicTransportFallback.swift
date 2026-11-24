import Foundation

/// Routes that take over a transport action when Music refused Cadenza's Apple events. macOS refuses those before Music
/// runs the action, so a fallback cannot apply it twice. Any other failure can mean Music already acted, so it never
/// falls back.
enum MusicTransportFallback {
    static func isAutomationDenial(_ error: Error) -> Bool {
        guard case .failure(let code, let message)? = error as? CadenzaError else { return false }

        return code == "music_unavailable" && message.contains("(-1743)")
    }

    /// Pause and resume use MediaRemote's explicit commands only. A posted play/pause key toggles, so it could reverse
    /// the request.
    static func mediaRemoteCommand(for kind: String) -> MediaRemoteCommand? {
        switch kind {
        case "playback.pause": .pause
        case "playback.resume": .play
        case "playback.skip": .nextTrack
        case "playback.previous": .previousTrack
        default: nil
        }
    }

    /// Next and previous keys do not toggle, so posting one cannot reverse the request.
    static func mediaKey(for kind: String) -> MediaKey? {
        switch kind {
        case "playback.skip": .next
        case "playback.previous": .previous
        default: nil
        }
    }

    /// Returns false when no fallback route exists for the action, so the caller reports the original refusal.
    static func perform(_ kind: String) -> Bool {
        if let command = mediaRemoteCommand(for: kind), MediaRemote.send(command) { return true }
        guard let key = mediaKey(for: kind) else { return false }

        MediaKeys.post(key)
        return true
    }
}
