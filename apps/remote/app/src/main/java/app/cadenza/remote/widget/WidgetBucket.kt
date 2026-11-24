package app.cadenza.remote.widget

/** The three responsive buckets. Compact is a single cell row, standard adds lyrics, and expanded adds the full bar. */
enum class WidgetBucket { COMPACT, STANDARD, EXPANDED }

/** Height thresholds in dp. Each bucket needs its own RemoteViews, so a resize never forces a layout pass. */
fun widgetBucketFor(heightDp: Float): WidgetBucket =
    when {
        heightDp < 110f -> WidgetBucket.COMPACT
        heightDp < 200f -> WidgetBucket.STANDARD
        else -> WidgetBucket.EXPANDED
    }
