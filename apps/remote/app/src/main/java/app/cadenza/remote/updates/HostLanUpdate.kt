package app.cadenza.remote.updates

import android.content.Context
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.data.HostProfile
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Takes the Remote update from the paired Host over the LAN, so it needs no internet. The Host has verified the APK against
 * its signed release. This Remote checks the digest the Host reports and the APK's signing identity before it asks Android
 * to install. Downloads go in ranges and resume after a dropped connection.
 */
object HostLanUpdate {
    internal const val RANGE_BYTES = 4L * 1024 * 1024
    internal const val MAXIMUM_APK_BYTES = 128L * 1024 * 1024
    private const val MANIFEST_PATH = "/api/v1/updates/manifest"
    private const val CONNECT_MS = 5_000
    private const val READ_MS = 20_000
    private val VERSION = Regex("^[0-9]+\\.[0-9]+\\.[0-9]+(_[0-9]{8}\\.[0-9]+-[0-9a-f]{12})?$")
    private val SHA256 = Regex("^[0-9a-f]{64}$")

    data class Offer(
        val version: String,
        val buildNumber: Long,
        val sha256: String,
        val sizeBytes: Long,
        val downloadPath: String,
    )

    /** Parses the manifest body. Keys are snake case, like the rest of the protocol. */
    fun parseOffer(json: String): Offer = offerFrom(JSONObject(json))

    /** Reads the welcome's `update_manifest`, or the same object from the manifest endpoint. */
    fun offerFrom(value: JSONObject): Offer {
        val offer =
            Offer(
                version = value.getString("version"),
                buildNumber = value.getLong("build_number"),
                sha256 = value.getString("sha256"),
                sizeBytes = value.getLong("size_bytes"),
                downloadPath = value.getString("lan_download_path"),
            )
        require(
            VERSION.matches(offer.version) && SHA256.matches(offer.sha256) && offer.buildNumber > 0 &&
                offer.sizeBytes in 1..MAXIMUM_APK_BYTES && offer.downloadPath.startsWith("/api/v1/updates/remote/"),
        ) { "The Host offered an invalid Remote update." }
        return offer
    }

    /** The inclusive byte ranges that cover the APK from [offset] to [size], each at most [RANGE_BYTES] long. */
    fun rangesFrom(
        offset: Long,
        size: Long,
    ): List<LongRange> =
        (offset until size step RANGE_BYTES).map { start ->
            start..minOf(start + RANGE_BYTES - 1, size - 1)
        }

    /**
     * Downloads the APK the Host offers and commits the install. [welcomed] is the offer from the welcome; without one the
     * manifest endpoint is asked. Call from a background dispatcher.
     */
    fun update(
        context: Context,
        profile: HostProfile,
        token: String,
        hostBuild: Long,
        welcomed: Offer?,
    ) {
        check(BuildConfig.AUTOMATIC_UPDATES) { "Updates are disabled in this build." }
        val base = "http://${profile.address}:${profile.port}"
        val credentials = mapOf("X-Cadenza-Remote-Id" to profile.remoteId, "X-Cadenza-Remote-Token" to token)
        val offer =
            welcomed ?: parseOffer(readBytes(URL("$base$MANIFEST_PATH"), credentials, range = null, expected = 200).decodeToString())
        require(offer.buildNumber == hostBuild) { "The Host's update does not match its build." }
        val directory = File(context.filesDir, "updates").apply { mkdirs() }
        val partial = File(directory, "lan-${offer.buildNumber}.part")
        if (partial.length() > offer.sizeBytes) partial.delete()
        val url = URL("$base${offer.downloadPath}")
        for (range in rangesFrom(partial.length(), offer.sizeBytes)) {
            val bytes = readBytes(url, credentials, "bytes=${range.first}-${range.last}", expected = 206)
            check(bytes.size.toLong() == range.last - range.first + 1) { "The Host sent a short update range." }
            partial.appendBytes(bytes)
        }
        check(partial.length() == offer.sizeBytes) { "The Host update is incomplete." }
        check(digest(partial) == offer.sha256) { "The Host update does not match the digest the Host reported." }
        val file = File(directory, "Cadenza-Remote-${offer.version}.apk")
        check(partial.renameTo(file) || file.isFile) { "The Host update could not be staged." }
        RemoteUpdater.installFromHost(context, file, offer.buildNumber)
    }

    private fun readBytes(
        url: URL,
        credentials: Map<String, String>,
        range: String?,
        expected: Int,
    ): ByteArray {
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = CONNECT_MS
            connection.readTimeout = READ_MS
            credentials.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            range?.let { connection.setRequestProperty("Range", it) }
            val code = connection.responseCode
            // A 200 to a range request would be the whole APK, which must never be appended to a partial download.
            check(code == expected) { "The Host refused the update ($code)." }
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    private fun digest(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
