package app.cadenza.remote.debugmode

import android.content.Intent
import android.util.Log
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState

// Debug mode lets a device test drive the Remote through activity extras, which adb can send. It runs only in debug
// builds or in builds that explicitly set cadenza.pairingTestHook, so published profiles ignore every extra.
internal const val DEBUG_MODE_TAG = "CadenzaDebug"
internal const val DEBUG_COMMAND_EXTRA = "debug_command"
internal const val DEBUG_INVITATION_EXTRA = "debug_pairing_invitation"
internal const val DEBUG_NAME_EXTRA = "debug_name"
internal const val DEBUG_MODE_EXTRA = "debug_mode"

internal fun debugModeEnabled(): Boolean = BuildConfig.DEBUG || BuildConfig.PAIRING_TEST_HOOK

// Commands: pair (with debug_pairing_invitation), connect, disconnect, transport (with debug_mode), status.
internal fun handleDebugIntent(
    intent: Intent?,
    model: RemoteModel,
) {
    if (!debugModeEnabled() || intent == null) return
    intent.getStringExtra(DEBUG_INVITATION_EXTRA)?.let { invitation ->
        val requestedName = intent.getStringExtra(DEBUG_NAME_EXTRA)
        val name = if (requestedName.isNullOrBlank()) "Debug Remote" else requestedName
        Log.i(DEBUG_MODE_TAG, "pair with invitation of ${invitation.length} characters")
        model.pair(invitation.toByteArray(Charsets.UTF_8), name)
    }
    when (val command = intent.getStringExtra(DEBUG_COMMAND_EXTRA)) {
        null -> Unit
        "connect" -> model.connect()
        "disconnect" -> model.disconnect()
        "transport" -> intent.getStringExtra(DEBUG_MODE_EXTRA)?.let(model::setTransportMode)
        "status" -> Log.i(DEBUG_MODE_TAG, debugStatusLine(model.state.value))
        else -> Log.w(DEBUG_MODE_TAG, "unknown debug command: $command")
    }
}

internal fun debugStatusLine(state: RemoteState): String =
    debugStatusLine(
        connected = state.connected,
        connecting = state.connecting,
        transportMode = state.transportMode,
        profileName = state.profile?.name,
        issue = state.connectionIssue,
        playing = state.snapshot?.playing == true,
        title = currentTitle(state),
        clockUncertaintyMs = state.clockUncertaintyMs,
    )

internal fun debugStatusLine(
    connected: Boolean,
    connecting: Boolean,
    transportMode: String,
    profileName: String?,
    issue: String?,
    playing: Boolean,
    title: String?,
    clockUncertaintyMs: Long?,
): String =
    listOf(
        "connected=$connected",
        "connecting=$connecting",
        "transport=$transportMode",
        "host=${profileName.orEmpty()}",
        "playing=$playing",
        "title=${title.orEmpty()}",
        "issue=${issue.orEmpty()}",
        "clock_uncertainty_ms=${clockUncertaintyMs ?: "none"}",
    ).joinToString(" ")

private fun currentTitle(state: RemoteState): String? {
    val snapshot = state.snapshot ?: return null
    return snapshot.current?.song?.title
}
