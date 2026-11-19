package app.cadenza.remote.energy

import app.cadenza.remote.data.StoredSettings

/** Percent choices for the low-battery switch. 0 turns the rule off. */
val LOW_BATTERY_CHOICES = listOf(0, 10, 15, 20, 30)

data class EnergySettings(
    val mode: EnergyMode = EnergyMode.AUTOMATIC,
    val followSystemSaver: Boolean = true,
    val lowBatteryPercent: Int = 20,
    val reduceWhenHot: Boolean = true,
    val fullWhileCharging: Boolean = true,
    val motionArtworkInSaver: Boolean = false,
    val lyricBlurInSaver: Boolean = false,
)

/** Persists [EnergySettings] as additive key/value rows, so older installs simply read the defaults. */
object EnergySettingsStore {
    private const val MODE = "energy_mode"
    private const val FOLLOW_SYSTEM = "energy_follow_system"
    private const val LOW_BATTERY = "energy_low_battery"
    private const val REDUCE_HOT = "energy_reduce_hot"
    private const val FULL_CHARGING = "energy_full_charging"
    private const val MOTION_IN_SAVER = "energy_motion_in_saver"
    private const val BLUR_IN_SAVER = "energy_blur_in_saver"

    fun load(store: StoredSettings): EnergySettings {
        val defaults = EnergySettings()

        fun flag(
            key: String,
            fallback: Boolean,
        ) = store.getString(key)?.toBooleanStrictOrNull() ?: fallback
        return EnergySettings(
            mode = EnergyMode.entries.firstOrNull { it.name == store.getString(MODE) } ?: defaults.mode,
            followSystemSaver = flag(FOLLOW_SYSTEM, defaults.followSystemSaver),
            lowBatteryPercent =
                store.getInt(LOW_BATTERY, defaults.lowBatteryPercent).takeIf { it in LOW_BATTERY_CHOICES }
                    ?: defaults.lowBatteryPercent,
            reduceWhenHot = flag(REDUCE_HOT, defaults.reduceWhenHot),
            fullWhileCharging = flag(FULL_CHARGING, defaults.fullWhileCharging),
            motionArtworkInSaver = flag(MOTION_IN_SAVER, defaults.motionArtworkInSaver),
            lyricBlurInSaver = flag(BLUR_IN_SAVER, defaults.lyricBlurInSaver),
        )
    }

    fun save(
        store: StoredSettings,
        settings: EnergySettings,
    ) = store.write(
        MODE to settings.mode.name,
        FOLLOW_SYSTEM to settings.followSystemSaver.toString(),
        LOW_BATTERY to settings.lowBatteryPercent.toString(),
        REDUCE_HOT to settings.reduceWhenHot.toString(),
        FULL_CHARGING to settings.fullWhileCharging.toString(),
        MOTION_IN_SAVER to settings.motionArtworkInSaver.toString(),
        BLUR_IN_SAVER to settings.lyricBlurInSaver.toString(),
    )
}
