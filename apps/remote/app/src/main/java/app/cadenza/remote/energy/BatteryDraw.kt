package app.cadenza.remote.energy

/**
 * What the system battery reports for the current session. The charge counter falls as the device draws, so the
 * session's consumption is its drop since the session began. This is the whole device's draw, not Cadenza's alone.
 */
data class BatteryDraw(
    /** Charge drawn since the session began, or null when the system reports no charge counter. */
    val consumedMilliAh: Double?,
    val elapsedMs: Long,
    /** The system's current reading, in mA. Most devices report it negative while discharging. */
    val currentMilliAmp: Double?,
) {
    /** Average draw since the session began, in mA, once a minute of session has passed. */
    val averageMilliAmp: Double?
        get() =
            consumedMilliAh
                ?.takeIf { elapsedMs >= MINIMUM_AVERAGE_MS }
                ?.let { it * MILLISECONDS_PER_HOUR / elapsedMs }

    private companion object {
        const val MINIMUM_AVERAGE_MS = 60_000L
        const val MILLISECONDS_PER_HOUR = 3_600_000.0
    }
}

/** Starts a session's meter from the first charge reading, and reads the draw since then. */
internal class BatteryDrawMeter {
    private var startedAt: Long? = null
    private var startCharge: Long? = null

    fun start(
        chargeMicroAh: Long?,
        nowMs: Long,
    ) {
        startedAt = nowMs
        startCharge = chargeMicroAh
    }

    fun read(
        chargeMicroAh: Long?,
        currentMicroAmp: Long?,
        nowMs: Long,
    ): BatteryDraw? {
        val started = startedAt ?: return null
        val before = startCharge ?: chargeMicroAh.also { startCharge = it }
        val consumed = if (before == null || chargeMicroAh == null) null else (before - chargeMicroAh).coerceAtLeast(0) / 1_000.0
        return BatteryDraw(
            consumedMilliAh = consumed,
            elapsedMs = (nowMs - started).coerceAtLeast(0),
            currentMilliAmp = currentMicroAmp?.let { it / 1_000.0 },
        )
    }
}
