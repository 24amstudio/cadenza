package app.cadenza.remote.energy

/**
 * What the device reports right now. [powerSave] is the standard PowerManager flag, so a vendor mode (for example
 * Huawei "Ultra power saving") is seen only when the vendor also raises that flag. No private vendor API is read.
 */
data class EnergyInputs(
    val powerSave: Boolean = false,
    val batteryPercent: Int? = null,
    val charging: Boolean = false,
    val thermal: ThermalLevel = ThermalLevel.NORMAL,
    val interactive: Boolean = true,
    /** What the system battery says about the draw since this session began. Null until the first reading. */
    val draw: BatteryDraw? = null,
)
