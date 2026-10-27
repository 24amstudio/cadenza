package app.cadenza.remote

import android.app.Notification
import android.app.NotificationManager
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class SessionNotificationTest {
    @Test
    fun olderAndroidGetsAnOngoingSessionAndEndingItRemovesTheNotification() {
        val app = ApplicationProvider.getApplicationContext<CadenzaApplication>()
        val manager = app.getSystemService(NotificationManager::class.java)
        val status = SessionStatus(true, true, "Synthetic Cadenza Host", "Test song", "Artist", true, true)
        val notifications = SessionNotification(app)
        notifications.update(status)
        val notification = manager.activeNotifications.single { it.id == SessionNotification.ID }.notification
        assertEquals("Test song", notification.extras.getString(Notification.EXTRA_TITLE))
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertTrue(
            notification.extras
                .getString(Notification.EXTRA_TEXT)
                .orEmpty()
                .contains("Synthetic Cadenza Host"),
        )
        notifications.update(status.copy(connected = false))
        assertEquals(
            "Reconnecting to Synthetic Cadenza Host",
            manager.activeNotifications
                .single()
                .notification.extras
                .getString(Notification.EXTRA_TEXT),
        )
        assertEquals(
            "Unpin",
            manager.activeNotifications
                .single()
                .notification
                .actions
                .single()
                .title,
        )
        notifications.update(status.copy(playing = false))
        assertEquals(
            "Unpin",
            manager.activeNotifications
                .single()
                .notification
                .actions
                .single()
                .title,
        )
        notifications.update(status.copy(active = false))
        assertTrue(manager.activeNotifications.isEmpty())
    }
}
