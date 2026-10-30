package app.cadenza.remote

import app.cadenza.remote.data.TransportMethodRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransportMethodsTest {
    @Test
    fun selectionMapsToSingleOrHybridSessionModes() {
        assertEquals(setOf("lan"), TransportMethodRegistry.selectedFor("lan"))
        assertEquals("ble", TransportMethodRegistry.modeFor(setOf("ble")))
        assertEquals("hybrid", TransportMethodRegistry.modeFor(setOf("lan", "ble")))
    }

    @Test
    fun unsupportedFutureSelectionIsRejectedUntilTransportIsImplemented() {
        assertNull(TransportMethodRegistry.modeFor(setOf("lan", "usb")))
    }
}
