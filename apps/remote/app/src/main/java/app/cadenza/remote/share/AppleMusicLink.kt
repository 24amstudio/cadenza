package app.cadenza.remote.share

import java.net.URI

/** A song, album, or playlist link from music.apple.com, as a browser or another app shares it. */
internal data class AppleMusicLink(
    val kind: Kind,
    val id: String,
    // The track an album link points at with `?i=`, when the link names one.
    val trackId: String?,
) {
    enum class Kind { SONG, ALBUM, PLAYLIST }

    companion object {
        private val identifier = Regex("^[A-Za-z0-9._-]{1,64}$")

        /** Finds the first Apple Music address in shared text. Other hosts and plain http links are refused. */
        fun parse(shared: String): AppleMusicLink? {
            val url =
                shared
                    .trim()
                    .split(Regex("\\s+"))
                    .firstOrNull { it.startsWith("https://music.apple.com/") }
                    ?: return null
            val uri = runCatching { URI(url) }.getOrNull() ?: return null
            if (uri.scheme != "https" || uri.host != "music.apple.com") return null
            val segments =
                uri.path
                    .orEmpty()
                    .split('/')
                    .filter { it.isNotEmpty() }
            val kindIndex = segments.indexOfFirst { it == "song" || it == "album" || it == "playlist" }
            if (kindIndex < 0 || kindIndex + 1 >= segments.size) return null
            val id = segments.last()
            if (!identifier.matches(id)) return null
            val track = trackParameter(uri.rawQuery)
            return when (segments[kindIndex]) {
                "song" -> AppleMusicLink(Kind.SONG, id, id)
                "album" -> AppleMusicLink(Kind.ALBUM, id, track)
                else -> AppleMusicLink(Kind.PLAYLIST, id, null)
            }
        }

        private fun trackParameter(query: String?): String? {
            val value = query?.split('&')?.firstOrNull { it.startsWith("i=") }?.removePrefix("i=") ?: return null
            return value.takeIf { identifier.matches(it) }
        }
    }
}
