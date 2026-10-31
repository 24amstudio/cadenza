package app.cadenza.remote

import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.CadenzaDatabase
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class RemoteLogOutboxTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private lateinit var database: CadenzaDatabase

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
    fun aBatchIsReadInOrderAndDeletedOnlyByItsOwnIds() {
        database.queueLog("info", "command.sent", "one")
        database.queueLog("info", "command.sent", "two")
        database.queueLog("warning", "ui.error", "three")

        val first = database.pendingLogs(limit = 2)
        assertEquals(listOf("one", "two"), first.map { it.message })

        database.deleteLogs(first.map { it.id })
        assertEquals(listOf("three"), database.pendingLogs().map { it.message })
    }

    @Test
    fun anOverflowingOutboxKeepsTheNewestEntries() {
        repeat(205) { database.queueLog("info", "burst", "entry $it") }

        val remaining = database.pendingLogs(limit = 500)
        assertEquals(200, remaining.size)
        assertEquals("entry 5", remaining.first().message)
    }
}
