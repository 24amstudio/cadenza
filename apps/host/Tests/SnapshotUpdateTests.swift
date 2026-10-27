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

    @Test func unpackagedDevelopmentCannotEnableUpdates() {
        #expect(!HostBuild.updatesEnabled)
    }
}
