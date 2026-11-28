package app.cadenza.remote

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal fun syntheticHostSnapshot(
    hostId: String,
    remoteId: String,
    emptyQueue: Boolean,
    playing: Boolean = false,
    sing: Boolean = false,
): JSONObject {
    val queue = JSONArray()
    if (!emptyQueue) {
        queue.put(entry(4, remoteId, "Android Remote", "A long requested song title with several words", 210_000, 150_000))
        queue.put(entry(5, UUID(0, 3).toString(), "Living room", "Second request", 90_000, 360_000))
    }
    return JSONObject()
        .put("host_id", hostId)
        .put("host_epoch", UUID(0, 10).toString())
        .put("revision", 1)
        .put("sequence", 1)
        .put("host_time_ms", 1_000)
        .put("allow_cross_remote_edits", false)
        .put("playing", playing)
        .put("volume", 40)
        .put("quality", "unknown")
        .put(
            "current",
            JSONObject()
                .put("occurrence_id", UUID(0, 11).toString())
                .put("entry_id", UUID(0, 12).toString())
                .put("requested_by", UUID(0, 3).toString())
                .put("requester_name", "Living room")
                .put("song", syntheticSong("Current song", 180_000))
                .put("position_ms", 30_000)
                .put("sampled_at_host_ms", 1_000),
        ).put("queue", queue)
        .put("total_remaining_ms", if (emptyQueue) 150_000 else 450_000)
        .put("synchronized", true)
        .apply {
            if (sing) {
                put(
                    "sing",
                    JSONObject()
                        .put("status", "ready")
                        .put("vocal_percent", 0)
                        .put("latency_ms", 20)
                        .put("backend", "stereo-center")
                        .put("model_revision", "dsp-1"),
                )
            }
        }.put("observation_gap", false)
}

private fun entry(
    id: Long,
    owner: String,
    name: String,
    title: String,
    duration: Long,
    wait: Long,
): JSONObject =
    JSONObject()
        .put("id", UUID(0, id).toString())
        .put("requested_by", owner)
        .put("requester_name", name)
        .put("song", syntheticSong(title, duration))
        .put("estimated_wait_ms", wait)

internal fun syntheticSong(
    title: String,
    duration: Long,
): JSONObject =
    JSONObject()
        .put(
            "source",
            "catalog",
        ).put("id", "123")
        .put("title", title)
        .put("artist", "Synthetic artist")
        .put("duration_ms", duration)
