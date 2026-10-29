package app.cadenza.remote.updates

import app.cadenza.remote.BuildConfig
import app.cadenza.remote.data.Wire
import org.json.JSONObject
import java.io.File
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

data class ReleaseAsset(
    val filename: String,
    val sha256: String,
    val size: Long,
    val minimumOs: Int,
)

data class VerifiedRelease(
    val version: String,
    val build: Long,
    val tag: String,
    val asset: ReleaseAsset,
    val buildIdentity: String? = null,
    val changes: List<String> = emptyList(),
    val history: List<ReleaseNote> = emptyList(),
)

data class ReleaseNote(
    val build: Long,
    val version: String,
    val changes: List<String>,
)

object ReleaseVerifier {
    fun repositoryValid(value: String): Boolean =
        value.matches(Regex("[A-Za-z0-9][A-Za-z0-9_\\-]{0,38}/[A-Za-z0-9][A-Za-z0-9_.\\-]{0,99}")) && !value.contains("..")

    fun verify(
        data: ByteArray,
        signature: ByteArray,
        publicKey: String,
        repository: String,
        currentBuild: Long = BuildConfig.VERSION_CODE.toLong(),
        apiLevel: Int = android.os.Build.VERSION.SDK_INT,
    ): VerifiedRelease {
        require(data.size <= 65_536 && signature.size <= 128 && repositoryValid(repository)) { "Invalid release metadata." }
        val encoded = Base64.getDecoder().decode(publicKey)
        require(encoded.size <= 128) { "Invalid release key." }
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(encoded)) as ECPublicKey
        require(
            key.params.order.toString(16) == "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        ) { "Use a P-256 release key." }
        val verifier =
            Signature.getInstance("SHA256withECDSA").apply {
                initVerify(key)
                update(data)
            }
        require(verifier.verify(signature)) { "The update signature does not match the configured release key." }
        val manifest = JSONObject(data.toString(Charsets.UTF_8))
        val version = manifest.getString("version")
        val build = manifest.getLong("build")
        val versionPattern = Regex("[0-9]+\\.[0-9]+\\.[0-9]+(_[0-9]{8}\\.[0-9]+-[0-9a-f]{12})?")
        require(
            manifest.getInt("schema") == 1 && manifest.getInt("protocol_major") == 1 &&
                manifest.getString("repository") == repository && version.matches(versionPattern) &&
                manifest.getString("tag") == "v" + version && build > currentBuild &&
                build <= Wire.MAXIMUM_COUNTER,
        ) { "The update is incompatible or is not newer than this installation." }
        val assets = manifest.getJSONArray("assets")
        val matches = (0 until assets.length()).map(assets::getJSONObject).filter { it.getString("platform") == "android" }
        require(matches.size == 1) { "The release does not contain one Android package." }
        val item = matches.single()
        val filename = item.getString("filename")
        val digest = item.getString("sha256")
        val size = item.getLong("size")
        val minimum = item.getInt("minimum_os")
        require(
            filename == "Cadenza-Remote-" + version + ".apk" && digest.matches(Regex("[0-9a-f]{64}")) &&
                size in 1..134_217_728 && minimum in 26..apiLevel,
        ) { "The update package is incompatible with this device." }
        val identity = manifest.optString("build_id").takeIf { it.isNotEmpty() }
        require(identity == null || identity.matches(Regex("([0-9a-f]{40}|source-[0-9a-f]{64})"))) { "Invalid release build identity." }
        val notes = manifest.optJSONArray("changes")
        require(notes == null || notes.length() <= 100) { "The changelog is too large." }
        val changes =
            notes
                ?.let { rows ->
                    (0 until rows.length()).map { rows.getString(it).also { text -> require(text.length in 1..1000) } }
                }.orEmpty()
        val history = manifest.optJSONArray("changelog")
        require(history == null || history.length() <= 100)
        val releases =
            history
                ?.let { entries ->
                    (0 until entries.length()).map { index ->
                        val item = entries.getJSONObject(index)
                        val number = item.getLong("build")
                        val label = item.getString("version")
                        require(number in 1..build && label.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+")))
                        val texts = item.getJSONArray("changes")
                        require(texts.length() <= 100)
                        ReleaseNote(
                            number,
                            label,
                            (0 until texts.length()).map {
                                texts.getString(it).also { text ->
                                    require(text.length in 1..1000)
                                }
                            },
                        )
                    }
                }.orEmpty()
        require(releases.map { it.build }.distinct().size == releases.size)
        return VerifiedRelease(
            version,
            build,
            manifest.getString("tag"),
            ReleaseAsset(filename, digest, size, minimum),
            identity,
            changes,
            releases,
        )
    }

    fun verifyFile(
        file: File,
        asset: ReleaseAsset,
    ) {
        require(file.length() == asset.size) { "The update download is incomplete." }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(262_144)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        require(actual == asset.sha256) { "The update checksum does not match its signed manifest." }
    }
}
