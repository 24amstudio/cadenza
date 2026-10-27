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
        val status = SessionStatus(true, true, "Synthetic Mac", "Test song", "Artist", true, true)
        val notifications = SessionNotification(app)
        notifications.update(status)
        val notification = manager.activeNotifications.single { it.id == SessionNotification.ID }.notification
        assertEquals("Test song", notification.extras.getString(Notification.EXTRA_TITLE))
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertTrue(
            notification.extras
                .getString(Notification.EXTRA_TEXT)
                .orEmpty()
                .contains("Synthetic Mac"),
        )
        notifications.update(status.copy(connected = false))
        assertEquals(
            "Reconnecting to Synthetic Mac",
            manager.activeNotifications
                .single()
                .notification.extras
                .getString(Notification.EXTRA_TEXT),
        )
        notifications.update(status.copy(active = false))
        assertTrue(manager.activeNotifications.isEmpty())
    }
}
