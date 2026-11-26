package app.cadenza.remote.tv

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.lifecycle.ViewModelProvider

/**
 * The Android TV receiver: a full-screen Cadenza stage on a TV, or on any tablet the person turned it on for. It shares
 * no screen with the Remote, so the Remote's navigation state never reaches it.
 */
class TvStageActivity : ComponentActivity() {
    private lateinit var model: TvStageModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        model = ViewModelProvider(this)[TvStageModel::class.java]
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                TvStageScreen(model = model, onExit = { finish() })
            }
        }
    }

    override fun onStart() {
        super.onStart()
        model.resume()
    }
}
