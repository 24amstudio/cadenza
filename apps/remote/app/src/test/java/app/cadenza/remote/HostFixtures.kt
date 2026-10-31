package app.cadenza.remote

import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.QueueEntry
import app.cadenza.remote.data.Song

internal fun testSong(id: String) = Song(source = "catalog", id = id, title = "Song $id", artist = "Artist")

internal fun testEntry(id: String) =
    QueueEntry(
        id = id,
        requestedBy = "remote",
        requesterName = "Living room",
        song = testSong(id),
        estimatedWaitMs = null,
        estimatedStartHostMs = null,
        estimateStatus = null,
    )

internal fun testSnapshot(
    playing: Boolean = true,
    volume: Int = 40,
    current: CurrentPlayback? = null,
    queue: List<QueueEntry> = emptyList(),
) = HostSnapshot(
    hostId = "host",
    hostEpoch = "epoch",
    revision = 1,
    sequence = 1,
    hostTimeMs = 0,
    allowCrossRemoteEdits = true,
    playing = playing,
    volume = volume,
    current = current,
    queue = queue,
    totalRemainingMs = null,
    quality = "unknown",
    incoming = null,
    mixing = null,
    synchronized = true,
    issue = null,
    observationGap = false,
)
