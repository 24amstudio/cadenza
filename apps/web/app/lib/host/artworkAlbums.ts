import type { Song } from '../protocol/types';

// Every track of an album shows the same cover, but Music gives each song its own artwork address. The page keeps the
// cover it already holds for an album and shows it for the album's other songs, so no transfer repeats it.
export class ArtworkAlbums {
  // Whether the page holds an image at this address.
  private readonly held: (address: string) => boolean;
  constructor(held: (address: string) => boolean) {
    this.held = held;
  }

  // The album of each artwork address the page has seen.
  private readonly albumOfUrl = new Map<string, string>();
  // The address of the cover the page holds for each album.
  private readonly coverOfAlbum = new Map<string, string>();
  // An address that is shown as another album's cover.
  private readonly coverOfUrl = new Map<string, string>();

  // Remembers which album a song's cover belongs to.
  note(song: Song): void {
    const url = song.artworkUrl;
    const album = albumKey(song);

    if (url === null || album === null) return;
    this.albumOfUrl.set(url, album);
  }

  // A full image is held for this address, so its album can share it.
  delivered(url: string): void {
    const album = this.albumOfUrl.get(url);

    if (album !== undefined) this.coverOfAlbum.set(album, url);
  }

  // The address to show and request for this cover: its own when the page holds it, otherwise the held cover of the
  // same album.
  shown(url: string): string {
    const held = this.held;

    if (held(url)) return url;

    const shared = this.coverOfUrl.get(url);

    if (shared !== undefined && held(shared)) return shared;

    const album = this.albumOfUrl.get(url);

    const cover =
      album === undefined ? undefined : this.coverOfAlbum.get(album);

    if (cover === undefined || cover === url || !held(cover)) return url;

    if (this.coverOfUrl.size >= albumLimit) this.coverOfUrl.clear();
    this.coverOfUrl.set(url, cover);

    return cover;
  }
}

// Bounds the aliases so a long session cannot grow them without limit.
const albumLimit = 512;

function albumKey(song: Song): string | null {
  const album = song.album.trim().toLowerCase();

  if (album === '') return null;

  return `${song.artist.trim().toLowerCase()}\u0000${album}`;
}
