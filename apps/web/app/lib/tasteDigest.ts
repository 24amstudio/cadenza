import type { HistoryEntry } from '~/lib/library/history';
import type { Song } from '~/lib/protocol/types';

/** The taste a Remote shares at connect. It names artists and favorite songs. Genres are not kept, so none are sent. */
export interface TasteDigest {
  topArtists: string[];
  topGenres: string[];
  favoritedTrackIds: string[];
}

const artistLimit = 20;
const favoriteLimit = 200;

/** The artists this listener plays most, and the favorite song IDs, from this browser's own history and favorites. */
export function buildTasteDigest(
  history: HistoryEntry[],
  favorites: Song[],
): TasteDigest {
  const plays = new Map<string, number>();

  for (const entry of history) {
    const artist = entry.song.artist.trim();

    if (entry.kind !== 'played' || artist === '') continue;
    plays.set(artist, (plays.get(artist) ?? 0) + 1);
  }

  const topArtists = [...plays.entries()]
    .sort((left, right) => right[1] - left[1])
    .slice(0, artistLimit)
    .map(([artist]) => artist);

  return {
    topArtists,
    topGenres: [],
    favoritedTrackIds: [...new Set(favorites.map((song) => song.id))].slice(
      0,
      favoriteLimit,
    ),
  };
}

const optInKey = 'cadenza.web.tasteDigest.v1';

/** Off until the listener turns it on. The digest is sent only when this is true. */
export function tasteDigestOptedIn(
  storage: Pick<Storage, 'getItem'> | null,
): boolean {
  try {
    return storage?.getItem(optInKey) === 'true';
  } catch {
    return false;
  }
}

export function setTasteDigestOptIn(
  storage: Pick<Storage, 'setItem' | 'removeItem'> | null,
  enabled: boolean,
): void {
  try {
    if (enabled) storage?.setItem(optInKey, 'true');
    else storage?.removeItem(optInKey);
  } catch {
    // A browser that blocks storage keeps the digest off, which is the safe default.
  }
}
