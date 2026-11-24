package app.cadenza.remote

import app.cadenza.remote.network.WakeOnLan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WakeOnLanTest {
    @Test
    fun aMagicPacketIsSixSyncBytesThenTheHostAddressSixteenTimes() {
        val packet = WakeOnLan.magicPacket("0a:1b:2c:3d:4e:5f")!!
        val address = listOf(0x0A, 0x1B, 0x2C, 0x3D, 0x4E, 0x5F).map { it.toByte() }

        assertEquals(102, packet.size)
        assertTrue(packet.take(6).all { it == 0xFF.toByte() })
        assertEquals(address, packet.copyOfRange(6, 12).toList())
        assertEquals(address, packet.copyOfRange(96, 102).toList())
    }

    @Test
    fun aMalformedAddressProducesNoPacketAndIsRefusedForStorage() {
        assertNull(WakeOnLan.magicPacket("0a-1b-2c-3d-4e-5f"))
        assertFalse(WakeOnLan.isValidAddress("0A:1B:2C:3D:4E:5F"))
        assertFalse(WakeOnLan.isValidAddress("0a:1b:2c:3d:4e"))
    }
}
