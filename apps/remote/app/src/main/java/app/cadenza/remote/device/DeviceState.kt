package app.cadenza.remote.device

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Screen and charging state, observed with broadcast receivers that are registered for the life of the process. Screen
 * events cannot be declared in the manifest, so registering here is the only option.
 */
class DeviceState(
    private val context: Context,
) {
    private val screen = MutableStateFlow(true)
    private val power = MutableStateFlow(false)
    private val presented = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private var started = false

    val screenInteractive: StateFlow<Boolean> = screen.asStateFlow()
    val charging: StateFlow<Boolean> = power.asStateFlow()

    /** Emits when the user unlocks the device. */
    val userPresent: SharedFlow<Unit> = presented.asSharedFlow()

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context,
                intent: Intent,
            ) {
                when (intent.action) {
                    Intent.ACTION_SCREEN_ON -> screen.value = true
                    Intent.ACTION_SCREEN_OFF -> screen.value = false
                    Intent.ACTION_USER_PRESENT -> presented.tryEmit(Unit)
                    Intent.ACTION_POWER_CONNECTED -> power.value = true
                    Intent.ACTION_POWER_DISCONNECTED -> power.value = false
                    Intent.ACTION_BATTERY_CHANGED -> power.value = intent.isPlugged()
                }
            }
        }

    fun start() {
        if (started) return
        started = true
        val powerManager = context.getSystemService(PowerManager::class.java)
        screen.value = powerManager.isInteractive
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        power.value = battery?.isPlugged() == true
        val filter =
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
                addAction(Intent.ACTION_POWER_CONNECTED)
                addAction(Intent.ACTION_POWER_DISCONNECTED)
                addAction(Intent.ACTION_BATTERY_CHANGED)
            }
        // The platform flag exists from API 33. Earlier releases take no flag, and no permission is needed for either.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun Intent.isPlugged(): Boolean = getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
}
