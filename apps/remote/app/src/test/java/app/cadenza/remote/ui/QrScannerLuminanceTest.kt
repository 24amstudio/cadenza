package app.cadenza.remote.ui

import com.google.zxing.BarcodeFormat
import com.google.zxing.DecodeHintType
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.Result
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
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

    @Test
    fun compactPairingKeepsRawQrBytesInsteadOfLossyText() {
        val raw = byteArrayOf(0x43, 0x44, 0x5A, 0x50, 0x01, 0xFF.toByte(), 0x00)
        val result = Result("CDZP\u0001�", raw, null, BarcodeFormat.QR_CODE)

        assertArrayEquals(raw, resultPayload(result))
    }

    @Test
    fun denseRotatedInvitationIsDecodedUsingCameraRotation() {
        val invitation = "{\"version\":1,\"certificate_der_base64\":\"${"A".repeat(1_000)}\"}"
        val size = 360
        val matrix =
            QRCodeWriter().encode(
                invitation,
                BarcodeFormat.QR_CODE,
                size,
                size,
                mapOf(
                    EncodeHintType.ERROR_CORRECTION to com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.M,
                    EncodeHintType.MARGIN to 4,
                ),
            )
        val rotated = rotateClockwise(matrix)
        val luminance = ByteArray(size * size) { index -> if (rotated.get(index % size, index / size)) 0.toByte() else 255.toByte() }
        val decoder =
            MultiFormatReader().apply {
                setHints(
                    mapOf(
                        DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                        DecodeHintType.TRY_HARDER to true,
                        DecodeHintType.ALSO_INVERTED to true,
                    ),
                )
            }

        assertEquals(invitation, String(requireNotNull(decodeQrPayload(luminance, size, size, 90, decoder))))
    }

    private fun rotateClockwise(source: BitMatrix): BitMatrix {
        val result = BitMatrix(source.width, source.height)
        for (y in 0 until source.height) {
            for (x in 0 until source.width) {
                if (source.get(x, y)) result.set(source.height - 1 - y, x)
            }
        }
        return result
    }
}
