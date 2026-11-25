package app.cadenza.remote.model

import app.cadenza.remote.data.Song
import kotlinx.coroutines.flow.update
import org.json.JSONObject

// The nudge is stored for the track on the Host, so the next visit starts from it. Only catalog and library tracks have
// an identity the Host can keep it under.
internal fun RemoteModel.setLyricDelay(milliseconds: Int) {
    val clamped = milliseconds.coerceIn(-5000, 5000)
    val current = mutable.value.snapshot?.current ?: return
    val song: Song = current.song
    if (song.source != "catalog" && song.source != "library") return
    mutable.update { it.copy(lyricDelayMs = clamped) }
    command(
        JSONObject()
            .put("kind", "lyrics.offset")
            .put("song", song.identity.json())
            .put("user_offset_ms", clamped),
        "lyrics.offset",
    )
}
