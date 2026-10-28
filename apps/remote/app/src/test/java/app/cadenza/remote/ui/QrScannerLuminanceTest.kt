package app.cadenza.remote.ui

import org.junit.Assert.assertArrayEquals
import org.junit.Test
import java.nio.ByteBuffer

class QrScannerLuminanceTest {
    @Test
    fun paddedRowsAreCopiedWithoutTheirPadding() {
        // Two 4-pixel rows, each padded to a 6-byte stride.
        val plane = ByteBuffer.wrap(byteArrayOf(1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0))
        val data = ByteArray(8)

        extractLuminance(rowStride = 6, pixelStride = 1, width = 4, height = 2, buffer = plane, data = data)

        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), data)
    }

    @Test
    fun interleavedPixelsKeepOnlyTheLuminanceSamples() {
        // Each luminance byte is followed by one chroma byte.
        val plane = ByteBuffer.wrap(byteArrayOf(10, 99, 11, 99, 12, 99))
        val data = ByteArray(3)

        extractLuminance(rowStride = 6, pixelStride = 2, width = 3, height = 1, buffer = plane, data = data)

        assertArrayEquals(byteArrayOf(10, 11, 12), data)
    }
}
