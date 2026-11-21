package app.cadenza.remote.energy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.content.ContextCompat

/**
 * Reads the device's energy conditions from system events. It registers its receiver and thermal listener only while
 * [setActive] is true (a foreground control session or a playback pin) and runs no timer, so an idle app costs nothing.
 */
class EnergyMonitor(
    private val context: Context,
    private val onInputs: (EnergyInputs) -> Unit,
) {
    private val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var active = false
    private var thermal = ThermalLevel.NORMAL
    private val batteryManager = context.getSystemService(BatteryManager::class.java)
    private val drawMeter = BatteryDrawMeter()

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context,
                intent: Intent,
            ) = publish(intent)
        }

    private val thermalListener =
        PowerManager.OnThermalStatusChangedListener { status ->
            thermal = thermalLevel(status)
            publish(null)
        }

    fun setActive(wanted: Boolean) {
        if (wanted == active) return
        active = wanted
        if (wanted) start() else stop()
    }

    private fun start() {
        val filter =
            IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
                addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            }
        // The battery broadcast is sticky, so registering returns the current reading without waiting for a change.
        val sticky = ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        thermal = thermalLevel(power.currentThermalStatus)
        drawMeter.start(chargeMicroAh(), SystemClock.elapsedRealtime())
        power.addThermalStatusListener(ContextCompat.getMainExecutor(context), thermalListener)
        publish(sticky)
    }

    private fun stop() {
        runCatching { context.unregisterReceiver(receiver) }
        power.removeThermalStatusListener(thermalListener)
    }

    private fun publish(battery: Intent?) {
        val reading = battery ?: context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        onInputs(
            EnergyInputs(
                powerSave = power.isPowerSaveMode,
                batteryPercent = reading?.let(::percent),
                charging = reading?.let(::isCharging) ?: false,
                thermal = thermal,
                interactive = power.isInteractive,
                draw =
                    drawMeter.read(
                        chargeMicroAh(),
                        currentMicroAmp(),
                        SystemClock.elapsedRealtime(),
                    ),
            ),
        )
    }

    // The system reports Long.MIN_VALUE for a property the device does not have, and a charge counter is never zero.
    private fun chargeMicroAh(): Long? {
        val charge = batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
        return charge.takeIf { it > 0 }
    }

    private fun currentMicroAmp(): Long? {
        val current = batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        return current.takeIf { it != Long.MIN_VALUE }
    }

    private fun percent(intent: Intent): Int? {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        return if (level >= 0 && scale > 0) (level * 100 / scale).coerceIn(0, 100) else null
    }

    private fun isCharging(intent: Intent): Boolean {
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
        return intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0 ||
            status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
    }
}

/** Moderate and below leave the display alone. Severe and above are the heat that throttles the CPU. */
internal fun thermalLevel(status: Int): ThermalLevel =
    when {
        status >= PowerManager.THERMAL_STATUS_SEVERE -> ThermalLevel.HOT
        status >= PowerManager.THERMAL_STATUS_MODERATE -> ThermalLevel.WARM
        else -> ThermalLevel.NORMAL
    }
