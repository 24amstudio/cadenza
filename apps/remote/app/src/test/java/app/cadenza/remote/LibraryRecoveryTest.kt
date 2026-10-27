package app.cadenza.remote

import android.app.job.JobScheduler
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import app.cadenza.remote.data.CadenzaDatabase
import app.cadenza.remote.data.RemoteLibrary
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SqlStatements
import app.cadenza.remote.data.StoredSettings
import app.cadenza.remote.data.deviceName
import app.cadenza.remote.updates.RemoteUpdater
import app.cadenza.remote.updates.UpdateJob
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class LibraryRecoveryTest {
    private val app get() = ApplicationProvider.getApplicationContext<CadenzaApplication>()
    private lateinit var db: CadenzaDatabase
    private val song = Song("catalog", "12345", "Saved song", "Artist", "Album", 150_000)

    @Before
    fun open() {
        app.database.close()
        app.deleteDatabase("cadence.sqlite")
        db = CadenzaDatabase(app)
    }

    @After
    fun close() = db.close()

    @Test
    fun favoritesAndPreferencesSurviveReopenAndRemovalIsLocal() {
        RemoteLibrary(db).setFavorite(song, true)
        StoredSettings(db, "app").write("client_name" to "Bedroom tablet", "theme" to "DARK")
        db.close()
        db = CadenzaDatabase(app)
        assertEquals(listOf(song), RemoteLibrary(db).load().songs)
        assertEquals("Bedroom tablet", StoredSettings(db, "app").getString("client_name", null))
        assertEquals("DARK", StoredSettings(db, "app").getString("theme", null))
        RemoteLibrary(db).setFavorite(song, false)
        assertEquals(emptyList<Song>(), RemoteLibrary(db).load().songs)
        assertEquals("Bedroom tablet", StoredSettings(db, "app").getString("client_name", null))
    }

    @Test
    fun malformedFavoriteDoesNotHideHealthySongsOrDestroyOriginalData() {
        RemoteLibrary(db).setFavorite(song, true)
        db.writableDatabase.execSQL("INSERT INTO favorites VALUES('catalog','999','{broken',0)")
        val result = RemoteLibrary(db).load()
        assertEquals(listOf(song), result.songs)
        assertEquals(1, result.unreadable)
        db.readableDatabase.rawQuery("SELECT song_json FROM favorites WHERE song_id='999'", null).use {
            it.moveToFirst()
            assertEquals("{broken", it.getString(0))
        }
        assertThrows(IllegalArgumentException::class.java) { RemoteLibrary(db).setFavorite(song.copy(source = "unknown"), true) }
        assertEquals(listOf(song), RemoteLibrary(db).load().songs)
    }

    @Test
    fun damagedDisposableStateCanRecoverWithoutDeletingPreferencesOrFavorites() {
        RemoteLibrary(db).setFavorite(song, true)
        db.writableDatabase.execSQL(
            "INSERT INTO paired_hosts(host_id,display_name,credential_reference) VALUES('test','Synthetic','unused')",
        )
        db.writableDatabase.execSQL("INSERT INTO host_snapshots VALUES('test','{broken',0)")
        assertNull(db.cachedState("test"))
        assertEquals(listOf(song), RemoteLibrary(db).load().songs)
    }

    @Test
    fun androidDeviceNameDoesNotRequireGoogleOrBluetooth() {
        Settings.Global.putString(app.contentResolver, Settings.Global.DEVICE_NAME, "Test Android Device")
        assertEquals("Test Android Device", deviceName(app))
    }

    @Test
    fun malformedNumericPreferencesFallBackWithoutDeletingTheStoredValue() {
        val settings = StoredSettings(db, "app")
        settings.write("last_maintenance" to "invalid", "installation_session" to "9999999999999999999999")
        assertEquals(0L, settings.getLong("last_maintenance", 0))
        assertEquals(-1, settings.getInt("installation_session", -1))
        assertEquals("invalid", settings.getString("last_maintenance", null))
    }

    @Test
    fun versionTwoUpgradePreservesEncryptedPayloadAndUserPreferences() {
        db.close()
        app.deleteDatabase("cadence.sqlite")
        app.openOrCreateDatabase("cadence.sqlite", 0, null).use { old ->
            for (migration in listOf("001-initial.sql", "002-runtime.sql")) {
                val sql =
                    app.assets
                        .open("storage/$migration")
                        .bufferedReader()
                        .use { it.readText() }
                SqlStatements.parse(sql).forEach(old::execSQL)
            }
            old.execSQL("INSERT INTO settings VALUES('credentials.host.synthetic','opaque-encrypted-payload')")
            old.execSQL("INSERT INTO settings VALUES('app.client_name','My existing tablet')")
            old.version = 2
        }
        db = CadenzaDatabase(app)
        assertEquals(3, db.readableDatabase.version)
        assertEquals("opaque-encrypted-payload", StoredSettings(db, "credentials").getString("host.synthetic", null))
        assertEquals("My existing tablet", StoredSettings(db, "app").getString("client_name", null))
        RemoteLibrary(db).setFavorite(song, true)
        assertEquals(listOf(song), RemoteLibrary(db).load().songs)
    }

    @Test
    fun developmentBuildCannotScheduleDownloadOrInstallUpdates() {
        assertFalse(BuildConfig.AUTOMATIC_UPDATES)
        assertFalse(RemoteUpdater.due(app))
        UpdateJob.schedule(app)
        assertNull(app.getSystemService(JobScheduler::class.java).getPendingJob(43127))
        assertThrows(IllegalStateException::class.java) { RemoteUpdater.checkAndStage(app) }
        assertThrows(IllegalStateException::class.java) { RemoteUpdater.install(app, File(app.filesDir, "never-installed.apk")) }
    }
}
