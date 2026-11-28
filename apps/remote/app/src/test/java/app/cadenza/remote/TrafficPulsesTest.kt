package app.cadenza.remote

import app.cadenza.remote.model.TrafficPulses
import org.junit.Assert.assertEquals
import org.junit.Test

class TrafficPulsesTest {
    @Test
    fun aBurstOfReceivedFramesPulsesOncePerInterval() {
        var now = 0L
        val pulses = TrafficPulses { now }

        pulses.received()
        pulses.received()
        assertEquals(1L, pulses.incoming.value)

        now = TrafficPulses.INTERVAL_MS
        pulses.received()
        assertEquals(2L, pulses.incoming.value)
    }

    @Test
    fun sentAndReceivedFramesPulseTheirOwnArrows() {
        var now = 0L
        val pulses = TrafficPulses { now }

        pulses.sent()
        pulses.received()

        assertEquals(1L, pulses.outgoing.value)
        assertEquals(1L, pulses.incoming.value)
    }
}
