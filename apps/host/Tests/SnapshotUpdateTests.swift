import Testing

@testable import CadenzaHost

struct SnapshotUpdateTests {
    @Test func aHeartbeatCannotHidePermissionQueueOrObservationChanges() {
        let previous = HostSnapshot(
            hostId: "host", hostEpoch: "epoch", revision: 1, sequence: 1, hostTimeMs: 100,
            allowCrossRemoteEdits: false, playing: false, volume: 40, queue: []
        )
        var next = previous
        next.sequence = 2
        next.hostTimeMs = 200
        #expect(next.permitsHeartbeat(comparedTo: previous))
        next.observationGap = true
        #expect(!next.permitsHeartbeat(comparedTo: previous))
        next = previous
        next.allowCrossRemoteEdits = true
        #expect(!next.permitsHeartbeat(comparedTo: previous))
        next = previous
        next.playing = true
        #expect(!next.permitsHeartbeat(comparedTo: previous))
        next = previous
        next.queue = [
            QueueEntry(
                id: "entry", requesterName: "Tablet",
                song: Song(source: "catalog", id: "123", title: "Song", artist: "Artist"))
        ]
        #expect(!next.permitsHeartbeat(comparedTo: previous))
    }

    @Test func playbackTimeAloneCanBeCarriedByAHeartbeat() {
        let sent = playingSnapshot(sampledAt: 1_000, positionMs: 5_000, remainingMs: 90_000, waitMs: 30_000)
        var next = playingSnapshot(sampledAt: 2_000, positionMs: 6_000, remainingMs: 89_000, waitMs: 29_000)
        #expect(next.changedOnlyByPlaybackTime(since: sent))

        // A seek in Music, a stall, or a new track is not something the Remote can predict.
        next.current?.positionMs = 9_000
        #expect(!next.changedOnlyByPlaybackTime(since: sent))
        next = playingSnapshot(sampledAt: 2_000, positionMs: 6_000, remainingMs: 89_000, waitMs: 29_000)
        next.current?.occurrenceId = "next-occurrence"
        #expect(!next.changedOnlyByPlaybackTime(since: sent))
        next = playingSnapshot(sampledAt: 2_000, positionMs: 6_000, remainingMs: 89_000, waitMs: 29_000)
        next.volume = 55
        #expect(!next.changedOnlyByPlaybackTime(since: sent))
        next = playingSnapshot(sampledAt: 2_000, positionMs: 6_000, remainingMs: 89_000, waitMs: 29_000)
        next.queue.append(next.queue[0])
        #expect(!next.changedOnlyByPlaybackTime(since: sent))
    }

    private func playingSnapshot(
        sampledAt: Int64, positionMs: Int64, remainingMs: Int64, waitMs: Int64
    ) -> HostSnapshot {
        let song = Song(source: "catalog", id: "123", title: "Song", artist: "Artist", durationMs: 200_000)
        var snapshot = HostSnapshot(
            hostId: "host", hostEpoch: "epoch", revision: 1, sequence: 1, hostTimeMs: sampledAt,
            allowCrossRemoteEdits: false, playing: true, volume: 40,
            queue: [QueueEntry(id: "entry", requesterName: "Tablet", song: song, estimatedWaitMs: waitMs)])
        snapshot.current = CurrentPlayback(
            occurrenceId: "occurrence", requesterName: "Host", song: song,
            positionMs: positionMs, sampledAtHostMs: sampledAt)
        snapshot.totalRemainingMs = remainingMs
        return snapshot
    }

    @Test func unpackagedDevelopmentCannotEnableUpdates() {
        #expect(!HostBuild.updatesEnabled)
    }
}
