package app.cadenza.remote.data

import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.core.database.sqlite.transaction
import org.json.JSONObject

enum class ThemePreference(
    val label: String,
) {
    SYSTEM("Follow system"),
    LIGHT("Light"),
    DARK("Dark"),
}

fun deviceName(context: Context): String {
    val configured = runCatching { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) }.getOrNull()
    return configured?.trim()?.takeIf { it.isNotEmpty() }?.take(80)
        ?: Build.MODEL
            .trim()
            .take(80)
            .ifEmpty { "Android Remote" }
}

fun Song.json(): JSONObject =
    identity
        .json()
        .put("title", title)
        .put("artist", artist)
        .put("album", album)
        .put("duration_ms", durationMs ?: JSONObject.NULL)
        .put("artwork_url", artworkUrl ?: JSONObject.NULL)

data class FavoriteLibrary(
    val songs: List<Song>,
    val unreadable: Int,
)

class RemoteLibrary(
    private val database: CadenzaDatabase,
) {
    @Synchronized
    fun load(): FavoriteLibrary {
        val songs = mutableListOf<Song>()
        var unreadable = 0
        database.readableDatabase
            .rawQuery(
                "SELECT source,song_id,song_json FROM favorites ORDER BY saved_at_ms DESC,source,song_id",
                null,
            ).use { rows ->
                while (rows.moveToNext()) {
                    val song =
                        runCatching {
                            val text = rows.getString(2)
                            require(text.length <= 16384)
                            Wire.song(JSONObject(text)).also {
                                require(it.source == rows.getString(0) && it.id == rows.getString(1))
                            }
                        }.getOrNull()
                    if (song == null) unreadable++ else songs.add(song)
                }
            }
        return FavoriteLibrary(songs, unreadable)
    }

    @Synchronized
    fun setFavorite(
        song: Song,
        saved: Boolean,
    ) {
        val json = song.json().toString()
        Wire.song(JSONObject(json))
        require(song.source in listOf("catalog", "library") && json.length <= 16384) { "This song cannot be saved." }
        val db = database.writableDatabase
        db.transaction {
            if (!saved) {
                db.delete("favorites", "source=? AND song_id=?", arrayOf(song.source, song.id))
            } else {
                db.rawQuery("SELECT count(*) FROM favorites WHERE NOT (source=? AND song_id=?)", arrayOf(song.source, song.id)).use {
                    check(it.moveToFirst() && it.getInt(0) < 1000) { "Favorites is full. Remove a song before adding another." }
                }
                db.execSQL(
                    "INSERT OR REPLACE INTO favorites(source,song_id,song_json,saved_at_ms) VALUES(?,?,?,?)",
                    arrayOf<Any>(song.source, song.id, json, System.currentTimeMillis()),
                )
            }
        }
    }
}
