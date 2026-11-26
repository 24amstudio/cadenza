package app.cadenza.remote.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import androidx.core.graphics.ColorUtils
import app.cadenza.remote.R
import app.cadenza.remote.media.PlaybackMediaService

/**
 * What one widget render shows. [lyrics] is a [LYRIC_WINDOW]-line window around the active line, from [lyricWindow].
 * [artwork] is null when the cover is missing, and the layout then shows its themed fallback.
 */
data class WidgetContent(
    val title: String,
    val artist: String,
    val artwork: Bitmap?,
    val playing: Boolean,
    val lyrics: List<WidgetLyric>,
    val accent: Int?,
)

/**
 * Builds the responsive layouts with raw RemoteViews. Full renders include artwork. Partial renders carry only the lyric
 * lines and play icon, so the cover is not sent over Binder again when only the lyric changes.
 */
internal object WidgetViews {
    private val minimumHeights =
        mapOf(
            WidgetBucket.COMPACT to 40f,
            WidgetBucket.STANDARD to 110f,
            WidgetBucket.EXPANDED to 200f,
        )

    fun full(
        context: Context,
        content: WidgetContent,
    ): RemoteViews =
        RemoteViews(
            WidgetBucket.entries.associate { bucket ->
                SizeF(MINIMUM_WIDTH_DP, minimumHeights.getValue(bucket)) to build(context, bucket, content)
            },
        )

    fun partial(
        context: Context,
        bucket: WidgetBucket,
        content: WidgetContent,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, layoutFor(bucket))
        bindLyrics(views, bucket, content.lyrics)
        views.setImageViewResource(R.id.play, playIcon(content.playing))
        return views
    }

    private fun build(
        context: Context,
        bucket: WidgetBucket,
        content: WidgetContent,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, layoutFor(bucket))
        views.setTextViewText(R.id.title, content.title.ifEmpty { "Cadenza Remote" })
        views.setTextViewText(R.id.artist, content.artist)
        if (content.artwork != null) {
            views.setImageViewBitmap(R.id.art, content.artwork)
        } else {
            views.setImageViewResource(R.id.art, R.drawable.cadenza_mark)
        }
        views.setImageViewResource(R.id.play, playIcon(content.playing))
        // Only the expanded layout has a tint layer. A translucent tint keeps the text legible on any cover color.
        if (bucket == WidgetBucket.EXPANDED) {
            // The layer is a white rounded shape, so it stays invisible unless an accent color tints it.
            views.setViewVisibility(R.id.tint, if (content.accent != null) View.VISIBLE else View.INVISIBLE)
            content.accent?.let {
                val tint = ColorStateList.valueOf(ColorUtils.setAlphaComponent(it, TINT_ALPHA))
                views.setColorStateList(R.id.tint, "setImageTintList", tint)
            }
        }
        if (bucket != WidgetBucket.COMPACT) bindLyrics(views, bucket, content.lyrics)
        views.setOnClickPendingIntent(R.id.prev, action(context, "previous"))
        views.setOnClickPendingIntent(R.id.play, action(context, if (content.playing) "pause" else "play"))
        views.setOnClickPendingIntent(R.id.next, action(context, "next"))
        return views
    }

    private fun bindLyrics(
        views: RemoteViews,
        bucket: WidgetBucket,
        window: List<WidgetLyric>,
    ) {
        when (bucket) {
            WidgetBucket.COMPACT -> Unit
            WidgetBucket.STANDARD -> {
                bindLine(views, R.id.lyric_current, R.id.lyric_current_end, window[ACTIVE])
                bindLine(views, R.id.lyric_next, R.id.lyric_next_end, window[ACTIVE + 1])
            }
            WidgetBucket.EXPANDED ->
                window.forEachIndexed { index, line -> bindLine(views, LYRIC_IDS[index], LYRIC_END_IDS[index], line) }
        }
    }

    // A line is drawn by one of two views, one aligned to each edge. RemoteViews can set visibility, which keeps this
    // free of reflective gravity calls that a widget host might refuse.
    private fun bindLine(
        views: RemoteViews,
        startId: Int,
        endId: Int,
        line: WidgetLyric,
    ) {
        views.setTextViewText(startId, if (line.end) "" else line.text)
        views.setTextViewText(endId, if (line.end) line.text else "")
        views.setViewVisibility(startId, if (line.end) View.GONE else View.VISIBLE)
        views.setViewVisibility(endId, if (line.end) View.VISIBLE else View.GONE)
    }

    /** Starts the media service, so a tap never opens an Activity. */
    private fun action(
        context: Context,
        value: String,
    ): PendingIntent {
        val intent =
            Intent(context, PlaybackMediaService::class.java)
                .putExtra(PlaybackMediaService.EXTRA_TRANSPORT, value)
        return PendingIntent.getForegroundService(
            context,
            value.hashCode(),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    fun layoutFor(bucket: WidgetBucket): Int =
        when (bucket) {
            WidgetBucket.COMPACT -> R.layout.widget_now_playing_compact
            WidgetBucket.STANDARD -> R.layout.widget_now_playing_standard
            WidgetBucket.EXPANDED -> R.layout.widget_now_playing_expanded
        }

    private fun playIcon(playing: Boolean): Int = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play

    private const val MINIMUM_WIDTH_DP = 180f
    private const val TINT_ALPHA = 0x40
    private val LYRIC_IDS = listOf(R.id.lyric_0, R.id.lyric_1, R.id.lyric_2)
    private val LYRIC_END_IDS = listOf(R.id.lyric_0_end, R.id.lyric_1_end, R.id.lyric_2_end)
}
