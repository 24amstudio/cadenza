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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import app.cadenza.remote.data.readBounded
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import android.graphics.Color as AndroidColor

internal data class ArtworkData(
    val image: ImageBitmap,
    val accent: Color,
)

private object ArtworkCache {
    private const val MAX_KILOBYTES = 12 * 1024
    private const val FAILURE_TTL_MS = 30_000L
    private val images =
        object : LruCache<String, Bitmap>(MAX_KILOBYTES) {
            override fun sizeOf(
                key: String,
                value: Bitmap,
            ): Int = (value.allocationByteCount / 1024).coerceAtLeast(1)
        }
    private val failures = mutableMapOf<String, Long>()

    @Synchronized
    fun get(url: String): Bitmap? {
        val failure = failures[url]
        if (failure != null && failure > System.currentTimeMillis()) return null
        if (failure != null) failures.remove(url)
        return images.get(url)
    }

    @Synchronized
    fun put(
        url: String,
        image: Bitmap,
    ) {
        failures.remove(url)
        images.put(url, image)
    }

    @Synchronized
    fun markFailure(url: String) {
        failures[url] = System.currentTimeMillis() + FAILURE_TTL_MS
        if (failures.size > 64) {
            failures.entries.removeIf { it.value <= System.currentTimeMillis() }
        }
    }
}

@Composable
internal fun rememberArtwork(url: String?): ArtworkData? {
    var artwork by remember(url) { mutableStateOf<ArtworkData?>(null) }
    LaunchedEffect(url) {
        artwork = url?.let { loadArtwork(it) }
    }
    return artwork
}

private suspend fun loadArtwork(url: String): ArtworkData? {
    val cached = ArtworkCache.get(url)
    if (cached != null) return cached.toArtworkData()
    val image =
        withContext(Dispatchers.IO) {
            runCatching {
                val address = URL(url)
                require(address.protocol == "https" && address.userInfo == null)
                require(address.host != "mzstatic.com" && address.host.endsWith(".mzstatic.com"))
                val connection = address.openConnection() as HttpsURLConnection
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                try {
                    require(connection.responseCode == 200)
                    val bytes = connection.inputStream.use { it.readBounded(524_288) }
                    decode(bytes)
                } finally {
                    connection.disconnect()
                }
            }.getOrNull()
        }
    if (image == null) {
        ArtworkCache.markFailure(url)
        return null
    }
    ArtworkCache.put(url, image)
    return image.toArtworkData()
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
