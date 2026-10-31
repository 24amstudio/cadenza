package app.cadenza.remote.model

import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.Song

internal fun RemoteState.enrichArtwork(snapshot: HostSnapshot): HostSnapshot {
    val known =
        (
            favorites + results +
                listOfNotNull(
                    this.snapshot
                        ?.current
                        ?.song,
                ) +
                this.snapshot
                    ?.queue
                    .orEmpty()
                    .map { it.song }
        ).filter { it.artworkUrl != null }
            .associateBy { it.source + ":" + it.id }

    fun song(value: Song): Song = value.artworkUrl?.let { value } ?: known[value.source + ":" + value.id] ?: value
    return snapshot.copy(
        current = snapshot.current?.copy(song = song(snapshot.current.song)),
        queue = snapshot.queue.map { it.copy(song = song(it.song)) },
        incoming = snapshot.incoming?.let(::song),
    )
}
