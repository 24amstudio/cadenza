import { describe, expect, test } from 'bun:test';
import { nowPlayingMetadata } from '../app/lib/mediaSession';
import type { Song } from '../app/lib/protocol/types';

const song: Song = {
  source: 'catalog',
  id: '958A4478EDBDEEF8',
  title: 'Breathe Deeper',
  artist: 'Tame Impala',
  album: 'Currents',
  durationMs: 372000,
  artworkUrl: null,
};

describe('nowPlayingMetadata', () => {
  test('the operating system shows the song the Host is playing, and nothing without a song', () => {
    expect(nowPlayingMetadata(song)).toEqual({
      title: 'Breathe Deeper',
      artist: 'Tame Impala',
      album: 'Currents',
    });
    expect(nowPlayingMetadata(null)).toBeNull();
  });

  test('a song with no artist or album keeps those fields empty instead of inventing them', () => {
    expect(nowPlayingMetadata({ ...song, artist: '', album: '' })).toEqual({
      title: 'Breathe Deeper',
      artist: '',
      album: '',
    });
  });
});
