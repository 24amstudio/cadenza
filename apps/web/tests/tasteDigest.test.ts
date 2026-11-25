import { describe, expect, test } from 'bun:test';
import type { HistoryEntry } from '../app/lib/library/history';
import { encodeHello } from '../app/lib/protocol/encode';
import type { Song } from '../app/lib/protocol/types';
import {
  buildTasteDigest,
  setTasteDigestOptIn,
  tasteDigestOptedIn,
} from '../app/lib/tasteDigest';

function song(id: string, artist: string): Song {
  return {
    source: 'catalog',
    id,
    title: `Song ${id}`,
    artist,
    album: '',
    durationMs: null,
    artworkUrl: null,
  };
}

function played(id: string, artist: string): HistoryEntry {
  return {
    id,
    kind: 'played',
    at: 0,
    occurrenceId: null,
    song: song(id, artist),
  };
}

describe('taste digest', () => {
  test('artists rank by plays, requests do not count, and blank artists are left out', () => {
    const digest = buildTasteDigest(
      [
        played('1', 'Artist A'),
        played('2', 'Artist A'),
        played('3', 'Artist B'),
        { ...played('4', 'Artist C'), kind: 'requested' },
        played('5', '  '),
      ],
      [],
    );

    expect(digest.topArtists).toEqual(['Artist A', 'Artist B']);
    expect(digest.topGenres).toEqual([]);
  });

  test('favorite song IDs are distinct and the digest holds no more than its limits', () => {
    const history = Array.from({ length: 25 }, (_, index) =>
      played(`h${index}`, `Artist ${index}`),
    );

    const favorites = [song('1', 'A'), song('1', 'A'), song('2', 'B')];

    const digest = buildTasteDigest(history, favorites);

    expect(digest.topArtists).toHaveLength(20);
    expect(digest.favoritedTrackIds).toEqual(['1', '2']);
  });

  test('the opt-in is off by default and stays off unless the listener turns it on', () => {
    const values = new Map<string, string>();

    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => {
        values.set(key, value);
      },
      removeItem: (key: string) => {
        values.delete(key);
      },
    };

    expect(tasteDigestOptedIn(storage)).toBe(false);
    setTasteDigestOptIn(storage, true);
    expect(tasteDigestOptedIn(storage)).toBe(true);
    setTasteDigestOptIn(storage, false);
    expect(tasteDigestOptedIn(storage)).toBe(false);
  });

  test('the hello carries the digest only when one is given', () => {
    const base = {
      remoteId: 'remote-1',
      token: 'token',
      lastCreditSequence: 0,
      name: 'Tablet',
      remoteVersion: '1.0',
    };

    const withDigest = JSON.parse(
      encodeHello({
        ...base,
        tasteDigest: {
          topArtists: ['Artist A'],
          topGenres: [],
          favoritedTrackIds: ['1'],
        },
      }),
    );

    const withoutDigest = JSON.parse(
      encodeHello({ ...base, tasteDigest: null }),
    );

    expect(withDigest.auth.taste_digest).toEqual({
      top_artists: ['Artist A'],
      top_genres: [],
      favorited_track_ids: ['1'],
    });
    expect(withoutDigest.auth.taste_digest).toBeUndefined();
  });
});
