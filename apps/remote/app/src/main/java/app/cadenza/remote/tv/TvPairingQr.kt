package app.cadenza.remote.tv

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/**
 * Renders [content] as a black-on-white QR code of [sidePx] pixels. The quiet zone is part of the bitmap, so a phone
 * camera can read the code from the couch.
 */
internal fun pairingQrBitmap(
    content: String,
    sidePx: Int,
): Bitmap {
    val matrix =
        QRCodeWriter().encode(
            content,
            BarcodeFormat.QR_CODE,
            sidePx,
            sidePx,
            mapOf(EncodeHintType.MARGIN to QUIET_ZONE_MODULES),
        )
    val pixels =
        IntArray(sidePx * sidePx) { index ->
            if (matrix.get(index % sidePx, index / sidePx)) Color.BLACK else Color.WHITE
        }
    return Bitmap.createBitmap(pixels, sidePx, sidePx, Bitmap.Config.ARGB_8888)
}

private const val QUIET_ZONE_MODULES = 2
