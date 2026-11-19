import type { Song, SongIdentity } from '../protocol/types';

// The identity the Host can queue a song by. A song with no catalog or library ID has none.
export function identityOf(song: Song): SongIdentity | null {
  if (song.source === 'unknown' || song.id === '') return null;

  return { source: song.source, id: song.id };
}

// Names a song inside this browser. A song without a Host identity is matched by its normalized text, so it can still be
// kept as a favorite even though it cannot be queued.
export function songKey(song: Song): string {
  const identity = identityOf(song);

  if (identity !== null) return `${identity.source}:${identity.id}`;

  return `text:${[song.title, song.artist, song.album].map(normalize).join('|')}`;
}

function normalize(text: string): string {
  return text.trim().replace(/\s+/g, ' ').toLowerCase();
}
