package app.cadenza.remote.model

import app.cadenza.remote.data.Song

// Music gives each library song its own cover address, but every track of an album shows the same cover. A Remote
// that already holds one of an album's covers shows it for the album's other tracks instead of asking the Host again.
internal fun albumKey(song: Song): String? {
    val album = song.album.trim()
    if (album.isEmpty()) return null

    return "${song.artist.trim().lowercase()}\u001F${album.lowercase()}"
}

// The address of a held cover of the same album as [url], or null when none is held yet.
internal fun heldAlbumCover(
    url: String,
    songs: Iterable<Song>,
    held: (String) -> Boolean,
): String? {
    val album = songs.firstOrNull { it.artworkUrl == url }?.let(::albumKey) ?: return null

    return songs
        .asSequence()
        .filter { albumKey(it) == album }
        .mapNotNull { it.artworkUrl }
        .firstOrNull { it != url && held(it) }
}
