package app.cadenza.remote

import app.cadenza.remote.data.ClockSync
import app.cadenza.remote.model.TrafficPulses
import app.cadenza.remote.ui.LinkTransport
import app.cadenza.remote.ui.linkSignalBars
import app.cadenza.remote.ui.linkTransportOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LinkSignalTest {
    @Test
    fun aDroppedLinkShowsNoBarsAndALiveLinkWithoutARoundTripShowsOne() {
        assertEquals(0, linkSignalBars(connected = false, roundTripMs = 40))
        assertEquals(1, linkSignalBars(connected = true, roundTripMs = null))
    }

    @Test
    fun aQuickLinkShowsAllBarsAndASlowOneShowsFewer() {
        assertEquals(4, linkSignalBars(connected = true, roundTripMs = 40))
        assertEquals(3, linkSignalBars(connected = true, roundTripMs = 150))
        assertEquals(2, linkSignalBars(connected = true, roundTripMs = 300))
        assertEquals(1, linkSignalBars(connected = true, roundTripMs = 900))
    }

    @Test
    fun aFixedModeNamesItsTransportAndHybridFollowsTheHostDecision() {
        assertEquals(LinkTransport.BLUETOOTH, linkTransportOf("ble", selected = "lan"))
        assertEquals(LinkTransport.WIFI, linkTransportOf("lan", selected = null))
        assertEquals(LinkTransport.BLUETOOTH, linkTransportOf("hybrid", selected = "ble"))
        assertEquals(LinkTransport.WIFI, linkTransportOf("hybrid", selected = "ethernet"))
        assertNull(linkTransportOf("hybrid", selected = null))
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
