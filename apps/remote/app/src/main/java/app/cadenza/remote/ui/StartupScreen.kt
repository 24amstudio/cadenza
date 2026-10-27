package app.cadenza.remote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.cadenza.remote.BuildConfig

val startupBuildLabel: String
    get() {
        val profile =
            when (BuildConfig.BUILD_PROFILE) {
                "production" -> "prod"
                "development" -> "dev"
                else -> BuildConfig.BUILD_PROFILE
            }
        val identity =
            if (BuildConfig.BUILD_ID.startsWith("source-")) {
                "source-" + BuildConfig.BUILD_ID.removePrefix("source-").take(12)
            } else {
                BuildConfig.BUILD_ID.take(12)
            }
        return "Cadenza ${BuildConfig.VERSION_NAME.substringBefore('-')}-$profile-$identity-${BuildConfig.BUILD_TIMESTAMP}"
    }

/** The OS launch splash precedes this native screen; no artificial startup delay is added. */
@Composable
fun StartupScreen() {
    Surface(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp)) {
            Column(
                Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Icon(cadenzaVector(CadenzaIcon.MUSIC), contentDescription = null, modifier = Modifier.size(80.dp))
                Text("Cadenza", style = MaterialTheme.typography.headlineLarge)
                CircularProgressIndicator(Modifier.size(24.dp))
            }
            Text(
                startupBuildLabel,
                Modifier.align(Alignment.BottomCenter).fillMaxWidth(),
                style = MaterialTheme.typography.labelMedium,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
