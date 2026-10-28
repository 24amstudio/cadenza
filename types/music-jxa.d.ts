// The narrow Music.app scripting surface used by the owned JXA resource.
interface MusicTrack {
  persistentID(): string;
  duration(): number;
  name(): string;
  artist(): string;
  album(): string;
}

interface MusicTrackCollection extends ArrayLike<MusicTrack> {
  whose(query: { persistentID: string }): MusicTrack[];
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
  search(
    library: MusicLibrary,
    query: { for: string; only: 'songs' },
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
}

declare function Application(name: 'Music'): MusicApplication;

declare function delay(seconds: number): void;

declare var run: (argv: string[]) => string;
