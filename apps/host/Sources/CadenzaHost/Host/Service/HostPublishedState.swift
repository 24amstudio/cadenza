import AppKit
import Foundation

/// What the Host adds to each state snapshot beyond the queue: the thermal budget, the Cast devices, and the Cast
/// transmission. Cast discovery starts with the first snapshot and runs for the life of the Host.
@MainActor
final class HostPublishedState {
    var hostBudget: HostOperatingBudget = .unrestricted
    let castDiscovery = CastDiscovery()
    let castTransmitter = CastTransmitter()
    let videoLyrics = VideoLyricsOverlay()
    let stageHub: StageHub
    let stageSuites: StageSuiteStore
    let stage: StageCoordinator
    private var followedOccurrence: String?
    private(set) var videoOutputTarget = VideoOutputTarget.stored()
    private(set) var lipSyncOffsetMs = UserDefaults.standard.integer(forKey: "lipSyncOffsetMs")
    private(set) var castPresentation = CastPresentationMode.stored()

    init(stageReceiversFile: URL?) {
        let hub = StageHub(receivers: StageReceivers(file: stageReceiversFile))
        let suites = StageSuiteStore()
        stageHub = hub
        stageSuites = suites
        stage = StageCoordinator(hub: hub, audio: StageAudioTransmitter(hub: hub), suites: suites)
    }

    /// Chooses the Cast mode that the Cast device presents.
    func setCastPresentation(_ mode: CastPresentationMode) {
        castPresentation = mode
        UserDefaults.standard.set(mode.rawValue, forKey: CastPresentationMode.defaultsKey)
    }

    /// How Music's channels are sent to stage receivers: `transcode_auto` by default, or `bitstream` for raw PCM.
    var castTransmitFormat: CastTransmitChannelFormat {
        UserDefaults.standard.string(forKey: "castTransmitChannelFormat").flatMap(
            CastTransmitChannelFormat.init(rawValue:))
            ?? .transcodeAuto
    }

    /// The AVR delay that karaoke lines wait for, so a line appears with the sound the listener hears.
    func setLipSyncOffset(_ milliseconds: Int) {
        lipSyncOffsetMs = milliseconds
        UserDefaults.standard.set(milliseconds, forKey: "lipSyncOffsetMs")
    }

    /// Chooses where the karaoke line is shown. The Mac and a Cast device never show it at the same time.
    func setVideoOutputTarget(_ target: VideoOutputTarget) {
        videoOutputTarget = target
        UserDefaults.standard.set(target.rawValue, forKey: VideoOutputTarget.defaultsKey)
        if target == .castTransmitter { videoLyrics.show(line: nil) }
    }

    /// Sends the karaoke line of a music video that Music is playing to the chosen output. The Mac draws it in an overlay
    /// over Music's window, and a Cast receiver draws it on the device. Other items send nothing.
    func updateVideoLyrics(snapshot: HostSnapshot, lyrics: LyricDocument?) {
        guard let current = snapshot.current, current.song.mediaType == .musicVideo else {
            followedOccurrence = nil
            videoLyrics.show(line: nil)
            return
        }
        let lines = lyrics?.occurrenceId == current.occurrenceId ? (lyrics?.lines ?? []) : []
        let position = current.positionMs - Int64(lipSyncOffsetMs) - Int64(lyrics?.userOffsetMs ?? 0)
        let window = ActiveLyricLine.window(at: position, in: lines)
        switch videoOutputTarget {
        case .hostDisplay:
            if followedOccurrence != current.occurrenceId || !videoLyrics.isAttached {
                followedOccurrence = current.occurrenceId
                videoLyrics.follow(musicProcess: Self.musicProcessIdentifier())
            }
            videoLyrics.show(line: window.current?.text)
        case .castTransmitter:
            // A Cast device draws the karaoke as its own WebVTT track, so the Mac draws nothing.
            followedOccurrence = nil
            videoLyrics.show(line: nil)
        }
    }

    private static func musicProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: VideoLyricsVisibility.musicBundleIdentifier)
            .first?.processIdentifier
    }

    func apply(to snapshot: inout HostSnapshot) {
        snapshot.hostBudget = hostBudget.rawValue
        snapshot.videoOutput = videoOutputTarget.rawValue
        snapshot.lipSyncOffsetMs = lipSyncOffsetMs
        castDiscovery.start()
        snapshot.cast = CastSnapshot.make(
            devices: castDiscovery.devices, presentation: castPresentation, transmit: castTransmitter.state,
            transmitRoute: castTransmitter.route, stages: stageHub.snapshot(sourceName: CastRouteStatus.sourceName),
            pending: stageHub.receivers.pending)
    }
}
