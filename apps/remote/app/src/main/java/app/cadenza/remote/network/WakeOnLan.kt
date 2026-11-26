package app.cadenza.remote.network

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/** Sends the Wake-on-LAN magic packet that asks a sleeping Host's network interface to wake the Mac. */
internal object WakeOnLan {
    private const val PORT = 9
    private const val SYNC_BYTES = 6
    private const val REPEATS = 16
    private val address = Regex("^([0-9a-f]{2}:){5}[0-9a-f]{2}$")

    fun isValidAddress(value: String): Boolean = address.matches(value)

    /** Six 0xFF bytes followed by the hardware address repeated sixteen times, or null for a malformed address. */
    fun magicPacket(mac: String): ByteArray? {
        if (!isValidAddress(mac)) return null
        val hardware = mac.split(":").map { it.toInt(16).toByte() }
        val packet = ByteArray(SYNC_BYTES + REPEATS * hardware.size)
        packet.fill(0xFF.toByte(), 0, SYNC_BYTES)
        for (repeat in 0 until REPEATS) {
            hardware.forEachIndexed { index, value -> packet[SYNC_BYTES + repeat * hardware.size + index] = value }
        }
        return packet
    }

    /** Broadcasts the packet on the local network. This blocks, so call it off the main thread. */
    fun send(mac: String): Boolean {
        val packet = magicPacket(mac) ?: return false
        return runCatching {
            DatagramSocket().use { socket ->
                socket.broadcast = true
                socket.send(DatagramPacket(packet, packet.size, InetAddress.getByName("255.255.255.255"), PORT))
            }
        }.isSuccess
    }
}
