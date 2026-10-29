package app.cadenza.remote

import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.data.TransportPolicy
import app.cadenza.remote.network.PathPreference
import app.cadenza.remote.network.TransportPathSelector
import org.junit.Assert.assertEquals
import org.junit.Test

class TransportPathSelectorTest {
    private val selector = TransportPathSelector()

    @Test
    fun deterministicPolicyHonorsPreferredLanFamily() {
        val selected =
            selector.choose(
                TransportPolicy("hybrid", "deterministic", "lan", "lan"),
                listOf(
                    path("ble", rtt = 2),
                    path("wifi", rtt = 20),
                ),
            )

        assertEquals("wifi", selected?.transport)
    }

    @Test
    fun opportunisticPolicyUsesMeasuredHealth() {
        val selected =
            selector.choose(
                TransportPolicy("hybrid", "opportunistic", null, "auto"),
                listOf(
                    path("ble", rtt = 8, throughput = 64),
                    path("ethernet", rtt = 3, throughput = 10_000),
                ),
            )

        assertEquals("ethernet", selected?.transport)
    }

    @Test
    fun measuredBatteryPreferenceChoosesLowerEnergyPath() {
        val selected =
            selector.chooseMeasured(
                TransportPolicy("hybrid", "opportunistic", null, "auto"),
                listOf(
                    path("wifi", 4, energy = 1.2),
                    path("ble", 55, energy = 0.2),
                ),
                PathPreference.battery,
            )

        assertEquals("ble", selected?.transport)
    }

    private fun path(
        transport: String,
        rtt: Long,
        throughput: Long = 1_000,
        energy: Double? = null,
    ): TransportPathStatus = TransportPathStatus(transport, "connected", null, rtt, 0.0, throughput, 0, energy)
}
