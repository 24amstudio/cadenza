// The narrow Music.app scripting surface used by the owned JXA resource.
interface MusicTrack {
  persistentID(): string;
  get favorited(): () => boolean;
  set favorited(value: boolean);
  duplicate(query: { to: MusicPlaylist }): void;
  class(): string;
  // Music answers "missing value" (null here) for a stream, which has no length.
  duration(): number | null;
  name(): string;
  artist(): string;
  album(): string;
  kind(): string;
  // Music names a music video's media kind "music video". Songs and streams have other media kinds.
  mediaKind(): string;
  // File tracks expose a POSIX path or file URL via location().
  location?(): string | null;
  play(): void;
}

// A set of tracks read one property at a time: each call is a single Apple event for the whole set.
interface MusicTrackSet {
  length: number;
  persistentID(): string[];
  class(): string[];
  name(): string[];
  artist(): string[];
  album(): string[];
  duration(): (number | null)[];
  discNumber(): number[];
  trackNumber(): number[];
  mediaKind?(): string[];
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
  whose(query: { persistentID: string } | { name: string }): MusicPlaylist[];
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
  make(spec: {
    new: 'userPlaylist';
    withProperties: { name: string };
  }): MusicPlaylist;
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
