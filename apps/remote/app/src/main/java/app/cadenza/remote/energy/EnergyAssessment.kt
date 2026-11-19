package app.cadenza.remote.energy

/** Battery levels this far above the low-battery threshold already lower the tier to Balanced. */
private const val BALANCED_MARGIN_PERCENT = 10

data class EnergyAssessment(
    val tier: EnergyTier,
    val reason: EnergyReason,
    /** Plain-language reason shown in Settings and Debug. */
    val message: String,
)

/**
 * Picks the tier from the device [inputs] and the user's [settings]. Pure, so every rule is unit-tested.
 *
 * Rules, first match wins in Automatic mode:
 * 1. Hot device (reduce-when-hot on): Saver. Heat outranks charging, because a charging phone is often the hottest.
 * 2. System battery saver on (follow-system on): Saver, even while charging, since the user chose it.
 * 3. Warm device (reduce-when-hot on): Balanced.
 * 4. Screen off: Balanced. Nothing is drawn, so only network and tick cadence matter.
 * 5. Charging (full-while-charging on): Full.
 * 6. Battery at or below the threshold: Saver. Within [BALANCED_MARGIN_PERCENT] above it: Balanced.
 * 7. Otherwise Full.
 * "Always full" and "Always saver" skip every rule.
 */
fun assessEnergy(
    inputs: EnergyInputs,
    settings: EnergySettings,
): EnergyAssessment {
    when (settings.mode) {
        EnergyMode.FULL -> return result(EnergyTier.FULL, EnergyReason.MANUAL_FULL, "Full performance is always on")
        EnergyMode.SAVER -> return result(EnergyTier.SAVER, EnergyReason.MANUAL_SAVER, "Saver is always on")
        EnergyMode.AUTOMATIC -> Unit
    }
    val hot = settings.reduceWhenHot
    val percent = inputs.batteryPercent
    val threshold = settings.lowBatteryPercent
    return when {
        hot && inputs.thermal == ThermalLevel.HOT -> result(EnergyTier.SAVER, EnergyReason.HOT, "The device is hot")
        settings.followSystemSaver && inputs.powerSave ->
            result(EnergyTier.SAVER, EnergyReason.SYSTEM_SAVER, "Battery saver is on")
        hot && inputs.thermal == ThermalLevel.WARM ->
            result(EnergyTier.BALANCED, EnergyReason.WARM, "The device is getting warm")
        !inputs.interactive -> result(EnergyTier.BALANCED, EnergyReason.SCREEN_OFF, "The screen is off")
        settings.fullWhileCharging && inputs.charging -> result(EnergyTier.FULL, EnergyReason.CHARGING, "Charging")
        threshold > 0 && percent != null && percent <= threshold ->
            result(EnergyTier.SAVER, EnergyReason.LOW_BATTERY, "Battery is at $percent%")
        threshold > 0 && percent != null && percent <= threshold + BALANCED_MARGIN_PERCENT ->
            result(EnergyTier.BALANCED, EnergyReason.BATTERY_GETTING_LOW, "Battery is at $percent%")
        else -> result(EnergyTier.FULL, EnergyReason.NORMAL, "Plenty of power")
    }
}

private fun result(
    tier: EnergyTier,
    reason: EnergyReason,
    message: String,
) = EnergyAssessment(tier, reason, message)
