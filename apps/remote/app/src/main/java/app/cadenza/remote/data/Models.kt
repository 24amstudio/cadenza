package app.cadenza.remote.data

import app.cadenza.remote.model.id
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Base64

data class SongIdentity(
    val source: String,
    val id: String,
) {
    fun json(): JSONObject = JSONObject().put("source", source).put("id", id)
}

data class Song(
    val source: String,
    val id: String,
    val title: String,
    val artist: String,
    val album: String = "",
    val durationMs: Long? = null,
    val artworkUrl: String? = null,
) {
    val identity: SongIdentity get() = SongIdentity(source, id)
}

data class QueueEntry(
    val id: String,
    val requestedBy: String?,
    val requesterName: String,
    val song: Song,
    val estimatedWaitMs: Long?,
    val estimatedStartHostMs: Long?,
    val estimateStatus: String?,
)

data class CurrentPlayback(
    val occurrenceId: String,
    val entryId: String?,
    val requestedBy: String?,
    val requesterName: String,
    val song: Song,
    val positionMs: Long,
    val sampledAtHostMs: Long,
)

data class SingSession(
    val status: String,
    val vocalPercent: Int,
    val latencyMs: Long?,
    val backend: String?,
    val modelRevision: String?,
    val issue: String?,
)

data class HostSnapshot(
    val hostId: String,
    val hostEpoch: String,
    val revision: Long,
    val sequence: Long,
    val hostTimeMs: Long,
    val allowCrossRemoteEdits: Boolean,
    val playing: Boolean,
    val volume: Int,
    val current: CurrentPlayback?,
    val queue: List<QueueEntry>,
    val totalRemainingMs: Long?,
    val quality: String,
    val incoming: Song?,
    val mixing: Boolean?,
    val synchronized: Boolean,
    val issue: String?,
    val observationGap: Boolean,
    val sing: SingSession? = null,
)

data class LyricLine(
    val id: String,
    val text: String,
    val startMs: Long,
    val endMs: Long,
    val translation: String?,
    val words: List<LyricWord> = emptyList(),
    val romanized: String? = null,
)

data class LyricWord(
    val text: String,
    val startMs: Long,
    val endMs: Long,
)

data class LyricDocument(
    val occurrenceId: String,
    val revision: String,
    val translationSource: String,
    val lines: List<LyricLine>,
    val issue: String?,
    val source: String = "apple_music",
) {
    /** 0: unavailable, 1: plain text, 2: timed lines, 3: timed words. */
    val level: Int
        get() =
            when {
                lines.isEmpty() -> 0
                lines.none { it.endMs > it.startMs } -> 1
                lines.all { line -> line.endMs > line.startMs && line.words.isNotEmpty() } -> 3
                else -> 2
            }
}

data class HostProfile(
    val hostId: String,
    val name: String,
    val address: String,
    val port: Int,
    val remoteId: String,
)

data class PairingInvitation(
    val host: String,
    val port: Int,
    val secret: String,
)

data class SongStatistic(
    val source: String,
    val songId: String,
    val title: String,
    val artist: String,
    val plays: Long,
    val playedMs: Long,
)

data class UpdateConfiguration(
    val repository: String = "",
    val publicKeySpkiBase64: String = "",
)

fun JSONObject.nullableString(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

fun JSONObject.counter(key: String): Long {
    val value = get(key)
    require(value is Number) { "Expected an integer for $key." }
    val number = value.toString().toBigDecimal().longValueExact()
    require(number in 0..Wire.MAXIMUM_COUNTER) { "Counter outside the supported range: $key." }
    return number
}

fun JSONObject.nullableLong(key: String): Long? = if (has(key) && !isNull(key)) counter(key) else null

fun JSONObject.identifier(key: String): String =
    getString(key).also {
        require(it.matches(Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"))) { "Invalid identifier: $key." }
    }

fun JSONObject.nullableBoolean(key: String): Boolean? = if (has(key) && !isNull(key)) getBoolean(key) else null

fun JSONArray.objects(): List<JSONObject> = (0 until length()).map(::getJSONObject)

object Wire {
    private val pairingMagic = byteArrayOf(0x43, 0x44, 0x5A, 0x50)
    private val pairingTextPrefix = "CDZP:".toByteArray(Charsets.US_ASCII)
    const val MAXIMUM_BYTES = 1_048_576
    const val MAXIMUM_COUNTER = 9_007_199_254_740_991L

    fun frame(type: String): JSONObject = JSONObject().put("version", 1).put("type", type)

    fun song(value: JSONObject): Song =
        Song(
            source = value.getString("source"),
            id = value.getString("id"),
            title = value.getString("title"),
            artist = value.getString("artist"),
            album = value.optString("album"),
            durationMs = value.nullableLong("duration_ms"),
            artworkUrl = value.nullableString("artwork_url"),
        ).also {
            require(it.title.length <= 500 && it.artist.length <= 500 && it.album.length <= 500) { "Song metadata is too long." }
            require(
                when (it.source) {
                    "catalog" -> it.id.matches(Regex("[0-9]{1,20}"))
                    "library" -> it.id.matches(Regex("[0-9A-F]{16}"))
                    "unknown" -> it.id.length in 1..128
                    else -> false
                },
            ) { "Invalid song identity." }
        }

    fun snapshot(value: JSONObject): HostSnapshot {
        val current =
            value.optJSONObject("current")?.let { item ->
                CurrentPlayback(
                    item.identifier("occurrence_id"),
                    item.nullableString("entry_id"),
                    item.nullableString("requested_by"),
                    item.getString("requester_name"),
                    song(item.getJSONObject("song")),
                    item.counter("position_ms"),
                    item.counter("sampled_at_host_ms"),
                )
            }
        val queue =
            value.getJSONArray("queue").objects().map { item ->
                QueueEntry(
                    item.getString("id"),
                    item.nullableString("requested_by"),
                    item.getString("requester_name"),
                    song(item.getJSONObject("song")),
                    item.nullableLong("estimated_wait_ms"),
                    item.nullableLong("estimated_start_host_ms"),
                    item.nullableString("estimate_status"),
                )
            }
        require(queue.size <= 256) { "The shared queue exceeds its limit." }
        val sing =
            value.optJSONObject("sing")?.let {
                SingSession(
                    it.getString("status"),
                    it.getInt("vocal_percent"),
                    it.nullableLong("latency_ms"),
                    it.nullableString("backend"),
                    it.nullableString("model_revision"),
                    it.nullableString("issue"),
                ).also { session ->
                    require(session.status in listOf("unavailable", "preparing", "ready", "active", "failed")) {
                        "Unknown Sing state."
                    }
                    require(session.vocalPercent in 0..100) { "Invalid Sing mix." }
                }
            }
        return HostSnapshot(
            value.identifier("host_id"),
            value.identifier("host_epoch"),
            value.counter("revision"),
            value.counter("sequence"),
            value.counter("host_time_ms"),
            value.getBoolean("allow_cross_remote_edits"),
            value.getBoolean("playing"),
            value.getInt("volume"),
            current,
            queue,
            value.nullableLong("total_remaining_ms"),
            value.optString("quality", "unknown"),
            value.optJSONObject("incoming")?.let(::song),
            value.nullableBoolean("mixing"),
            value.getBoolean("synchronized"),
            value.nullableString("issue"),
            value.optBoolean("observation_gap"),
            sing,
        ).also {
            require(it.volume in 0..100 && it.quality in listOf("unknown", "lossless", "hi_res_lossless", "dolby_atmos")) {
                "Invalid playback format or volume."
            }
            require(queue.map { entry -> entry.id }.toSet().size == queue.size) { "Duplicate queue request identity." }
        }
    }

    fun lyrics(value: JSONObject): LyricDocument {
        val lines =
            value.getJSONArray("lines").objects().map {
                val words =
                    it
                        .optJSONArray("words")
                        ?.objects()
                        ?.map { word ->
                            LyricWord(word.getString("text"), word.counter("start_ms"), word.counter("end_ms"))
                        }.orEmpty()
                require(words.size <= 1_000 && words.all { word -> word.text.length <= 1_000 && word.endMs >= word.startMs }) {
                    "Invalid lyric word timings or text."
                }
                LyricLine(
                    it.getString("id"),
                    it.getString("text"),
                    it.counter("start_ms"),
                    it.counter("end_ms"),
                    it.nullableString("translation"),
                    words,
                    it.nullableString("romanized"),
                )
            }
        require(
            lines.size <= 2_000 &&
                lines.all { it.endMs >= it.startMs && it.text.length <= 20_000 && (it.translation?.length ?: 0) <= 20_000 },
        ) { "Invalid lyric timings or text." }
        require(
            lines
                .map {
                    it.id
                }.toSet()
                .size == lines.size && lines.all { it.id.length in 1..128 },
        ) { "Invalid or repeated lyric line identity." }
        require(value.getString("translation_source") in listOf("none", "original", "apple", "machine", "apple_and_machine")) {
            "Unknown translation source."
        }
        val source = value.optString("source", "apple_music")
        require(source in listOf("apple_music", "lrclib", "unknown")) { "Unknown lyric source." }
        return LyricDocument(
            value.identifier("occurrence_id"),
            value.identifier("revision"),
            value.getString("translation_source"),
            lines,
            value.nullableString("issue"),
            source,
        )
    }

    fun invitation(payload: ByteArray): PairingInvitation {
        if (payload.hasPrefix(pairingTextPrefix)) {
            require(payload.size in (pairingTextPrefix.size + 1)..4_096) { "Pairing data is too large." }
            val encoded = payload.copyOfRange(pairingTextPrefix.size, payload.size).toString(Charsets.US_ASCII)
            require(encoded.matches(Regex("[A-Za-z0-9_-]+"))) { "This QR code is not a Cadenza Host invitation." }
            val decoded =
                runCatching { Base64.getUrlDecoder().decode(encoded) }
                    .getOrElse { throw IllegalArgumentException("This QR code is not a Cadenza Host invitation.") }
            require(decoded.size in 4..4_096) { "Pairing data is too large." }
            return binaryInvitation(decoded)
        }
        return binaryInvitation(payload)
    }

    private fun binaryInvitation(payload: ByteArray): PairingInvitation {
        require(payload.size in 4..4_096) { "Pairing data is too large." }
        val input = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
        val magic = ByteArray(pairingMagic.size)
        input.get(magic)
        require(magic.contentEquals(pairingMagic)) { "This QR code is not a Cadenza Host invitation." }
        require(input.get().toInt() == 3) { "Update Cadenza Host to pair with this Remote." }
        val host = readUtf8(input, input.get().toInt() and 0xff, "Host address")
        val port = input.short.toInt() and 0xffff
        val secret = readUtf8(input, input.get().toInt() and 0xff, "Pairing secret")
        require(!input.hasRemaining()) { "Invalid pairing envelope." }
        require(host.matches(Regex("[A-Za-z0-9.\\-:]{1,253}"))) { "Invalid Host address." }
        require(port in 1024..65535) { "Invalid Host address." }
        require(secret.length in 32..128) { "Invalid pairing identity." }
        return PairingInvitation(host, port, secret)
    }

    private fun readUtf8(
        input: ByteBuffer,
        length: Int,
        field: String,
    ): String {
        require(length in 1..253 && length <= input.remaining()) { "Invalid $field." }
        return ByteArray(length).also(input::get).toString(Charsets.UTF_8).also {
            require(it.toByteArray(Charsets.UTF_8).size == length && it.none(Char::isISOControl)) { "Invalid $field." }
        }
    }

    private fun ByteArray.hasPrefix(prefix: ByteArray): Boolean =
        size >= prefix.size && prefix.indices.all { index -> this[index] == prefix[index] }
}
