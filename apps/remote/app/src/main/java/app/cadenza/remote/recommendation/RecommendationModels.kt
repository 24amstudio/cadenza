package app.cadenza.remote.recommendation

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.util.UUID

data class RecommendationTrack(
    val source: String,
    val id: String,
    val artistId: String? = null,
    val albumId: String? = null,
    val versionId: String? = null,
) {
    val key: String get() = "$source:$id"
}

/** Wire vocabulary only. CREE learning weights are authoritative on Cadenza Host. */
enum class RecommendationOutcome(
    val wire: String,
) {
    QUALIFIED_PLAY("qualified_play"),
    EARLY_SKIP("early_skip"),
    LATE_SKIP("late_skip"),
    REPLAY("replay"),
    FAVORITE("favorite"),
    MANUAL_REPLACEMENT("manual_replacement"),
    QUEUE_REMOVAL("queue_removal"),
    INTERRUPTION("interruption"),
}

data class RecommendationFeedback(
    val recommendationId: String,
    val outcome: RecommendationOutcome,
    val track: RecommendationTrack,
    val positionMs: Long? = null,
    val durationMs: Long? = null,
    val replacement: RecommendationTrack? = null,
    val occurredAtMs: Long = System.currentTimeMillis(),
)

data class SignedRecommendationPassport(
    val payload: String,
    val publicKey: String,
    val signature: String,
) {
    fun json(): JSONObject =
        JSONObject()
            .put("payload_base64", payload)
            .put("public_key_base64", publicKey)
            .put("signature_base64", signature)
}

internal data class RecommendationPassport(
    val sequence: Long,
    val issuedAtMs: Long,
    val expiresAtMs: Long,
    val affinities: Map<String, Double>,
    val negative: Map<String, Double>,
    val recent: List<RecommendationTrack>,
    val transitions: Map<String, Double>,
    val noveltyBudget: Double,
    val intent: String?,
)

class RecommendationPassportSigner(
    private val alias: String,
) {
    private val store: KeyStore? by lazy {
        runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }.getOrNull()
    }
    private var fallback: java.security.KeyPair? = null

    @Synchronized
    private fun keyPair(): java.security.KeyPair {
        store?.let { secureStore ->
            val existing = secureStore.getEntry(alias, null) as? KeyStore.PrivateKeyEntry
            if (existing != null) return java.security.KeyPair(existing.certificate.publicKey, existing.privateKey)
            val generator = KeyPairGenerator.getInstance("EC", "AndroidKeyStore")
            generator.initialize(
                android.security.keystore.KeyGenParameterSpec
                    .Builder(
                        alias,
                        android.security.keystore.KeyProperties.PURPOSE_SIGN or
                            android.security.keystore.KeyProperties.PURPOSE_VERIFY,
                    ).setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
                    .setDigests(android.security.keystore.KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            return generator.generateKeyPair()
        }
        return fallback ?: KeyPairGenerator
            .getInstance("EC")
            .apply {
                initialize(java.security.spec.ECGenParameterSpec("secp256r1"))
            }.generateKeyPair()
            .also { fallback = it }
    }

    fun sign(payload: ByteArray): SignedRecommendationPassport {
        val pair = keyPair()
        val signature =
            Signature
                .getInstance("SHA256withECDSA")
                .apply {
                    initSign(pair.private)
                    update(payload)
                }.sign()
        return SignedRecommendationPassport(
            Base64.encodeToString(payload, Base64.NO_WRAP),
            Base64.encodeToString(rawPublicKey(pair.public), Base64.NO_WRAP),
            Base64.encodeToString(signature, Base64.NO_WRAP),
        )
    }

    private fun rawPublicKey(key: java.security.PublicKey): ByteArray {
        val ec = key as ECPublicKey

        fun coordinate(value: java.math.BigInteger): ByteArray {
            val bytes = value.toByteArray()
            return ByteArray(32).also { target ->
                bytes.copyInto(
                    target,
                    destinationOffset = (32 - bytes.size).coerceAtLeast(0),
                    startIndex = (bytes.size - 32).coerceAtLeast(0),
                )
            }
        }
        return coordinate(ec.w.affineX) + coordinate(ec.w.affineY)
    }
}

internal fun trackJson(track: RecommendationTrack): JSONObject =
    JSONObject()
        .put("source", track.source)
        .put("id", track.id)
        .apply {
            track.artistId?.let { put("artist_id", it) }
            track.albumId?.let { put("album_id", it) }
            track.versionId?.let { put("version_id", it) }
        }

internal fun passportJson(value: RecommendationPassport): JSONObject =
    JSONObject()
        .put("schema_version", 1)
        .put("model_version", 1)
        .put("sequence", value.sequence)
        .put("issued_at_ms", value.issuedAtMs)
        .put("expires_at_ms", value.expiresAtMs)
        .put("consent", "balanced")
        .put("disclosure", "balanced")
        .put("affinities", JSONObject(value.affinities))
        .put("negative_preferences", JSONObject(value.negative))
        .put("novelty_budget", value.noveltyBudget)
        .put("privacy_budget", 1.0)
        .apply {
            value.intent?.let { put("session_intent", it) }
            put("recent", JSONArray(value.recent.take(100).map(::trackJson)))
            put(
                "transitions",
                JSONArray(
                    value.transitions.entries.take(512).map {
                        val from = it.key.substringBefore("->").split(":", limit = 2)
                        val to = it.key.substringAfter("->").split(":", limit = 2)
                        JSONObject()
                            .put("from", trackJson(RecommendationTrack(from[0], from.getOrElse(1) { "" })))
                            .put("to", trackJson(RecommendationTrack(to[0], to.getOrElse(1) { "" })))
                            .put("weight", it.value)
                            .put("source", "remote")
                            .put("confidence", 0.8)
                            .put("freshness_ms", value.issuedAtMs)
                    },
                ),
            )
            put("provenance", JSONObject())
        }

internal fun emptyPassport(
    sequence: Long,
    nowMs: Long,
): RecommendationPassport =
    RecommendationPassport(
        sequence = sequence,
        issuedAtMs = nowMs,
        expiresAtMs = nowMs + 24 * 60 * 60 * 1000,
        affinities = emptyMap(),
        negative = emptyMap(),
        recent = emptyList(),
        transitions = emptyMap(),
        noveltyBudget = 0.5,
        intent = null,
    )

fun newRecommendationId(): String = UUID.randomUUID().toString()
