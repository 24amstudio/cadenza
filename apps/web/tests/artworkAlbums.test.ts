import { describe, expect, test } from 'bun:test';
import { ArtworkAlbums } from '../app/lib/host/artworkAlbums';
import type { Song } from '../app/lib/protocol/types';

function song(id: string, album: string, artworkUrl: string): Song {
  return {
    source: 'catalog',
    id,
    title: `Track ${id}`,
    artist: 'Tame Impala',
    album,
    durationMs: 200_000,
    artworkUrl,
  };
}

function albumsHolding(urls: string[]) {
  const held = new Set(urls);

  return { albums: new ArtworkAlbums((url) => held.has(url)), held };
}

describe('ArtworkAlbums', () => {
  test('a later song of the same album shows the cover already held, not its own address', () => {
    const coverUrl = 'https://art.example/1.jpg';
    const laterUrl = 'https://art.example/2.jpg';
    const { albums, held } = albumsHolding([]);

    albums.note(song('1', 'The Slow Rush', coverUrl));
    held.add(coverUrl);
    albums.delivered(coverUrl);
    albums.note(song('2', 'The slow rush', laterUrl));

    expect(albums.shown(laterUrl)).toBe(coverUrl);
  });

  test('a cover from another album, or none yet, is not shared', () => {
    const coverUrl = 'https://art.example/1.jpg';
    const otherUrl = 'https://art.example/3.jpg';
    const { albums, held } = albumsHolding([]);

    albums.note(song('1', 'The Slow Rush', coverUrl));
    held.add(coverUrl);
    albums.delivered(coverUrl);
    albums.note(song('3', 'Currents', otherUrl));

    expect(albums.shown(otherUrl)).toBe(otherUrl);

    held.clear();
    expect(albums.shown(otherUrl)).toBe(otherUrl);
  });

  test('a song whose own cover is already held keeps its own address', () => {
    const ownUrl = 'https://art.example/2.jpg';
    const { albums } = albumsHolding([ownUrl]);

    albums.note(song('2', 'The Slow Rush', ownUrl));

    expect(albums.shown(ownUrl)).toBe(ownUrl);
  });
});
