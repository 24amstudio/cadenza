package app.cadenza.remote.widget

/** What the widget last rendered. Artwork is part of the track, so it is sent only when the track changes. */
data class WidgetRenderKey(
    val trackId: String?,
    val playing: Boolean,
    val lyricIndex: Int?,
)

enum class WidgetUpdate {
    /** Nothing visible changed, so nothing is sent. */
    NONE,

    /** The track changed, so artwork and text are rebuilt. */
    FULL,

    /** Only the lyric line or the play icon changed. The artwork bitmap is not sent again. */
    PARTIAL,
}

object WidgetRenderGate {
    /**
     * [screenInteractive] is false while the screen is off. Lyric changes are then not rendered, because nobody can read
     * them. A play-state change still renders, so the icon never shows a stale state.
     */
    fun decide(
        previous: WidgetRenderKey?,
        next: WidgetRenderKey,
        screenInteractive: Boolean,
    ): WidgetUpdate =
        when {
            previous == next -> WidgetUpdate.NONE
            previous == null || previous.trackId != next.trackId -> WidgetUpdate.FULL
            previous.playing == next.playing && !screenInteractive -> WidgetUpdate.NONE
            else -> WidgetUpdate.PARTIAL
        }
}
