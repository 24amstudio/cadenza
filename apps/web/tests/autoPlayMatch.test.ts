import { describe, expect, test } from 'bun:test';
import { matchesAutoPlay } from '../app/lib/library/autoPlayMatch';
import type { Song } from '../app/lib/protocol/types';

function catalog(title: string, artist: string): Song {
  return {
    source: 'catalog',
    id: '1',
    title,
    artist,
    album: '',
    durationMs: null,
    artworkUrl: null,
  };
}

describe('AutoPlay matching', () => {
  test('matches the same recording despite a version suffix, accents, and case', () => {
    const item = { title: 'Café Song (Remastered 2014)', artist: 'Beyoncé' };

    expect(matchesAutoPlay(item, catalog('Cafe Song', 'beyonce'))).toBe(true);
  });

  test('does not match a different song by the same artist', () => {
    const item = { title: 'Halo', artist: 'Beyonce' };

    expect(matchesAutoPlay(item, catalog('Irreplaceable', 'Beyonce'))).toBe(
      false,
    );
  });
});
