package app.cadenza.remote.tv

import app.cadenza.remote.data.LyricLine
import app.cadenza.remote.data.LyricWord
import org.json.JSONArray
import org.json.JSONObject

/** The JSON messages a stage receiver gets from the Host. Unknown fields and out-of-range values are refused. */
internal sealed interface TvStageMessage {
    data class Pairing(
        val pin: String,
        val expiresInMs: Long,
    ) : TvStageMessage

    data class Accepted(
        val receiverToken: String,
    ) : TvStageMessage

    data class Suite(
        val suite: TvStageSuite,
    ) : TvStageMessage

    data class Prefetch(
        val trackId: String,
    ) : TvStageMessage

    data class Optimistic(
        val isPlaying: Boolean,
        val targetPositionMs: Long,
        val playbackRate: Double,
    ) : TvStageMessage

    data class Clock(
        val actualPositionMs: Long,
    ) : TvStageMessage

    data class Video(
        val mediaUrl: String,
        val subtitleUrl: String,
        val userOffsetMs: Long,
    ) : TvStageMessage
}

internal data class TvStageSuite(
    val trackId: String,
    val title: String,
    val artist: String,
    val album: String,
    val durationMs: Long,
    val quality: String?,
    val artworkUrl: String?,
    val motionUrl: String?,
    val lines: List<LyricLine>,
)

internal object TvStageMessages {
    private const val MAX_LINES = 2_000
    private val pinPattern = Regex("^[0-9]{4}$")
    private val lanUrlPattern = Regex("^http://[^/\\s]+/")
    private val actions = setOf("playback.pause", "playback.resume", "playback.skip", "playback.previous")
    private val suiteFields =
        setOf(
            "version",
            "type",
            "trackId",
            "title",
            "artist",
            "album",
            "durationMs",
            "quality",
            "artworkUrl",
            "motionUrl",
            "lines",
        )
    private val optimisticFields =
        setOf("version", "type", "isPlaying", "targetPositionMs", "playbackRate", "hostMonoTimeMs", "audioLatencyMs")
    private val fields =
        mapOf(
            "STAGE_PAIRING" to setOf("version", "type", "pin", "expiresInMs"),
            "STAGE_ACCEPTED" to setOf("version", "type", "receiverToken"),
            "TRACK_SUITE_PAYLOAD" to suiteFields,
            "PREFETCH_NEXT_SUITE" to setOf("version", "type", "trackId", "reason"),
            "OPTIMISTIC_STATE" to optimisticFields,
            "CLOCK_CALIBRATE" to setOf("version", "type", "actualPositionMs", "audioLatencyMs", "hostMonoTimeMs"),
            "VIDEO_KARAOKE_PAYLOAD" to setOf("version", "type", "source", "mediaUrl", "subtitleUrl", "userOffsetMs"),
        )

    /** Parses one text frame. Returns null for anything that breaks the contract, and the caller keeps its state. */
    fun parse(text: String): TvStageMessage? {
        val json = runCatching { JSONObject(text) }.getOrNull() ?: return null
        if (json.optInt("version", -1) != 1) return null
        val type = json.optString("type", "")
        val allowed = fields[type] ?: return null
        if (json.keys().asSequence().any { it !in allowed }) return null
        return when (type) {
            "STAGE_PAIRING" -> pairing(json)
            "STAGE_ACCEPTED" -> accepted(json)
            "TRACK_SUITE_PAYLOAD" -> suite(json)
            "PREFETCH_NEXT_SUITE" -> prefetch(json)
            "OPTIMISTIC_STATE" -> optimistic(json)
            "CLOCK_CALIBRATE" -> clock(json)
            "VIDEO_KARAOKE_PAYLOAD" -> video(json)
            else -> null
        }
    }

    /** The `RECEIVER_PROFILE` this receiver sends on connect. `codecs` lists only what the output can play. */
    fun profile(
        receiverId: String,
        displayName: String,
        channels: Int,
        codecs: List<String>,
        lipSyncOffsetMs: Int,
        token: String?,
    ): String {
        val json =
            JSONObject()
                .put("version", 1)
                .put("type", "RECEIVER_PROFILE")
                .put("receiverId", receiverId)
                .put("transportType", "cadenza_android_tv_receiver")
                .put("displayName", displayName)
                .put("hasDisplay", true)
                .put("isStandby", false)
                .put("isTouchSupported", false)
                .put("maxAudioChannels", channels)
                .put("supportedCodecs", JSONArray(codecs))
                .put("lipSyncOffsetMs", lipSyncOffsetMs)
        if (token != null) json.put("receiverToken", token)
        return json.toString()
    }

    /** The `STAGE_COMMAND` a TV remote key sends. Only an approved receiver's command runs on the Host. */
    fun command(action: String): String? =
        if (action in actions) {
            JSONObject()
                .put("version", 1)
                .put("type", "STAGE_COMMAND")
                .put("action", action)
                .toString()
        } else {
            null
        }

    /** The most characters of one log line the Host keeps. */
    const val LOG_MAX_LENGTH = 500

    /** The `STAGE_PLAYBACK` that says what this TV's audio track is playing now. */
    fun playback(
        codec: String,
        channels: Int,
        path: String,
        active: Boolean,
    ): String =
        JSONObject()
            .put("version", 1)
            .put("type", "STAGE_PLAYBACK")
            .put("codec", codec)
            .put("channels", channels)
            .put("path", path)
            .put("active", active)
            .toString()

    /** The `STAGE_LOG` that records one line on the Host. */
    fun log(
        level: String,
        message: String,
    ): String =
        JSONObject()
            .put("version", 1)
            .put("type", "STAGE_LOG")
            .put("level", level)
            .put("message", message.take(LOG_MAX_LENGTH))
            .toString()

    private fun pairing(json: JSONObject): TvStageMessage? {
        val pin = json.str("pin")?.takeIf { pinPattern.matches(it) } ?: return null
        val expires = json.counter("expiresInMs") ?: return null
        return TvStageMessage.Pairing(pin, expires)
    }

    private fun optimistic(json: JSONObject): TvStageMessage? {
        if (!json.has("isPlaying") || json.opt("isPlaying") !is Boolean) return null
        val target = json.counter("targetPositionMs") ?: return null
        val rate = json.optDouble("playbackRate", Double.NaN)
        if (!rate.isFinite() || rate <= 0.0 || rate > 4.0) return null
        if (json.counter("hostMonoTimeMs") == null || json.counter("audioLatencyMs") == null) return null
        return TvStageMessage.Optimistic(json.getBoolean("isPlaying"), target, rate)
    }

    private fun video(json: JSONObject): TvStageMessage? {
        if (json.str("source") != "lan_mp4") return null
        val media = json.str("mediaUrl")?.takeIf { isLan(it) } ?: return null
        val subtitle = json.str("subtitleUrl")?.takeIf { isLan(it) } ?: return null
        val offset = json.optLong("userOffsetMs", Long.MIN_VALUE)
        if (offset == Long.MIN_VALUE || offset !in -5_000L..5_000L) return null
        return TvStageMessage.Video(media, subtitle, offset)
    }

    private fun suite(json: JSONObject): TvStageMessage? {
        val trackId = json.str("trackId") ?: return null
        val title = json.str("title") ?: return null
        val artist = json.str("artist") ?: return null
        val album = json.str("album") ?: return null
        val duration = json.counter("durationMs") ?: return null
        val lineArray = json.optJSONArray("lines") ?: return null
        if (lineArray.length() > MAX_LINES) return null
        val lines = (0 until lineArray.length()).map { line(lineArray.optJSONObject(it) ?: return null) ?: return null }
        return TvStageMessage.Suite(
            TvStageSuite(
                trackId = trackId,
                title = title,
                artist = artist,
                album = album,
                durationMs = duration,
                quality = json.str("quality"),
                artworkUrl = json.str("artworkUrl")?.takeIf { isLan(it) },
                motionUrl = json.str("motionUrl")?.takeIf { isLan(it) },
                lines = lines,
            ),
        )
    }

    private fun accepted(json: JSONObject): TvStageMessage? =
        json.str("receiverToken")?.takeIf { it.length in 32..128 }?.let { TvStageMessage.Accepted(it) }

    private fun prefetch(json: JSONObject): TvStageMessage? = json.str("trackId")?.let { TvStageMessage.Prefetch(it) }

    private fun clock(json: JSONObject): TvStageMessage? = json.counter("actualPositionMs")?.let { TvStageMessage.Clock(it) }

    private fun line(json: JSONObject): LyricLine? {
        val id = json.str("id") ?: return null
        val text = json.str("text") ?: return null
        val start = json.counter("start_ms") ?: return null
        val end = json.counter("end_ms") ?: return null
        val wordArray = json.optJSONArray("words") ?: return null
        val words = (0 until wordArray.length()).map { word(wordArray.optJSONObject(it) ?: return null) ?: return null }
        return LyricLine(
            id = id,
            text = text,
            startMs = start,
            endMs = end,
            translation = json.str("translation"),
            words = words,
            align = json.str("align")?.takeIf { it == "center" || it == "end" } ?: "start",
        )
    }

    private fun word(json: JSONObject): LyricWord? {
        val text = json.str("text") ?: return null
        val start = json.counter("start_ms") ?: return null
        val end = json.counter("end_ms") ?: return null
        return LyricWord(text, start, end)
    }

    private fun isLan(url: String): Boolean = url.length <= 2_048 && lanUrlPattern.containsMatchIn(url)

    private fun JSONObject.str(key: String): String? = if (has(key) && opt(key) is String) getString(key) else null

    private fun JSONObject.counter(key: String): Long? {
        val value = opt(key) as? Number ?: return null
        val long = value.toLong()
        return if (long >= 0L && long.toDouble() == value.toDouble()) long else null
    }
}
