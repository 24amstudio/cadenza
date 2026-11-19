import { describe, expect, test } from 'bun:test';
import { Favorites, favoritesStorageKey } from '../app/lib/library/favorites';
import {
  History,
  historyLimit,
  historyStorageKey,
  type HistoryEntry,
} from '../app/lib/library/history';
import { groupHistory } from '../app/lib/library/historyGroups';
import { songKey } from '../app/lib/library/identity';
import { keyValueStore, type KeyValueStore } from '../app/lib/library/keyValue';
import type { Song } from '../app/lib/protocol/types';

const breathe: Song = {
  source: 'catalog',
  id: '1440857781',
  title: 'Breathe Deeper',
  artist: 'Tame Impala',
  album: 'The Slow Rush',
  durationMs: 372_000,
  artworkUrl: 'https://example.com/art.jpg',
};

const localDemo: Song = {
  source: 'unknown',
  id: '',
  title: 'Local Demo',
  artist: 'Mia',
  album: 'Sketches',
  durationMs: null,
  artworkUrl: null,
};

function memoryStore(
  values: Map<string, string> = new Map<string, string>(),
): KeyValueStore {
  return {
    read: (key) => values.get(key) ?? null,
    write: (key, value) => {
      values.set(key, value);
    },
  };
}

// A storage that refuses every access, as a blocked or full browser does.
function blockedStore(): KeyValueStore {
  return keyValueStore(() => {
    throw new Error('Storage is blocked.');
  });
}

function refusingItems(): KeyValueStore {
  return keyValueStore(() => ({
    getItem: () => {
      throw new Error('Storage is blocked.');
    },
    setItem: () => {
      throw new Error('Storage is full.');
    },
  }));
}

function requestAt(at: number): HistoryEntry {
  return {
    id: `entry-${at}`,
    kind: 'requested',
    at,
    occurrenceId: null,
    song: breathe,
  };
}

describe('favorites', () => {
  test('a song is a favorite once, and a second press removes it', () => {
    const favorites = new Favorites(memoryStore());

    expect(favorites.toggle(breathe)).toBe(true);
    expect(
      favorites.toggle({ ...breathe, title: 'Breathe Deeper (Live)' }),
    ).toBe(false);
    expect(favorites.list()).toEqual([]);
  });

  test('a song without a Host identity is matched by its normalized text', () => {
    const favorites = new Favorites(memoryStore());

    favorites.toggle(localDemo);

    expect(
      favorites.has({ ...localDemo, title: '  local   DEMO ', artist: 'mia' }),
    ).toBe(true);
    expect(songKey(localDemo)).toBe(
      songKey({ ...localDemo, title: 'LOCAL demo' }),
    );
  });

  test('favorites are read back from the versioned key after a reload', () => {
    const values = new Map<string, string>();

    new Favorites(memoryStore(values)).toggle(breathe);

    expect(values.has(favoritesStorageKey)).toBe(true);
    expect(new Favorites(memoryStore(values)).list()).toEqual([breathe]);
  });

  test('a damaged favorite is skipped and the others are kept', () => {
    const values = new Map<string, string>([
      [
        favoritesStorageKey,
        JSON.stringify([{ source: 'catalog', id: 42 }, breathe]),
      ],
    ]);

    expect(new Favorites(memoryStore(values)).list()).toEqual([breathe]);
  });

  test('keeps working for the visit when storage throws', () => {
    const favorites = new Favorites(blockedStore());

    expect(favorites.toggle(breathe)).toBe(true);
    expect(new Favorites(blockedStore()).has(breathe)).toBe(false);
    expect(favorites.has(breathe)).toBe(true);
  });

  test('a refused write is kept in memory, so the page still shows it', () => {
    const store = refusingItems();
    const favorites = new Favorites(store);

    favorites.toggle(breathe);

    expect(new Favorites(store).list()).toEqual([breathe]);
  });
});

describe('history', () => {
  test('a play is recorded once per occurrence', () => {
    const history = new History(memoryStore(), () => 'id');

    expect(history.recordPlayed(breathe, 'occurrence-1', 1)).toBe(true);
    expect(history.recordPlayed(breathe, 'occurrence-1', 2)).toBe(false);
    expect(history.list()).toHaveLength(1);
  });

  test('requests are kept as they happen, newest first', () => {
    const history = new History(memoryStore(), () => 'id');

    history.recordRequested(breathe, 1);
    history.recordRequested(breathe, 2);

    expect(history.list().map((entry) => entry.at)).toEqual([2, 1]);
    expect(history.list().every((entry) => entry.occurrenceId === null)).toBe(
      true,
    );
  });

  test('keeps the newest 200 entries and drops the oldest', () => {
    const history = new History(memoryStore(), () => 'id');

    for (let at = 1; at <= historyLimit + 1; at += 1) {
      history.recordRequested(breathe, at);
    }

    expect(history.list()).toHaveLength(historyLimit);
    expect(history.list()[0]?.at).toBe(historyLimit + 1);
    expect(history.list().at(-1)?.at).toBe(2);
  });

  test('the cap holds after a reload from storage', () => {
    const values = new Map<string, string>();
    const writer = new History(memoryStore(values), () => 'id');

    for (let at = 1; at <= historyLimit + 5; at += 1) {
      writer.recordRequested(breathe, at);
    }

    expect(new History(memoryStore(values), () => 'id').list()).toHaveLength(
      historyLimit,
    );
    expect(values.has(historyStorageKey)).toBe(true);
  });

  test('clearing removes every entry from storage', () => {
    const values = new Map<string, string>();
    const history = new History(memoryStore(values), () => 'id');

    history.recordRequested(breathe, 1);
    history.clear();

    expect(new History(memoryStore(values), () => 'id').list()).toEqual([]);
  });

  test('keeps recording while storage throws', () => {
    const history = new History(blockedStore(), () => 'id');

    expect(history.recordPlayed(breathe, 'occurrence-1', 1)).toBe(true);
    expect(history.recordPlayed(breathe, 'occurrence-1', 2)).toBe(false);
    expect(history.list()).toHaveLength(1);
  });
});

describe('history days', () => {
  test('entries are grouped by local calendar day, Today and Yesterday first', () => {
    const now = new Date(2026, 10, 19, 15, 30);
    const todayEvening = new Date(2026, 10, 19, 9, 5).getTime();
    const yesterdayNight = new Date(2026, 10, 18, 23, 40).getTime();
    const threeDaysAgo = new Date(2026, 10, 16, 12, 0).getTime();

    const groups = groupHistory(
      [
        requestAt(todayEvening),
        requestAt(yesterdayNight),
        requestAt(threeDaysAgo),
      ],
      now,
    );

    expect(groups.map((group) => group.label).slice(0, 2)).toEqual([
      'Today',
      'Yesterday',
    ]);
    expect(groups).toHaveLength(3);
    expect(groups[2]?.label).not.toBe('');
    expect(groups[2]?.entries).toHaveLength(1);
  });
});
