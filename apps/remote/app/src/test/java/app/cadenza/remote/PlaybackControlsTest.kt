package app.cadenza.remote

import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.Song
import app.cadenza.remote.ui.mayInterruptPlayback
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackControlsTest {
    @Test
    fun protectedRequestsKeepTheSameInterruptRulesInBothPlayerModes() {
        val current = CurrentPlayback("occurrence", "entry", "remote-b", "Remote B", Song("catalog", "song", "Title", "Artist"), 0, 0)
        val snapshot =
            HostSnapshot(
                hostId = "host",
                hostEpoch = "epoch",
                revision = 1,
                sequence = 1,
                hostTimeMs = 0,
                allowCrossRemoteEdits = false,
                playing = true,
                volume = 50,
                current = current,
                queue = emptyList(),
                totalRemainingMs = null,
                quality = "unknown",
                incoming = null,
                mixing = null,
                synchronized = true,
                issue = null,
                observationGap = false,
            )
        val profile = HostProfile("host", "Mac", "127.0.0.1", 1, "fingerprint", "remote-a")
        val state = RemoteState(profile = profile, connected = true, snapshot = snapshot)

        assertFalse(mayInterruptPlayback(state))
        assertTrue(mayInterruptPlayback(state.copy(snapshot = snapshot.copy(allowCrossRemoteEdits = true))))
        assertTrue(mayInterruptPlayback(state.copy(snapshot = snapshot.copy(current = current.copy(requestedBy = "remote-a")))))
        assertFalse(mayInterruptPlayback(state.copy(connected = false)))
        val unknownRequester = snapshot.copy(allowCrossRemoteEdits = true, current = current.copy(requestedBy = null))
        assertFalse(mayInterruptPlayback(state.copy(snapshot = unknownRequester)))
    }
}
