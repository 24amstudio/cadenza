package app.cadenza.remote.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import app.cadenza.remote.energy.LocalEnergyProfile
import kotlinx.coroutines.withContext
import android.graphics.Color as AndroidColor

internal data class ArtworkHost(
    val cached: Map<String, ByteArray>,
    val request: (String) -> Unit,
)

internal val LocalArtworkHost = staticCompositionLocalOf<ArtworkHost?> { null }

internal data class ArtworkData(
    val image: ImageBitmap,
    val accent: Color,
)

private object ArtworkCache {
    private const val MAX_KILOBYTES = 12 * 1024
    private val images =
        object : LruCache<String, Bitmap>(MAX_KILOBYTES) {
            override fun sizeOf(
                key: String,
                value: Bitmap,
            ): Int = (value.allocationByteCount / 1024).coerceAtLeast(1)
        }

    @Synchronized
    fun get(url: String): Bitmap? = images.get(url)

    @Synchronized
    fun put(
        url: String,
        image: Bitmap,
    ) {
        images.put(url, image)
    }
}

// Rows and small covers never show more than about 300 px, so they decode far smaller than a Now Playing cover.
internal const val THUMBNAIL_EDGE_PX = 320

/** Decodes the cover of [url] no larger than [maxEdgePx], or the energy profile's cover size when it is null. */
@Composable
internal fun rememberArtwork(
    url: String?,
    maxEdgePx: Int? = null,
): ArtworkData? {
    val host = LocalArtworkHost.current
    val edge = maxEdgePx ?: LocalEnergyProfile.current.artworkMaxEdgePx
    val bytes = url?.let { host?.cached?.get(it) }
    var artwork by remember(url, bytes, edge) { mutableStateOf<ArtworkData?>(null) }
    LaunchedEffect(url, bytes, edge) {
        if (url == null) {
            artwork = null
        } else if (bytes != null) {
            artwork =
                try {
                    loadArtwork(url, bytes, edge)
                } catch (_: Exception) {
                    null
                }
        } else {
            artwork = ArtworkCache.get(cacheKey(url, edge))?.toArtworkData()
            if (artwork == null) host?.request(url)
        }
    }
    return artwork
}

// The decoded size is part of the key, so a cover decoded small for Saver is never shown large after the tier rises.
private fun cacheKey(
    url: String,
    edge: Int,
) = "$url#$edge"

private suspend fun loadArtwork(
    url: String,
    bytes: ByteArray,
    edge: Int,
): ArtworkData =
    withContext(kotlinx.coroutines.Dispatchers.Default) {
        val key = cacheKey(url, edge)
        ArtworkCache.get(key)?.toArtworkData() ?: decode(bytes, edge).also { image -> ArtworkCache.put(key, image) }.toArtworkData()
    }

private fun decode(
    bytes: ByteArray,
    edge: Int,
): Bitmap {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    require(bounds.outWidth in 1..2_048 && bounds.outHeight in 1..2_048)
    val sample = sampleSize(bounds.outWidth, bounds.outHeight, edge)
    val options =
        BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
    return requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)) {
        "The artwork could not be decoded."
    }
}

// The largest power-of-two reduction whose result still has at least three quarters of the wanted edge.
private fun sampleSize(
    width: Int,
    height: Int,
    edge: Int,
): Int {
    var sample = 1
    while (minOf(width, height) / (sample * 2) >= edge * 3 / 4) sample *= 2
    return sample
}

private fun Bitmap.toArtworkData(): ArtworkData = ArtworkData(asImageBitmap(), accentColor())

private fun Bitmap.accentColor(): Color {
    val stepX = (width / 16).coerceAtLeast(1)
    val stepY = (height / 16).coerceAtLeast(1)
    var red = 0L
    var green = 0L
    var blue = 0L
    var count = 0L
    for (y in 0 until height step stepY) {
        for (x in 0 until width step stepX) {
            val pixel = getPixel(x, y)
            if (AndroidColor.alpha(pixel) < 96) continue
            red += AndroidColor.red(pixel)
            green += AndroidColor.green(pixel)
            blue += AndroidColor.blue(pixel)
            count++
        }
    }
    if (count == 0L) return Color(0.24f, 0.27f, 0.34f)
    val r = red.toFloat() / count / 255f
    val g = green.toFloat() / count / 255f
    val b = blue.toFloat() / count / 255f
    return Color(r, g, b)
}
