package app.cadenza.remote

import android.app.Application
import android.content.Intent
import app.cadenza.remote.data.CadenzaDatabase
import app.cadenza.remote.data.RemoteLibrary
import app.cadenza.remote.data.SecureVault
import app.cadenza.remote.data.StoredSettings
import app.cadenza.remote.media.SessionNotification
import app.cadenza.remote.updates.UpdateJob

class CadenzaApplication : Application() {
    lateinit var database: CadenzaDatabase
        private set
    lateinit var vault: SecureVault
        private set
    var installationHandler: ((Intent?) -> Unit)? = null
    var mediaAction: ((String) -> Unit)? = null
    val settings by lazy { StoredSettings(database, "app") }
    val library by lazy { RemoteLibrary(database) }
    val updateSettings by lazy { StoredSettings(database, "updates") }

    override fun onCreate() {
        super.onCreate()
        SessionNotification(this).clear()
        database = CadenzaDatabase(this)
        vault = SecureVault(this, database)
        UpdateJob.schedule(this)
    }
}
