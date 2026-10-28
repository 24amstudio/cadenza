package app.cadenza.remote

import android.database.sqlite.SQLiteConstraintException
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.CadenzaDatabase
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SqlStatements
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class DatabaseIntegrationTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private lateinit var database: CadenzaDatabase
    private val profile =
        HostProfile("test-host", "Test Cadenza Host", "10.0.0.5", 43127, TestCertificate.fingerprint, "remote-a", TestCertificate.encoded)

    @Before
    fun open() {
        app.database.close()
        app.deleteDatabase("cadence.sqlite")
        database = CadenzaDatabase(app)
    }

    @After
    fun close() {
        database.close()
    }

    @Test
    fun failedSettingsWritePreservesThePreviousIdentity() {
        database.saveSettings("identity" to "before")
        assertThrows(SQLiteConstraintException::class.java) {
            database.saveSettings("identity" to "after", "" to "invalid key")
        }
        assertEquals("before", database.setting("identity"))
        database.close()
        database = CadenzaDatabase(app)
        assertEquals("before", database.setting("identity"))
    }

    @Test
    fun creditsRemainExactlyOnceAfterMaintenanceAndReopen() {
        database.saveProfile(profile)
        database.remember(profile.hostId, listOf(Song("catalog", "123", "Synthetic song", "Test artist")))
        database.applyCredit(profile.hostId, credit(1, 5_000, 1))
        database.applyCredit(profile.hostId, credit(2, 3_000, 0))
        database.maintain()
        database.close()
        database = CadenzaDatabase(app)
        assertEquals(profile, database.profile(profile.hostId))
        assertEquals(2L, database.applyCredit(profile.hostId, credit(1, 5_000, 1)))
        assertEquals(2L, database.applyCredit(profile.hostId, credit(2, 3_000, 0)))
        assertEquals(3L, database.applyCredit(profile.hostId, credit(3, 2_000, 0)))
        val statistic = database.statistics(profile.hostId).single()
        assertEquals("Synthetic song", statistic.title)
        assertEquals(1L, statistic.plays)
        assertEquals(10_000L, statistic.playedMs)
    }

    @Test
    fun invalidCreditRollsBackCursorAndStatistics() {
        database.saveProfile(profile)
        database.applyCredit(profile.hostId, credit(1, 5_000, 1))
        assertThrows(SQLiteConstraintException::class.java) { database.applyCredit(profile.hostId, credit(3, 1_000, 0)) }
        assertThrows(SQLiteConstraintException::class.java) { database.applyCredit(profile.hostId, credit(2, 1_000, 1)) }
        assertEquals(1L, database.cursor(profile.hostId))
        assertEquals(5_000L, database.statistics(profile.hostId).single().playedMs)
        assertEquals(2L, database.applyCredit(profile.hostId, credit(2, 1_000, 0)))
        assertEquals(6_000L, database.statistics(profile.hostId).single().playedMs)
    }

    @Test
    fun unresolvedCommandsSurviveReopenAndKeepTheirPairingIdentity() {
        database.saveProfile(profile)
        val first = JSONObject().put("command_id", UUID(0, 1).toString()).put("operation", "first")
        val second = JSONObject().put("command_id", UUID(0, 2).toString()).put("operation", "second")
        database.savePending(profile, first, "queue:first")
        database.savePending(profile, second, "queue:second")
        database.close()
        database = CadenzaDatabase(app)
        assertEquals(listOf("queue:first", "queue:second"), database.pending(profile).map { it.second })
        assertEquals(emptyList<Pair<JSONObject, String>>(), database.pending(profile.copy(remoteId = "remote-b")))
        database.finishPending(profile, first.getString("command_id"))
        assertEquals(
            "second",
            database
                .pending(profile)
                .single()
                .first
                .getString("operation"),
        )
    }

    private fun credit(
        sequence: Long,
        duration: Long,
        count: Int,
    ): JSONObject =
        JSONObject()
            .put("sequence", sequence)
            .put("event_id", UUID(0, sequence).toString())
            .put("occurrence_id", UUID(1, 1).toString())
            .put("song", JSONObject().put("source", "catalog").put("id", "123"))
            .put("played_ms_delta", duration)
            .put("play_count_delta", count)
}
