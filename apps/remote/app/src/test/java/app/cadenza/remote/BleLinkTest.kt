package app.cadenza.remote

import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.data.TransportPolicy
import app.cadenza.remote.network.BleFrameCodec
import app.cadenza.remote.network.BleLinkPolicy
import app.cadenza.remote.network.BulkTransferTracker
import app.cadenza.remote.network.HostLivenessPolicy
import app.cadenza.remote.network.PathPreference
import app.cadenza.remote.network.TransportPathSelector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BleLinkTest {
    @Test
    fun codecReassemblesFramesSplitAtEveryByteAndAtMtuSize() {
        val first = "first".toByteArray()
        val second = ByteArray(700) { it.toByte() }
        val codec = BleFrameCodec()
        val bytes = (codec.encode(first, 23) + codec.encode(second, 247)).flatMap { it.asList() }.toByteArray()
        val frames = bytes.map { codec.append(byteArrayOf(it)) }.flatten()
        assertEquals(2, frames.size)
        assertTrue(first.contentEquals(frames[0]))
        assertTrue(second.contentEquals(frames[1]))
    }

    @Test
    fun codecFramesMatchTheHostAndWebGoldenBytes() {
        // The same bytes are asserted by the Host (Swift) and Web (TypeScript) codec tests: 4-byte big-endian length,
        // then the payload, split every mtu - 3 bytes.
        val chunks = BleFrameCodec().encode("hello".toByteArray(), 23)
        assertEquals(1, chunks.size)
        assertTrue(byteArrayOf(0, 0, 0, 5, 104, 101, 108, 108, 111).contentEquals(chunks.single()))
        assertEquals(listOf(20, 20, 4), BleFrameCodec().encode(ByteArray(40), 23).map { it.size })
    }

    @Test
    fun codecDropsAFrameThatStopsGrowingAndReadsTheNextCleanly() {
        var now = 0L
        val codec = BleFrameCodec { now }
        val lost = codec.encode(ByteArray(100), 23)
        // The Host sent six fragments and two never arrived: the codec waits for bytes that cannot come.
        lost.take(3).forEach { assertTrue(codec.append(it).isEmpty()) }
        now += BleFrameCodec.STALLED_FRAME_MS + 1
        val next = codec.encode("state".toByteArray(), 247).single()
        assertThrows(IllegalStateException::class.java) { codec.append(next) }
        assertEquals("state", String(codec.append(next).single()))
    }

    @Test
    fun codecRefusesAnImplausibleLength() {
        val codec = BleFrameCodec()
        assertThrows(IllegalStateException::class.java) { codec.append(byteArrayOf(-1, -1, -1, -1, 1)) }
        assertEquals("ok", String(codec.append(codec.encode("ok".toByteArray(), 247).single()).single()))
    }

    @Test
    fun retryDelayGrowsIsCappedAndJitterStaysWithinAQuarter() {
        assertEquals(300L, BleLinkPolicy.retryDelayMs(1, 0.0))
        assertEquals(600L, BleLinkPolicy.retryDelayMs(2, 0.0))
        assertEquals(4_000L, BleLinkPolicy.retryDelayMs(9, 0.0))
        assertTrue(BleLinkPolicy.retryDelayMs(2, 1.0) <= 750L)
        assertTrue(BleLinkPolicy.backgroundRetryDelayMs(3, 0.0) == 45_000L)
    }

    @Test
    fun retriesStopOnSecurityStatusesTheAttemptLimitAndTheTotalBudget() {
        assertTrue(BleLinkPolicy.retryable(133, 1, 2_000, 300))
        assertFalse(BleLinkPolicy.retryable(5, 1, 0, 300))
        assertFalse(BleLinkPolicy.retryable(133, BleLinkPolicy.MAXIMUM_ATTEMPTS, 0, 300))
        assertFalse(BleLinkPolicy.retryable(133, 1, BleLinkPolicy.TOTAL_SETUP_MS - 1_000, 300))
    }

    @Test
    fun scansStayUnderAndroidsFrequencyLimit() {
        assertEquals(0L, BleLinkPolicy.scanStartDelayMs(listOf(0L, 5_000L, 10_000L), 12_000L))
        // Four starts in the last 30 s: the next waits until the oldest ages out.
        assertEquals(18_000L, BleLinkPolicy.scanStartDelayMs(listOf(0L, 5_000L, 10_000L, 11_000L), 12_000L))
        assertEquals(0L, BleLinkPolicy.scanStartDelayMs(listOf(0L, 5_000L, 10_000L, 11_000L), 31_000L))
    }

    @Test
    fun fastIntervalIsRequestedOnlyDuringBulkInflowAndReleasedWhenQuiet() {
        val tracker = BulkTransferTracker()
        assertFalse(tracker.onBytes(0, 244))
        assertFalse(tracker.shouldRelax(10_000))
        var asked = 0
        for (i in 0 until 30) if (tracker.onBytes(5L * i, 244)) asked++
        assertEquals("Asked once, not per notification.", 1, asked)
        assertFalse(tracker.shouldRelax(3_000))
        assertTrue(tracker.shouldRelax(6_500))
        val trickle = BulkTransferTracker()
        for (i in 0 until 30) assertFalse("State and heartbeats stay on the balanced interval.", trickle.onBytes(100L * i, 244))
        assertFalse(tracker.fast)
    }

    @Test
    fun selectorKeepsTheCurrentPathUntilItsMinimumDwellPasses() {
        val selector = TransportPathSelector()
        val policy = TransportPolicy("hybrid", "opportunistic", null, "auto")
        val wifiBetter = listOf(path("wifi", 4, 0.1), path("ble", 55, 1.2))
        val bleBetter = listOf(path("wifi", 400, 2.0), path("ble", 20, 0.1))
        assertEquals("wifi", selector.chooseMeasured(policy, wifiBetter, PathPreference.battery, 0)?.transport)
        assertEquals("wifi", selector.chooseMeasured(policy, bleBetter, PathPreference.battery, 10_000)?.transport)
        assertEquals("ble", selector.chooseMeasured(policy, bleBetter, PathPreference.battery, 31_000)?.transport)
        // A path that is gone is replaced immediately, dwell or not.
        assertEquals("wifi", selector.chooseMeasured(policy, listOf(path("wifi", 4, 0.1)), PathPreference.battery, 32_000)?.transport)
    }

    @Test
    fun aRoutineBluetoothDropRetriesQuietlyUntilTheRetriesRunOut() {
        assertFalse(BleLinkPolicy.needsPrompt("Bluetooth link lost (GATT status 8).", 1))
        assertFalse(BleLinkPolicy.needsPrompt("Cadenza Host did not answer over Bluetooth.", BleLinkPolicy.QUIET_FAILURES - 1))
        assertTrue(BleLinkPolicy.needsPrompt("Cadenza Host did not answer over Bluetooth.", BleLinkPolicy.QUIET_FAILURES))
    }

    @Test
    fun aBlockedPermissionOrSwitchedOffAdapterPromptsOnTheFirstFailure() {
        assertTrue(BleLinkPolicy.needsPrompt(BleLinkPolicy.PERMISSION_MESSAGE, 1))
        assertTrue(BleLinkPolicy.needsPrompt(BleLinkPolicy.UNAVAILABLE_MESSAGE, 1))
    }

    @Test
    fun bluetoothToleratesTwiceTheHostsLongestQuietSpanWhileLanKeepsShortLimits() {
        // The Host sends a heartbeat at least every 15 s over Bluetooth, even while paused.
        assertTrue(HostLivenessPolicy.silenceLimitMs("ble") >= 2 * 15_000L)
        assertTrue(HostLivenessPolicy.silenceLimitMs("hybrid") >= 2 * 15_000L)
        assertEquals(10_000L, HostLivenessPolicy.silenceLimitMs("lan"))
        assertEquals(3_000L, HostLivenessPolicy.staleAfterMs("lan"))
        assertTrue(HostLivenessPolicy.staleAfterMs("ble") > 15_000L)
    }

    private fun path(
        transport: String,
        rtt: Long,
        energy: Double,
    ) = TransportPathStatus(transport, "connected", null, rtt, 0.0, 1_000, 0, energy)
}
