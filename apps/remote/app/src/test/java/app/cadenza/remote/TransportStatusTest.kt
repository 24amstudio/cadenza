package app.cadenza.remote

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransportStatusTest {
    @Test
    fun parsesLiveAndUnavailablePathsForTheSettingsIndicator() {
        val paths =
            parseTransportPaths(
                JSONArray()
                    .put(
                        JSONObject()
                            .put("transport", "ble")
                            .put("state", "connected")
                            .put("rssi_dbm", -54)
                            .put("loss_percent", 0.5),
                    ).put(
                        JSONObject()
                            .put("transport", "lan")
                            .put("state", "disconnected"),
                    ).put(
                        JSONObject()
                            .put("transport", "not-supported")
                            .put("state", "connected"),
                    ),
            )

        assertEquals(2, paths.size)
        assertEquals("ble", paths.first().transport)
        assertEquals(-54, paths.first().rssiDbm)
        assertEquals("disconnected", paths.last().state)
    }

    @Test
    fun dropsOutOfRangePathSamplesWithoutBreakingTheSessionStatus() {
        val paths =
            parseTransportPaths(
                JSONArray().put(
                    JSONObject()
                        .put("transport", "ble")
                        .put("state", "connected")
                        .put("rssi_dbm", -200),
                ),
            )

        assertEquals(1, paths.size)
        assertNull(paths.single().rssiDbm)
    }
}
