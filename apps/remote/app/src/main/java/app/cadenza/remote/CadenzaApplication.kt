package app.cadenza.remote

import android.app.Application
import android.content.Intent
import app.cadenza.remote.data.CadenzaDatabase
import app.cadenza.remote.data.RemoteLibrary
import app.cadenza.remote.data.SecureVault
import app.cadenza.remote.data.StoredSettings
import app.cadenza.remote.device.DeviceState
import app.cadenza.remote.lockscreen.LockScreenLauncher
import app.cadenza.remote.media.SessionNotification
import app.cadenza.remote.updates.UpdateJob
import app.cadenza.remote.updates.UpdateLoopGuard
import app.cadenza.remote.widget.WidgetObserver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

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
    val device by lazy { DeviceState(this) }
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        SessionNotification(this).clear()
        database = CadenzaDatabase(this)
        vault = SecureVault(this, database)
        UpdateJob.schedule(this)
        // A record for a build that is now running means the install worked, so the retry limit starts over.
        UpdateLoopGuard.save(
            updateSettings,
            UpdateLoopGuard.settled(UpdateLoopGuard.load(updateSettings), BuildConfig.VERSION_CODE.toLong()),
        )
        device.start()
        WidgetObserver(this, device, appScope).start()
        LockScreenLauncher(this, device, appScope).start()
    }
}
