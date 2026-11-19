package app.cadenza.remote.network

/** Timing and retry rules for the Bluetooth link, kept free of Android types so they can be tested directly. */
internal object BleLinkPolicy {
    /** The Host is usually found within a second or two. A longer scan only drains the battery. */
    const val SCAN_WINDOW_MS = 5_000L

    /** Connect, discover, negotiate the size and enable notifications, for one attempt. */
    const val SETUP_DEADLINE_MS = 4_500L

    /** A Host that never answers the size request still works at the default size. */
    const val MTU_DEADLINE_MS = 2_000L

    const val WRITE_DEADLINE_MS = 5_000L

    /** Below the model's own 12 s handshake limit, so the transport reports the real reason first. */
    const val TOTAL_SETUP_MS = 10_500L
    const val MAXIMUM_ATTEMPTS = 3
    const val MAXIMUM_QUEUED_BYTES = 262_144

    /** Android silently drops scans after five starts in 30 s, so a retry loop stays under four. */
    const val SCAN_HISTORY_MS = 30_000L
    private const val SCANS_PER_HISTORY = 4

    const val PERMISSION_MESSAGE = "Allow Nearby devices to connect over Bluetooth."
    const val UNAVAILABLE_MESSAGE = "Bluetooth is off or unavailable. Turn Bluetooth on to connect to the Host."

    /** Failed attempts in a row that the Remote retries without a prompt. Each attempt follows the reconnect backoff. */
    const val QUIET_FAILURES = 5

    /** A permission or a switched-off adapter will not fix itself. Other drops are routine and recover on their own. */
    fun needsPrompt(
        message: String,
        consecutiveFailures: Int,
    ): Boolean = message == PERMISSION_MESSAGE || message == UNAVAILABLE_MESSAGE || consecutiveFailures >= QUIET_FAILURES

    private const val RETRY_BASE_MS = 300L
    private const val RETRY_CAP_MS = 4_000L
    private const val RETRY_JITTER = 0.25

    private const val GATT_INSUFFICIENT_AUTHENTICATION = 5
    private const val GATT_INSUFFICIENT_ENCRYPTION = 15

    /** Delay before the next connection attempt: 0.3 s, 0.6 s, 1.2 s ... with up to a quarter more. */
    fun retryDelayMs(
        attempt: Int,
        random: Double,
    ): Long {
        val base = (RETRY_BASE_MS shl (attempt - 1).coerceIn(0, 6)).coerceAtMost(RETRY_CAP_MS)
        return base + (base * RETRY_JITTER * random.coerceIn(0.0, 1.0)).toLong()
    }

    /** Whether another attempt can help. Cadenza needs no bonding, so a security status will not improve. */
    fun retryable(
        status: Int,
        attempt: Int,
        elapsedMs: Long,
        nextDelayMs: Long,
    ): Boolean =
        status != GATT_INSUFFICIENT_AUTHENTICATION &&
            status != GATT_INSUFFICIENT_ENCRYPTION &&
            attempt < MAXIMUM_ATTEMPTS &&
            elapsedMs + nextDelayMs + SETUP_DEADLINE_MS / 2 < TOTAL_SETUP_MS

    /** Hybrid sessions retry a lost Bluetooth link this many times while LAN carries the session. */
    const val BACKGROUND_RETRIES = 3

    /** 5 s, 15 s, 45 s, each with up to a quarter more. */
    fun backgroundRetryDelayMs(
        attempt: Int,
        random: Double,
    ): Long {
        val base = 5_000L * listOf(1L, 3L, 9L)[(attempt - 1).coerceIn(0, 2)]
        return base + (base * RETRY_JITTER * random.coerceIn(0.0, 1.0)).toLong()
    }

    /** How long to wait before a scan may start without hitting Android's scan-frequency limit. */
    fun scanStartDelayMs(
        startedAt: List<Long>,
        now: Long,
    ): Long {
        val recent = startedAt.filter { now - it < SCAN_HISTORY_MS }.sorted()
        if (recent.size < SCANS_PER_HISTORY) return 0
        return recent[recent.size - SCANS_PER_HISTORY] + SCAN_HISTORY_MS - now
    }
}

/**
 * Asks for the fast connection interval only while a large transfer is arriving. The default balanced interval costs
 * less power and is plenty for commands and state, so the fast one is held briefly and then released.
 */
internal class BulkTransferTracker(
    private val thresholdBytes: Int = 6_144,
    private val windowMs: Long = 1_000,
    private val holdMs: Long = 3_000,
) {
    private var windowStart = 0L
    private var windowBytes = 0
    private var lastBulkAt = 0L

    var fast = false
        private set

    /** True when the caller should ask for the fast interval now. */
    fun onBytes(
        now: Long,
        size: Int,
    ): Boolean {
        if (now - windowStart > windowMs) {
            windowStart = now
            windowBytes = 0
        }
        windowBytes += size
        if (windowBytes < thresholdBytes) return false
        lastBulkAt = now
        if (fast) return false
        fast = true
        return true
    }

    /** True when the transfer has been quiet long enough to return to the balanced interval. */
    fun shouldRelax(now: Long): Boolean {
        if (!fast || now - lastBulkAt < holdMs) return false
        fast = false
        windowBytes = 0
        return true
    }

    fun reset() {
        fast = false
        windowBytes = 0
    }
}
