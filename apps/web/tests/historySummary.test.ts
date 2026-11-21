import { describe, expect, test } from 'bun:test';
import type { HistoryEntry } from '../app/lib/library/history';
import { summarizeHistory } from '../app/lib/library/historySummary';
import type { Song } from '../app/lib/protocol/types';

function song(id: string, artist: string, durationMs: number | null): Song {
  return {
    source: 'library',
    id,
    title: `Title ${id}`,
    artist,
    album: '',
    durationMs,
    artworkUrl: null,
  };
}

function entry(
  id: string,
  kind: HistoryEntry['kind'],
  value: Song,
): HistoryEntry {
  return { id, kind, at: 0, occurrenceId: null, song: value };
}

describe('summarizeHistory', () => {
  test('counts plays and their song time, and leaves requests out', () => {
    const summary = summarizeHistory([
      entry('1', 'played', song('a', 'Artist A', 200_000)),
      entry('2', 'played', song('a', 'Artist A', 200_000)),
      entry('3', 'requested', song('b', 'Artist B', 300_000)),
      entry('4', 'played', song('c', 'Artist B', null)),
    ]);

    expect(summary).toMatchObject({
      plays: 3,
      songTimeMs: 400_000,
      songs: 2,
      artists: 2,
    });
  });

  test('ranks the most played artists first, ties by name', () => {
    const summary = summarizeHistory([
      entry('1', 'played', song('a', 'Zed', 1)),
      entry('2', 'played', song('b', 'Amy', 1)),
      entry('3', 'played', song('c', 'Amy', 1)),
      entry('4', 'played', song('d', 'Bo', 1)),
    ]);

    expect(summary.topArtists).toEqual([
      { name: 'Amy', plays: 2 },
      { name: 'Bo', plays: 1 },
      { name: 'Zed', plays: 1 },
    ]);
  });

  test('an empty history is all zeros', () => {
    expect(summarizeHistory([])).toEqual({
      plays: 0,
      songTimeMs: 0,
      songs: 0,
      artists: 0,
      topArtists: [],
    });
  });
});
