package app.cadenza.remote

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import app.cadenza.remote.data.SongIdentity
import app.cadenza.remote.debugmode.handleDebugIntent
import app.cadenza.remote.media.SessionNotification
import app.cadenza.remote.media.SessionStatus
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.adjustVolumeFromRocker
import app.cadenza.remote.model.dismissPrompt
import app.cadenza.remote.model.installationResult
import app.cadenza.remote.model.installing
import app.cadenza.remote.model.receiveSharedTrack
import app.cadenza.remote.model.showError
import app.cadenza.remote.share.AppleMusicLink
import app.cadenza.remote.ui.CadenzaApp
import app.cadenza.remote.updates.RemoteUpdater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : ComponentActivity() {
    private lateinit var model: RemoteModel
    private var pendingInstallation: File? = null
    private val installAuthorization =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            val file = pendingInstallation
            if (file != null && packageManager.canRequestPackageInstalls()) {
                install(file)
            } else {
                model.installing(false)
            }
        }
    private val notifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            SessionNotification(application).update(SessionStatus.from(model.state.value), model.mediaToken)
        }

    // With the rocker control on, the volume buttons change Music's volume on Host while this screen is open.
    override fun onKeyDown(
        keyCode: Int,
        event: KeyEvent,
    ): Boolean {
        val up = keyCode == KeyEvent.KEYCODE_VOLUME_UP
        val down = keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if ((up || down) && model.adjustVolumeFromRocker(up)) return true
        return super.onKeyDown(keyCode, event)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        model = ViewModelProvider(this)[RemoteModel::class.java]
        handleDebugIntent(intent, model)
        handleSharedIntent(intent, model)
        setContent {
            CadenzaApp(model) { path ->
                val file = File(path)
                if (model.state.value.installationBusy) return@CadenzaApp
                model.installing(true)
                pendingInstallation = file
                if (packageManager.canRequestPackageInstalls()) {
                    install(file)
                } else {
                    installAuthorization.launch(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            ("package:" + packageName).toUri(),
                        ),
                    )
                }
            }
        }
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun install(file: File) {
        lifecycleScope.launch {
            try {
                withContext(Dispatchers.IO) { RemoteUpdater.install(this@MainActivity, file) }
            } catch (error: Exception) {
                model.installing(false)
                model.showError("Update could not be installed", error.message ?: "Retry installation.")
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDebugIntent(intent, model)
        handleSharedIntent(intent, model)
    }

    // A shared Apple Music link opens a dialog that sends the song to the Host. Album and playlist links name no
    // single song, so they are explained instead of guessed at.
    private fun handleSharedIntent(
        intent: Intent,
        model: RemoteModel,
    ) {
        val shared =
            when (intent.action) {
                Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
                Intent.ACTION_VIEW -> intent.dataString
                else -> null
            } ?: return
        val link = AppleMusicLink.parse(shared) ?: return
        val track = link.trackId
        if (track == null) {
            model.showError(
                "Shared link",
                "Album and playlist links are not supported yet. Share a song link instead.",
            )
            return
        }
        model.receiveSharedTrack(SongIdentity("catalog", track))
    }

    override fun onStart() {
        super.onStart()
        (application as CadenzaApplication).installationHandler = { confirmation ->
            if (confirmation != null) {
                try {
                    startActivity(confirmation)
                } catch (error: Exception) {
                    model.showError(
                        "Confirm installation",
                        error.message ?: "Open the update notification to continue.",
                    )
                }
            } else {
                model.installationResult()
            }
        }
        model.installationResult()
        model.setForeground(true)
        requestNotifications()
    }

    override fun onStop() {
        (application as CadenzaApplication).installationHandler = null
        if (isChangingConfigurations) {
            // The ViewModel and connection survive rotation. Clear transient feedback,
            // but do not tear down the control session that the new instance will reuse.
            model.dismissPrompt()
        } else {
            model.setForeground(false)
        }
        super.onStop()
    }
}
