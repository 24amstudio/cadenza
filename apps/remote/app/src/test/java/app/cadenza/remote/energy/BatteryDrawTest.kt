package app.cadenza.remote.energy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BatteryDrawTest {
    @Test
    fun theSessionDrawIsTheChargeLostSinceItBeganAndItsAverageRate() {
        val meter = BatteryDrawMeter()
        meter.start(chargeMicroAh = 4_000_000, nowMs = 0)

        val draw = meter.read(chargeMicroAh = 3_970_000, currentMicroAmp = -200_000, nowMs = 540_000)

        assertEquals(30.0, draw?.consumedMilliAh ?: -1.0, 1e-9)
        assertEquals(-200.0, draw?.currentMilliAmp ?: 0.0, 1e-9)
        assertEquals(200.0, draw?.averageMilliAmp ?: 0.0, 1e-9)
    }

    @Test
    fun charging_does_not_count_as_draw_and_the_average_waits_for_a_minute() {
        val meter = BatteryDrawMeter()
        meter.start(chargeMicroAh = 3_000_000, nowMs = 0)

        val charging = meter.read(chargeMicroAh = 3_100_000, currentMicroAmp = null, nowMs = 120_000)
        assertEquals(0.0, charging?.consumedMilliAh ?: -1.0, 1e-9)

        val early = meter.read(chargeMicroAh = 2_999_000, currentMicroAmp = null, nowMs = 30_000)
        assertNull(early?.averageMilliAmp)
    }

    @Test
    fun aDeviceWithoutACounterReportsNoDraw() {
        val meter = BatteryDrawMeter()
        meter.start(chargeMicroAh = null, nowMs = 0)

        val draw = meter.read(chargeMicroAh = null, currentMicroAmp = null, nowMs = 120_000)

        assertNull(draw?.consumedMilliAh)
        assertNull(draw?.averageMilliAmp)
        assertNull(BatteryDrawMeter().read(chargeMicroAh = 1, currentMicroAmp = null, nowMs = 1))
    }
}
