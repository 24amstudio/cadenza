package app.cadenza.remote.ui

import com.google.zxing.BarcodeFormat
import com.google.zxing.Result
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QrPayloadCandidatesTest {
    private val nativeInvitation = "CDZP:AQIDBA"

    @Test
    fun webAddressCarriesTheNativeInvitationInItsFragment() {
        val candidates = resultPayloadCandidates(qrResult("http://192.168.1.20:43129/#$nativeInvitation"))

        assertArrayEquals(nativeInvitation.toByteArray(Charsets.US_ASCII), candidates.first())
    }

    @Test
    fun nativeInvitationStillReadsWhenCadenzaWebIsOff() {
        val candidates = resultPayloadCandidates(qrResult(nativeInvitation))

        assertArrayEquals(nativeInvitation.toByteArray(Charsets.US_ASCII), candidates.first())
    }

    @Test
    fun unrelatedAddressesYieldNoInvitation() {
        assertNull(webWrappedInvitation("http://example.com/#hello"))
        assertNull(webWrappedInvitation("http://192.168.1.20:43129/"))
        assertNull(webWrappedInvitation(nativeInvitation))
    }

    private fun qrResult(text: String): Result = Result(text, text.toByteArray(Charsets.UTF_8), null, BarcodeFormat.QR_CODE)
}
