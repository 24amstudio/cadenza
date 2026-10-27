package app.cadenza.remote

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        model = ViewModelProvider(this)[RemoteModel::class.java]
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
