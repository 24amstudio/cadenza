package app.cadenza.remote.widget

import android.graphics.Bitmap
import android.graphics.Color
import android.util.LruCache
import androidx.palette.graphics.Palette

/**
 * The tint for the expanded widget. Extraction runs once per album: the result is cached by album key, so lyric and
 * play-state updates never reprocess the artwork. Call from a background dispatcher, since palette work is CPU-bound.
 */
object WidgetPaletteExtractor {
    private val cache = LruCache<String, Int>(ALBUM_CACHE_SIZE)

    fun accent(
        albumKey: String,
        bitmap: Bitmap,
    ): Int {
        cache[albumKey]?.let { return it }
        val palette = Palette.from(bitmap).maximumColorCount(COLOR_COUNT).generate()
        val color = palette.vibrantSwatch?.rgb ?: palette.dominantSwatch?.rgb ?: Color.DKGRAY
        cache.put(albumKey, color)
        return color
    }

    private const val ALBUM_CACHE_SIZE = 8
    private const val COLOR_COUNT = 16
}
