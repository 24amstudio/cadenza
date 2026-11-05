import { describe, expect, test } from 'bun:test';
import type { Song } from '../app/lib/protocol/types';
import { createSongChangeDetector, documentTitle } from '../app/lib/songAlerts';

const song: Song = {
  source: 'library',
  id: 'song-1',
  title: 'Roda',
  artist: 'Band',
  album: 'Album',
  durationMs: 200_000,
  artworkUrl: null,
};

describe('song change detection', () => {
  test('does not treat the first play or a repeated report of it as a change', () => {
    const detector = createSongChangeDetector();

    expect(detector.observe('occ-1')).toBe(false);
    expect(detector.observe('occ-1')).toBe(false);
  });

  test('reports a different play, including one that starts after playback stopped', () => {
    const detector = createSongChangeDetector();

    detector.observe('occ-1');

    expect(detector.observe('occ-2')).toBe(true);
    expect(detector.observe(null)).toBe(false);
    expect(detector.observe('occ-3')).toBe(true);
  });

  test('starts from a fresh baseline after a reset', () => {
    const detector = createSongChangeDetector();

    detector.observe('occ-1');
    detector.reset();

    expect(detector.observe('occ-2')).toBe(false);
  });
});

describe('document title', () => {
  test('names the song and its artist', () => {
    expect(documentTitle(song)).toBe('Roda — Band · Cadenza Remote');
  });

  test('omits a blank artist and falls back to the app name without a song', () => {
    expect(documentTitle({ ...song, artist: ' ' })).toBe(
      'Roda · Cadenza Remote',
    );
    expect(documentTitle(null)).toBe('Cadenza Remote');
  });
});
