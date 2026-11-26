package app.cadenza.remote.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import app.cadenza.remote.playback.NowPlayingHub

/** Home-screen widget. The Host's state is pushed in by [WidgetObserver]; placement alone never polls anything. */
class CadenzaNowPlayingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        WidgetRenderer.invalidate()
        WidgetRenderer.render(
            context,
            NowPlayingHub.snapshot.value,
            WidgetRenderer.lyricIndex.value,
            screenInteractive = true,
        )
    }

    override fun onDeleted(
        context: Context,
        appWidgetIds: IntArray,
    ) {
        WidgetRenderer.forget(appWidgetIds)
    }
}
