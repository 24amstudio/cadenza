package app.cadenza.remote.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.graphics.scale
import app.cadenza.remote.playback.NowPlayingSnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Pushes the shared now-playing state to every placed widget. Each widget remembers what it last showed, and the gate
 * decides whether a change needs a full render, a lyric-only partial, or nothing at all.
 */
object WidgetRenderer {
    private val lastRendered = mutableMapOf<Int, WidgetRenderKey>()
    private val currentLyricIndex = MutableStateFlow<Int?>(null)
    val lyricIndex: StateFlow<Int?> = currentLyricIndex.asStateFlow()

    fun publishLyricIndex(index: Int?) {
        currentLyricIndex.value = index
    }

    /** Forgets what each widget showed, so the next render sends everything. Used when the user unlocks the screen. */
    fun invalidate() {
        synchronized(lastRendered) { lastRendered.clear() }
    }

    fun forget(widgetIds: IntArray) {
        synchronized(lastRendered) { widgetIds.forEach(lastRendered::remove) }
    }

    fun render(
        context: Context,
        snapshot: NowPlayingSnapshot?,
        lyricIndex: Int?,
        screenInteractive: Boolean,
    ) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, CadenzaNowPlayingWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val key = WidgetRenderKey(snapshot?.occurrenceId, snapshot?.playing == true, lyricIndex)
        val content by lazy { content(context, snapshot, lyricIndex) }
        synchronized(lastRendered) {
            for (id in ids) {
                when (WidgetRenderGate.decide(lastRendered[id], key, screenInteractive)) {
                    WidgetUpdate.NONE -> continue
                    WidgetUpdate.FULL -> manager.updateAppWidget(id, WidgetViews.full(context, content))
                    WidgetUpdate.PARTIAL -> {
                        val bucket = bucketOf(manager, id)
                        manager.partiallyUpdateAppWidget(id, WidgetViews.partial(context, bucket, content))
                    }
                }
                lastRendered[id] = key
            }
        }
    }

    private fun content(
        context: Context,
        snapshot: NowPlayingSnapshot?,
        lyricIndex: Int?,
    ): WidgetContent {
        val artwork = snapshot?.artwork?.let(::decodeArtwork)
        val accent = snapshot?.let { current -> artwork?.let { WidgetPaletteExtractor.accent(current.occurrenceId, it) } }
        return WidgetContent(
            title = snapshot?.title.orEmpty(),
            artist = snapshot?.artist.orEmpty(),
            artwork = artwork,
            playing = snapshot?.playing == true,
            lyrics =
                lyricWindow(
                    snapshot
                        ?.lyrics
                        ?.lines
                        ?.map { WidgetLyric(text = it.text, end = it.align == "end") }
                        .orEmpty(),
                    lyricIndex,
                ),
            accent = accent,
        )
    }

    private fun bucketOf(
        manager: AppWidgetManager,
        id: Int,
    ): WidgetBucket {
        val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        return widgetBucketFor(height.toFloat().takeIf { it > 0f } ?: STANDARD_FALLBACK_DP)
    }

    /** The Host sends covers up to its own square size. The widget needs at most 256 pixels, so larger covers are scaled. */
    private fun decodeArtwork(bytes: ByteArray): Bitmap? {
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val side = minOf(decoded.width, decoded.height).coerceAtMost(ARTWORK_SIDE_PX)
        return decoded.scale(side, side)
    }

    private const val ARTWORK_SIDE_PX = 256
    private const val STANDARD_FALLBACK_DP = 150f
}
