import Foundation

/// Decides what the stage channel sends and when. It registers each track's suite, prefetches the next one ten seconds
/// before the end, fans transport commands out with a flush, optimistic state, and a clock calibration, and starts or
/// stops the audio transmitter. Music, artwork, and lyrics come from the Host, and each is passed in as a closure.
@MainActor
final class StageCoordinator {
    static let prefetchLeadMs: Int64 = 10_000

    let hub: StageHub
    let audio: StageAudioTransmitter
    let suites: StageSuiteStore
    /// The Cast presentation. Audio-only receivers get no track suite and no video.
    var presentation: () -> CastPresentationMode = { .auto }
    /// The Host's base URL on the LAN, such as `http://192.168.1.10:8765`. Nil until the listener is ready.
    var mediaBase: () -> String? = { nil }
    var lipSyncOffsetMs: () -> Int = { 0 }
    var playbackDelayMs: () -> Int64 = { 0 }
    var artwork: (URL) async -> Data? = { _ in nil }
    var motion: (String, String) async -> Data? = { _, _ in nil }
    var videoFile: (SongIdentity) async -> URL? = { _ in nil }
    var ac3Helper: () -> URL? = { nil }

    private var occurrenceId: String?
    private var budget: HostOperatingBudget = .unrestricted
    private var quality = "unknown"
    private var sentLyricsFor: String?
    private var prefetchedSuite: String?
    private var calibratePending = false

    init(hub: StageHub, audio: StageAudioTransmitter, suites: StageSuiteStore) {
        self.hub = hub
        self.audio = audio
        self.suites = suites
        suites.lipSyncOffsetMs = { [weak self] in self?.lipSyncOffsetMs() ?? 0 }
    }

    /// Called with every published snapshot and the lyric document in use.
    func snapshotChanged(_ snapshot: HostSnapshot, lyrics: LyricDocument?) {
        quality = snapshot.quality
        updateBudget(HostOperatingBudget(rawValue: snapshot.hostBudget ?? "") ?? .unrestricted)
        guard let current = snapshot.current else {
            occurrenceId = nil
            return
        }
        if current.occurrenceId != occurrenceId {
            occurrenceId = current.occurrenceId
            sentLyricsFor = nil
            publishSuite(for: current.song, lyrics: nil, occurrence: current.occurrenceId)
        }
        if let lyrics, lyrics.occurrenceId == current.occurrenceId, sentLyricsFor != current.occurrenceId {
            sentLyricsFor = current.occurrenceId
            publishSuite(for: current.song, lyrics: lyrics, occurrence: current.occurrenceId)
        }
        if calibratePending {
            calibratePending = false
            hub.broadcast(
                StageMessage.clockCalibrate(
                    actualPositionMs: current.positionMs, audioLatencyMs: Int(playbackDelayMs()),
                    hostMonoTimeMs: monotonicMs()))
        }
        prefetchIfNearEnd(snapshot: snapshot)
    }

    /// Under the `survival` budget receivers get stereo audio and synced lyrics only. Under `constrained` and above,
    /// motion artwork is not fetched, so receivers keep their static artwork.
    private func updateBudget(_ next: HostOperatingBudget) {
        guard next != budget else { return }
        budget = next
        audio.stereoOnly = next == .survival
        if audio.isRunning { audio.refreshRoutes() }
    }

    /// A transport command was dispatched. The flush and the optimistic state go out before Music answers. The clock
    /// follows once Music has confirmed the new position.
    func transportDispatched(isPlaying: Bool, targetPositionMs: Int64) {
        if audio.isRunning { audio.flush() }
        hub.broadcast(
            StageMessage.optimisticState(
                isPlaying: isPlaying, targetPositionMs: targetPositionMs, playbackRate: 1,
                hostMonoTimeMs: monotonicMs(), audioLatencyMs: Int(playbackDelayMs())))
        calibratePending = true
    }

    /// The Cast presentation, lowered to audio only at the `survival` budget.
    private func effectivePresentation() -> CastPresentationMode {
        budget == .survival ? .audioOnly : presentation()
    }

    /// Starts the audio transmitter while any approved receiver transmits, and stops it otherwise.
    func setTransmitting(sessionId: String, _ transmitting: Bool, format: CastTransmitChannelFormat) async throws {
        hub.setTransmitting(sessionId: sessionId, transmitting)
        if hub.approvedSessions.contains(where: \.isTransmitting) {
            try await audio.start(format: format, ac3Helper: ac3Helper())
        } else {
            audio.stop()
        }
    }

    private func prefetchIfNearEnd(snapshot: HostSnapshot) {
        guard let current = snapshot.current, let next = snapshot.queue.first,
            let duration = current.song.durationMs, duration > 0
        else { return }
        let nextId = StageTrackSuite.suiteId(for: next.song.identity)
        guard duration - current.positionMs <= Self.prefetchLeadMs, prefetchedSuite != nextId else { return }
        prefetchedSuite = nextId
        hub.broadcast(StageMessage.prefetch(trackId: nextId, reason: "near_end"))
        Task { await self.register(song: next.song, lyrics: nil) }
    }

    /// Registers the suite and publishes it at once. Artwork, motion, and a local video follow, and each one is added to
    /// the stored suite when it arrives, so a slow fetch never delays the track.
    private func publishSuite(for song: Song, lyrics: LyricDocument?, occurrence: String) {
        guard let base = mediaBase() else { return }
        let suiteId = StageTrackSuite.suiteId(for: song.identity)
        let previous = suites.entry(suiteId)
        let entry = StageSuiteStore.Entry(
            suiteId: suiteId, occurrenceId: occurrence,
            suite: StageTrackSuite.make(
                suiteId: suiteId, song: song, quality: quality, document: lyrics ?? previous?.lyrics, mediaBase: base),
            lyrics: lyrics ?? previous?.lyrics, artwork: previous?.artwork, motion: previous?.motion,
            videoFile: previous?.videoFile)
        suites.register(entry)
        if effectivePresentation() != .audioOnly {
            hub.publishSuite(StageMessage.trackSuite(entry.suite))
        }
        Task { await self.fetchMedia(for: song, suiteId: suiteId, occurrence: occurrence, base: base, lyrics: lyrics) }
    }

    private func register(song: Song, lyrics: LyricDocument?) async {
        guard let base = mediaBase() else { return }
        let suiteId = StageTrackSuite.suiteId(for: song.identity)
        let previous = suites.entry(suiteId)
        suites.register(
            StageSuiteStore.Entry(
                suiteId: suiteId, occurrenceId: "",
                suite: StageTrackSuite.make(
                    suiteId: suiteId, song: song, quality: quality, document: lyrics ?? previous?.lyrics,
                    mediaBase: base),
                lyrics: lyrics ?? previous?.lyrics, artwork: previous?.artwork, motion: previous?.motion,
                videoFile: previous?.videoFile))
        await fetchMedia(for: song, suiteId: suiteId, occurrence: nil, base: base, lyrics: lyrics)
    }

    private func fetchMedia(
        for song: Song, suiteId: String, occurrence: String?, base: String, lyrics: LyricDocument?
    ) async {
        if suites.entry(suiteId)?.artwork == nil, let url = song.artworkUrl.flatMap(URL.init(string:)),
            let data = await artwork(url)
        {
            suites.update(suiteId) { $0.artwork = data }
        }
        if suites.entry(suiteId)?.motion == nil, !song.album.isEmpty, budget < .constrained,
            let data = await motion(song.album, song.artist)
        {
            suites.update(suiteId) { $0.motion = data }
        }
        if suites.entry(suiteId)?.videoFile == nil, song.mediaType == .musicVideo,
            let file = await videoFile(song.identity)
        {
            suites.update(suiteId) { $0.videoFile = file }
            // The karaoke video is sent once its file is known, and only while its track is still the current one.
            guard let occurrence, occurrenceId == occurrence, effectivePresentation() != .audioOnly else { return }
            hub.broadcast(
                StageMessage.videoKaraoke(
                    mediaUrl: "\(base)/api/v1/cast/video/\(suiteId)/video.mp4",
                    subtitleUrl: "\(base)/api/v1/cast/video/\(suiteId)/lyrics.vtt",
                    userOffsetMs: lyrics?.userOffsetMs ?? 0))
        }
    }
}
