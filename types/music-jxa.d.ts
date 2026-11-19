// The narrow Music.app scripting surface used by the owned JXA resource.
interface MusicTrack {
  persistentID(): string;
  class(): string;
  duration(): number;
  name(): string;
  artist(): string;
  album(): string;
}

// A set of tracks read one property at a time: each call is a single Apple event for the whole set.
interface MusicTrackSet {
  length: number;
  persistentID(): string[];
  class(): string[];
  name(): string[];
  artist(): string[];
  album(): string[];
  duration(): number[];
  discNumber(): number[];
  trackNumber(): number[];
}

interface MusicTrackCollection extends ArrayLike<MusicTrack> {
  whose(query: { persistentID: string }): MusicTrack[];
}

// The same collection filtered by album or artist name, which returns a set read in bulk.
interface MusicTrackQuery {
  whose(query: { album: string } | { artist: string }): MusicTrackSet;
}

interface MusicPlaylist {
  name(): string;
  tracks: MusicTrackSet & {
    whose(query: { persistentID: string }): MusicTrack[];
  };
}

interface MusicPlaylistCollection extends ArrayLike<MusicPlaylist> {
  whose(query: { persistentID: string }): MusicPlaylist[];
  name(): string[];
  persistentID(): string[];
  class(): string[];
  specialKind(): string[];
}

interface MusicLibrary {
  tracks: MusicTrackCollection;
}

interface MusicApplication {
  running(): boolean;
  launch(): void;
  playerState(): string;
  currentTrack(): MusicTrack;
  libraryPlaylists: ArrayLike<MusicLibrary>;
  userPlaylists: MusicPlaylistCollection;
  search(
    library: MusicLibrary,
    query: {
      for: string;
      only: 'albums' | 'all' | 'artists' | 'composers' | 'displayed' | 'names';
    },
  ): ArrayLike<MusicTrack>;
  reveal(track: MusicTrack): void;
  play(): void;
  pause(): void;
  nextTrack(): void;
  previousTrack(): void;
  stop(): void;
  get soundVolume(): () => number;
  set soundVolume(value: number);
  get playerPosition(): () => number;
  set playerPosition(value: number);
  get shuffleEnabled(): () => boolean;
  set shuffleEnabled(value: boolean);
  get songRepeat(): () => string;
  set songRepeat(value: string);
}

declare function Application(name: 'Music'): MusicApplication;

declare function delay(seconds: number): void;

declare var run: (argv: string[]) => string;
