package app.cadenza.remote.tv

import android.content.Context
import androidx.core.content.edit
import java.util.UUID

/**
 * The stage's saved settings: the Host address, the receiver's identity and token, the AVR offset, and whether the stage
 * is turned on or off. None of it is shared with the Remote's own preferences.
 */
internal class TvStagePrefs(
    context: Context,
) {
    private val prefs = context.applicationContext.getSharedPreferences("cadenza.tv.stage", Context.MODE_PRIVATE)

    val receiverId: String
        get() =
            prefs.getString(KEY_RECEIVER_ID, null) ?: UUID.randomUUID().toString().also {
                prefs.edit { putString(KEY_RECEIVER_ID, it) }
            }

    var address: String?
        get() = prefs.getString(KEY_ADDRESS, null)
        set(value) = prefs.edit { putString(KEY_ADDRESS, value) }

    var token: String?
        get() = prefs.getString(KEY_TOKEN, null)
        set(value) = prefs.edit { putString(KEY_TOKEN, value) }

    var lipSyncOffsetMs: Int
        get() = prefs.getInt(KEY_LIP_SYNC, 0).coerceIn(0, MAX_LIP_SYNC_MS)
        set(value) = prefs.edit { putInt(KEY_LIP_SYNC, value.coerceIn(0, MAX_LIP_SYNC_MS)) }

    /** Null until the person chooses, so a TV starts the stage by default and a tablet does not. */
    var manualSetting: Boolean?
        get() = if (prefs.contains(KEY_ENABLED)) prefs.getBoolean(KEY_ENABLED, false) else null
        set(value) {
            prefs.edit {
                if (value == null) remove(KEY_ENABLED) else putBoolean(KEY_ENABLED, value)
            }
        }

    companion object {
        const val MAX_LIP_SYNC_MS = 250
        private const val KEY_RECEIVER_ID = "receiverId"
        private const val KEY_ADDRESS = "address"
        private const val KEY_TOKEN = "token"
        private const val KEY_LIP_SYNC = "lipSyncOffsetMs"
        private const val KEY_ENABLED = "enabled"
    }
}
