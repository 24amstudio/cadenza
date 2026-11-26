package app.cadenza.remote.updates

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class HostLanUpdateTest {
    private val digest = "a".repeat(64)

    private fun offer(
        path: String = "/api/v1/updates/remote/android.apk",
        sha: String = digest,
    ): String =
        JSONObject()
            .put("version", "0.3.4")
            .put("build_number", 12)
            .put("sha256", sha)
            .put("size_bytes", 1024)
            .put("lan_download_path", path)
            .toString()

    @Test
    fun aHostOfferIsReadWithItsDigestAndDownloadPath() {
        val offer = HostLanUpdate.parseOffer(offer())

        assertEquals(12L, offer.buildNumber)
        assertEquals(digest, offer.sha256)
        assertEquals("/api/v1/updates/remote/android.apk", offer.downloadPath)
    }

    @Test
    fun anOfferThatPointsOutsideTheUpdatePathOrHasNoDigestIsRefused() {
        assertThrows(IllegalArgumentException::class.java) {
            HostLanUpdate.parseOffer(offer(path = "/api/v1/settings"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            HostLanUpdate.parseOffer(offer(sha = "not-a-digest"))
        }
    }

    @Test
    fun resumedRangesCoverTheRestOfTheFileWithoutGapsOrOverlap() {
        val ranges = HostLanUpdate.rangesFrom(offset = 5, size = 20_000_000)

        assertEquals(5L, ranges.first().first)
        assertEquals(19_999_999L, ranges.last().last)
        ranges.zipWithNext { earlier, later -> assertEquals(earlier.last + 1, later.first) }
        assert(ranges.all { it.last - it.first + 1 <= HostLanUpdate.RANGE_BYTES })
    }
}
