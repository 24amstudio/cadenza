import type { Song } from '~/lib/protocol/types';

const appName = 'Cadenza Remote';

// The tab title names the song, so a background tab still shows what is playing.
export function documentTitle(song: Song | null): string {
  const title = song?.title.trim() ?? '';

  if (title === '') return appName;

  const artist = song?.artist.trim() ?? '';

  return artist === ''
    ? `${title} · ${appName}`
    : `${title} — ${artist} · ${appName}`;
}

export interface SongChangeDetector {
  // True when a different play starts after a known one. The first play seen is a baseline, not a change.
  observe(occurrenceId: string | null): boolean;
  reset(): void;
}

// Reports can repeat for the same play, such as on reconnect, so only a new occurrence counts as a change.
export function createSongChangeDetector(): SongChangeDetector {
  let last: string | null = null;

  return {
    observe(occurrenceId) {
      if (occurrenceId === null) return false;

      const changed = last !== null && last !== occurrenceId;
      last = occurrenceId;

      return changed;
    },
    reset() {
      last = null;
    },
  };
}
