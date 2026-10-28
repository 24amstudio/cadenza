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

@Composable
internal fun rememberArtwork(url: String?): ArtworkData? {
    val host = LocalArtworkHost.current
    val bytes = url?.let { host?.cached?.get(it) }
    var artwork by remember(url, bytes) { mutableStateOf<ArtworkData?>(null) }
    LaunchedEffect(url, bytes) {
        if (url == null) {
            artwork = null
        } else if (bytes != null) {
            artwork =
                try {
                    loadArtwork(url, bytes)
                } catch (_: Exception) {
                    null
                }
        } else {
            host?.request(url)
            artwork = ArtworkCache.get(url)?.toArtworkData()
        }
    }
    return artwork
}

private suspend fun loadArtwork(
    url: String,
    bytes: ByteArray,
): ArtworkData =
    withContext(kotlinx.coroutines.Dispatchers.Default) {
        ArtworkCache.get(url)?.toArtworkData() ?: decode(bytes).also { image -> ArtworkCache.put(url, image) }.toArtworkData()
    }

private fun decode(bytes: ByteArray): Bitmap {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    require(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds) != null)
    require(bounds.outWidth in 1..2_048 && bounds.outHeight in 1..2_048)
    val sample = sampleSize(bounds.outWidth, bounds.outHeight)
    val options =
        BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
    return requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)) {
        "The artwork could not be decoded."
    }
}

private fun sampleSize(
    width: Int,
    height: Int,
): Int {
    var sample = 1
    while (width / sample > 1_024 || height / sample > 1_024) sample *= 2
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
