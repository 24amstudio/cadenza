import type { Song } from '~/lib/protocol/types';

export interface NowPlayingMetadata {
  title: string;
  artist: string;
  album: string;
}

/** The text the operating system shows for the playing song. Missing fields are empty, not invented. */
export function nowPlayingMetadata(
  song: Song | null,
): NowPlayingMetadata | null {
  if (song === null) return null;

  return { title: song.title, artist: song.artist, album: song.album };
}
