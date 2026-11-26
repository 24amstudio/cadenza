package app.cadenza.remote

import app.cadenza.remote.model.artistMotionNameIsValid
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArtistMotionRequestTest {
    @Test
    fun aBlankOrOverlongArtistNameIsNotRequestedFromTheHost() {
        assertTrue(artistMotionNameIsValid("Payung Teduh"))
        assertTrue(artistMotionNameIsValid("a".repeat(200)))
        assertFalse(artistMotionNameIsValid("   "))
        assertFalse(artistMotionNameIsValid("a".repeat(201)))
    }
}
