package app.cadenza.remote.updates

import android.content.Context
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.data.UpdateConfiguration
import org.json.JSONObject

object Changelog {
    fun bundled(context: Context): String =
        runCatching {
            val data =
                context.assets
                    .open("changelog.json")
                    .bufferedReader()
                    .use { it.readText() }
            require(data.length <= 65_536)
            val entries = JSONObject(data).getJSONArray("releases")
            val current =
                (0 until entries.length()).map(entries::getJSONObject).firstOrNull {
                    it.getInt("build") ==
                        BuildConfig.VERSION_CODE
                }
            if (current == null) "No bundled notes for this build." else formatChanges(current)
        }.getOrDefault("Bundled changelog is unavailable. No release comparison was performed.")

    fun compare(config: UpdateConfiguration): String {
        val release = fetchReleaseMetadata(config).release
        return when {
            release.build < BuildConfig.VERSION_CODE ->
                "This installation is ahead of the published release. No newer release was found."
            release.build == BuildConfig.VERSION_CODE.toLong() && release.buildIdentity == BuildConfig.BUILD_ID ->
                "This build matches the published release."
            release.build == BuildConfig.VERSION_CODE.toLong() ->
                "The published release has the same version number and a different or unspecified build identity. " +
                    "No newer release was established."
            else ->
                "Changes from ${BuildConfig.VERSION_NAME} to ${release.version}:\n\n" +
                    relevantChanges(release, BuildConfig.VERSION_CODE.toLong())
        }
    }

    fun relevantChanges(
        release: VerifiedRelease,
        installedBuild: Long,
    ): String {
        val history = release.history.filter { it.build > installedBuild && it.build <= release.build }.sortedByDescending { it.build }
        if (history.isNotEmpty()) return history.joinToString("\n\n") { it.version + "\n" + it.changes.joinToString("\n") }
        return "Only notes for ${release.version} are available; intermediate releases are not included.\n\n" +
            release.changes.joinToString("\n\n").ifEmpty { "The publisher did not include signed change notes." }
    }

    fun formatChanges(value: JSONObject): String {
        val changes = value.getJSONArray("changes")
        require(changes.length() <= 100)
        return (0 until changes.length())
            .map {
                changes.getString(it).also { text ->
                    require(text.length in 1..1000)
                }
            }.joinToString("\n\n")
    }
}
