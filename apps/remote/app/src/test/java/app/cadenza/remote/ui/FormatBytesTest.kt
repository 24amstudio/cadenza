package app.cadenza.remote.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class FormatBytesTest {
    @Test
    fun labelsEachValueWithTheUnitMatchingItsMagnitude() {
        assertEquals("512 B", formatBytes(512))
        assertEquals("1.0 KB", formatBytes(1_024))
        assertEquals("75.4 MB", formatBytes(79_062_630))
        assertEquals("12.0 GB", formatBytes(12L * 1_073_741_824))
        assertEquals("226.9 GB", formatBytes(243_638_619_865))
    }
}
