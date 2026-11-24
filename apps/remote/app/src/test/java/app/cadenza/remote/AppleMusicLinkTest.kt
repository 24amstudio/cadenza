package app.cadenza.remote

import app.cadenza.remote.share.AppleMusicLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppleMusicLinkTest {
    @Test
    fun anAlbumLinkThatNamesATrackKeepsBothIdentifiers() {
        val link = AppleMusicLink.parse("Listen https://music.apple.com/us/album/some-album/1234?i=5678 now")

        assertEquals(AppleMusicLink(AppleMusicLink.Kind.ALBUM, "1234", "5678"), link)
    }

    @Test
    fun aSongPlaylistAndPlainAlbumLinkEachKeepTheirKind() {
        assertEquals(
            AppleMusicLink(AppleMusicLink.Kind.SONG, "999", "999"),
            AppleMusicLink.parse("https://music.apple.com/us/song/title/999"),
        )
        assertEquals(
            AppleMusicLink(AppleMusicLink.Kind.PLAYLIST, "pl.u-abc", null),
            AppleMusicLink.parse("https://music.apple.com/us/playlist/mix/pl.u-abc"),
        )
        assertEquals(
            AppleMusicLink(AppleMusicLink.Kind.ALBUM, "1234", null),
            AppleMusicLink.parse("https://music.apple.com/us/album/some-album/1234"),
        )
    }

    @Test
    fun otherHostsPlainHttpAndMalformedIdentifiersAreRefused() {
        assertNull(AppleMusicLink.parse("https://music.apple.com.evil.example/us/album/x/1"))
        assertNull(AppleMusicLink.parse("http://music.apple.com/us/album/x/1"))
        assertNull(AppleMusicLink.parse("https://music.apple.com/us/album/x/12%20drop"))
        assertNull(AppleMusicLink.parse("just some words"))
    }
}
