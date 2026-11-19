package app.cadenza.remote.energy

/** How much work the Remote does for visual polish. Lower tiers trade effects for battery and heat. */
enum class EnergyTier(
    val label: String,
) {
    FULL("Full"),
    BALANCED("Balanced"),
    SAVER("Saver"),
}

/** Whether the tier follows the device or the user pinned it. */
enum class EnergyMode(
    val label: String,
) {
    AUTOMATIC("Automatic"),
    FULL("Always full"),
    SAVER("Always saver"),
}

/** Android thermal status folded to the three levels that change behavior. */
enum class ThermalLevel {
    NORMAL,
    WARM,
    HOT,
}

/** The rule that decided the tier, so Settings and Debug can say why in plain language. */
enum class EnergyReason {
    MANUAL_FULL,
    MANUAL_SAVER,
    HOT,
    SYSTEM_SAVER,
    WARM,
    SCREEN_OFF,
    CHARGING,
    LOW_BATTERY,
    BATTERY_GETTING_LOW,
    NORMAL,
}
