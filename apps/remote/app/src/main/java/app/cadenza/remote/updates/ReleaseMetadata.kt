package app.cadenza.remote.updates

import app.cadenza.remote.data.UpdateConfiguration
import org.json.JSONObject

data class ReleaseMetadata(
    val manifest: ByteArray,
    val signature: ByteArray,
    val release: VerifiedRelease,
    val base: String,
)

fun fetchReleaseMetadata(config: UpdateConfiguration): ReleaseMetadata {
    require(ReleaseVerifier.repositoryValid(config.repository) && config.publicKeySpkiBase64.isNotBlank()) {
        "No release source is configured. No newer release was checked."
    }
    val metadata =
        JSONObject(
            GitHubDownload.bytes("https://api.github.com/repos/" + config.repository + "/releases/latest", 65_536).toString(Charsets.UTF_8),
        )
    check(!metadata.getBoolean("draft") && !metadata.getBoolean("prerelease")) { "A stable release is not available." }
    val tag = metadata.getString("tag_name")
    require(tag.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+"))) { "Unexpected release tag." }
    val base = "https://github.com/" + config.repository + "/releases/download/" + tag + "/"
    val data = GitHubDownload.bytes(base + "cadenza-release.json", 65_536)
    val signature = GitHubDownload.bytes(base + "cadenza-release.sig", 128)
    val verified = ReleaseVerifier.verify(data, signature, config.publicKeySpkiBase64, config.repository, currentBuild = 0)
    require(verified.tag == tag) { "The release tag does not match its signed manifest." }
    return ReleaseMetadata(data, signature, verified, base)
}
