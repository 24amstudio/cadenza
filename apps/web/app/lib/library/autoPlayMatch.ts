import type { AutoPlayItem, Song } from '../protocol/types';

// Music does not identify AutoPlay songs, so a request finds the catalog recording with the same title and artist.
// A version suffix such as "(Remastered 2014)" names the same recording.
export function matchesAutoPlay(item: AutoPlayItem, song: Song): boolean {
  return (
    baseTitle(item.title) === baseTitle(song.title) &&
    normalizeName(item.artist) === normalizeName(song.artist)
  );
}

function baseTitle(value: string): string {
  return normalizeName(value.replace(/\s*\([^)]*\)/g, ''));
}

function normalizeName(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}
