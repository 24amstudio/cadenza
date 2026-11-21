import type { HistoryEntry } from './history';
import { songKey } from './identity';

export interface HistoryArtist {
  name: string;
  plays: number;
}

export interface HistorySummary {
  plays: number;
  // Full song lengths of the plays. A browser cannot measure how much of each song was heard.
  songTimeMs: number;
  songs: number;
  artists: number;
  topArtists: HistoryArtist[];
}

const topArtistLimit = 5;

// Requests are not plays, so only played entries count. Each artist is named as the Host reports it.
export function summarizeHistory(entries: HistoryEntry[]): HistorySummary {
  const plays = entries.filter((entry) => entry.kind === 'played');
  const songs = new Set<string>();
  const artistPlays = new Map<string, number>();
  let songTimeMs = 0;

  for (const entry of plays) {
    songs.add(songKey(entry.song));
    songTimeMs += entry.song.durationMs ?? 0;
    const artist = entry.song.artist.trim();

    if (artist !== '')
      artistPlays.set(artist, (artistPlays.get(artist) ?? 0) + 1);
  }

  const topArtists = [...artistPlays]
    .map(([name, count]) => ({ name, plays: count }))
    .sort((a, b) => b.plays - a.plays || a.name.localeCompare(b.name))
    .slice(0, topArtistLimit);

  return {
    plays: plays.length,
    songTimeMs,
    songs: songs.size,
    artists: artistPlays.size,
    topArtists,
  };
}
