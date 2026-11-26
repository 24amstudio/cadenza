package app.cadenza.remote.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetRenderGateTest {
    private val playing = WidgetRenderKey(trackId = "a", playing = true, lyricIndex = 2)

    @Test
    fun anUnchangedStateSendsNothing() {
        assertEquals(WidgetUpdate.NONE, WidgetRenderGate.decide(playing, playing, screenInteractive = true))
    }

    @Test
    fun aLyricChangeIsAPartialUpdateThatDoesNotResendTheArtwork() {
        val next = playing.copy(lyricIndex = 3)

        assertEquals(WidgetUpdate.PARTIAL, WidgetRenderGate.decide(playing, next, screenInteractive = true))
    }

    @Test
    fun aTrackChangeRebuildsTheWidget() {
        val next = playing.copy(trackId = "b", lyricIndex = null)

        assertEquals(WidgetUpdate.FULL, WidgetRenderGate.decide(playing, next, screenInteractive = true))
    }

    @Test
    fun lyricChangesPauseWhileTheScreenIsOffButPlayChangesStillRender() {
        assertEquals(
            WidgetUpdate.NONE,
            WidgetRenderGate.decide(playing, playing.copy(lyricIndex = 3), screenInteractive = false),
        )
        assertEquals(
            WidgetUpdate.PARTIAL,
            WidgetRenderGate.decide(playing, playing.copy(playing = false), screenInteractive = false),
        )
    }

    @Test
    fun aHeightMapsToItsResponsiveBucket() {
        assertEquals(WidgetBucket.COMPACT, widgetBucketFor(72f))
        assertEquals(WidgetBucket.STANDARD, widgetBucketFor(150f))
        assertEquals(WidgetBucket.EXPANDED, widgetBucketFor(260f))
    }
}
