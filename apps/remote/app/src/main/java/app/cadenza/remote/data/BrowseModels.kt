package app.cadenza.remote.data

import org.json.JSONObject

// What a browse page shows. album and artist pages are addressed by catalog id, or by a song the Host resolves
// itself. A playlist is addressed by its library id. The list of playlists needs neither.
data class BrowseTarget(
    val kind: String,
    val id: String? = null,
    val song: SongIdentity? = null,
    // Shown while the page loads, so a tapped row keeps its name on screen.
    val title: String = "",
) {
    // Two taps on the same thing share one request and one cached answer.
    val key: String get() = listOfNotNull(kind, id, song?.let { it.source + ":" + it.id }).joinToString("/")

    fun encode(): String = listOf(kind, id.orEmpty(), song?.source.orEmpty(), song?.id.orEmpty(), title).joinToString(SEPARATOR)

    fun request(): JSONObject =
        JSONObject().put("kind", kind).apply {
            id?.let { put("id", it) }
            song?.let { put("song", it.json()) }
        }

    companion object {
        private const val SEPARATOR = "\u001f"

        val playlists = BrowseTarget("playlists", title = "Playlists")

        fun album(song: Song) = BrowseTarget("album", song = song.identity, title = song.album.ifBlank { "Album" })

        fun artist(song: Song) = BrowseTarget("artist", song = song.identity, title = song.artist.ifBlank { "Artist" })

        fun of(item: BrowseItem.Collection) = BrowseTarget(item.kind, item.id, title = item.title)

        fun decode(text: String): BrowseTarget? {
            val parts = text.split(SEPARATOR)
            if (parts.size != 5) return null
            val song = if (parts[2].isNotEmpty() && parts[3].isNotEmpty()) SongIdentity(parts[2], parts[3]) else null
            return BrowseTarget(parts[0], parts[1].ifEmpty { null }, song, parts[4])
        }
    }
}

sealed interface BrowseItem {
    data class Track(
        val song: Song,
    ) : BrowseItem

    data class Collection(
        val kind: String,
        val id: String,
        val title: String,
        val subtitle: String?,
        val artworkUrl: String?,
    ) : BrowseItem
}

data class BrowseSection(
    val id: String,
    val title: String,
    val items: List<BrowseItem>,
)

data class BrowsePage(
    val kind: String,
    val id: String,
    val title: String,
    val subtitle: String?,
    val artworkUrl: String?,
    val detail: String?,
    val sections: List<BrowseSection>,
)

object BrowseWire {
    private val kinds = listOf("album", "artist", "playlists", "playlist")
    private val collections = listOf("album", "artist", "playlist")

    fun page(frame: JSONObject): BrowsePage {
        val value = frame.getJSONObject("browse")
        val kind = value.getString("kind")
        require(kind in kinds) { "Unknown browse page." }
        val sections = value.optJSONArray("sections")?.objects().orEmpty()
        require(sections.size <= 8) { "Too many browse sections." }
        return BrowsePage(
            kind = kind,
            id = value.optString("id"),
            title = value.getString("title").also { require(it.length <= 500) { "Browse title is too long." } },
            subtitle = value.nullableString("subtitle"),
            artworkUrl = value.nullableString("artwork_url"),
            detail = value.nullableString("detail"),
            sections = sections.map(::section),
        )
    }

    private fun section(value: JSONObject): BrowseSection {
        val items = value.getJSONArray("items").objects()
        require(items.size <= 200) { "Too many browse items." }
        return BrowseSection(value.getString("id"), value.getString("title"), items.map(::item))
    }

    private fun item(value: JSONObject): BrowseItem {
        val type = value.getString("type")
        if (type == "song") return BrowseItem.Track(Wire.song(value.getJSONObject("song")))
        require(type in collections) { "Unknown browse item." }
        return BrowseItem.Collection(
            type,
            value.getString("id"),
            value.getString("title").also { require(it.length <= 500) { "Browse title is too long." } },
            value.nullableString("subtitle"),
            value.nullableString("artwork_url"),
        )
    }
}
