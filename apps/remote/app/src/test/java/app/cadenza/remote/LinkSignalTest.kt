package app.cadenza.remote

import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.model.TrafficPulses
import app.cadenza.remote.ui.linkSignalBars
import org.junit.Assert.assertEquals
import org.junit.Test

class LinkSignalTest {
    private fun path(
        state: String,
        rttMs: Long?,
    ) = TransportPathStatus(
        transport = "ble",
        state = state,
        rssiDbm = null,
        rttMs = rttMs,
        lossPercent = null,
        throughputKbps = null,
        backlogBytes = null,
    )

    @Test
    fun aDroppedLinkShowsNoBarsAndALiveLinkWithoutARoundTripShowsOne() {
        assertEquals(0, linkSignalBars(connected = false, paths = listOf(path("connected", 40))))
        assertEquals(1, linkSignalBars(connected = true, paths = emptyList()))
    }

    @Test
    fun barsFollowTheFastestLivePathsRoundTrip() {
        val paths = listOf(path("connected", 150), path("disconnected", 10), path("degraded", 300))

        assertEquals(3, linkSignalBars(connected = true, paths = paths))
        assertEquals(4, linkSignalBars(connected = true, paths = listOf(path("connected", 40))))
        assertEquals(1, linkSignalBars(connected = true, paths = listOf(path("connected", 900))))
    }

    @Test
    fun aBurstOfFramesPulsesOnceAndAPulseAfterTheIntervalCountsAgain() {
        var now = 0L
        val pulses = TrafficPulses(clock = { now })

        repeat(20) { pulses.received() }
        assertEquals(1L, pulses.incoming.value)
        assertEquals(0L, pulses.outgoing.value)

        now += TrafficPulses.INTERVAL_MS
        pulses.received()
        pulses.sent()
        assertEquals(2L, pulses.incoming.value)
        assertEquals(1L, pulses.outgoing.value)
    }
}
