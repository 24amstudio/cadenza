// Domain types used by the web client. Wire names are snake_case in shared/protocol/v1; these are their camelCase
// equivalents after decoding.

export interface Song {
  source: 'catalog' | 'library' | 'unknown';
  id: string;
  title: string;
  artist: string;
  album: string;
  durationMs: number | null;
  artworkUrl: string | null;
}

export interface CurrentPlayback {
  occurrenceId: string;
  entryId: string | null;
  requesterName: string;
  song: Song;
  positionMs: number;
  sampledAtHostMs: number;
  // The song's cover at most 32 by 32 pixels, as base64 JPEG. It arrives with the song.
  artworkPreview?: string | null;
  // A radio stream, which has no length to seek within.
  isLiveRadio?: boolean;
}

export interface QueueEntry {
  id: string;
  requesterName: string;
  song: Song;
  estimatedWaitMs: number | null;
}

export type RepeatMode = 'off' | 'one' | 'all';

// The audio tier Music reports for the current song. 'unknown' until Music's badge has been read.
export type AudioQuality =
  'unknown' | 'lossless' | 'hi_res_lossless' | 'dolby_atmos' | 'aac';

// A song Music plays after the requests. Only the first few arrive, and a Remote cannot change them.
export interface AutoPlayItem {
  title: string;
  artist: string;
}

// A song in the Mac's Music library. Library write-back accepts only these.
export interface LibrarySongIdentity {
  source: 'library';
  id: string;
}

// An audio output the Mac can play to. `id` is the device UID.
export interface AudioOutput {
  id: string;
  name: string;
  transport: string;
  isDefault: boolean;
}

// One suggestion on a Remote's shelf. The Host ranks it, and `evidence` holds the reasons it was chosen.
export interface RecommendationShelfItem {
  source: 'catalog' | 'library';
  id: string;
  title: string;
  artist: string;
  evidence: string[];
}

export type CastPresentation = 'auto' | 'audio_only' | 'full_suite';

// `none` is a screenless speaker, `display` a screen-capable device, and `unknown` one without a readable capability record.
export type CastDisplay = 'none' | 'display' | 'unknown';

export interface CastDevice {
  name: string;
  display: CastDisplay;
}

export interface CastState {
  presentation: CastPresentation;
  devices: CastDevice[];
}

export interface Snapshot {
  hostId: string;
  hostEpoch: string;
  revision: number;
  sequence: number;
  playing: boolean;
  volume: number;
  shuffle: boolean;
  repeat: RepeatMode;
  current: CurrentPlayback | null;
  queue: QueueEntry[];
  totalRemainingMs: number | null;
  quality: AudioQuality;
  autoPlay: AutoPlayItem[];
  synchronized: boolean;
  issue: string | null;
  audioOutputs: AudioOutput[];
  hostBudget: string | null;
  cast: CastState | null;
}

export interface LyricWord {
  text: string;
  startMs: number;
  endMs: number;
}

export interface LyricLine {
  id: string;
  text: string;
  startMs: number;
  endMs: number;
  translation: string | null;
  words: LyricWord[];
  // 'end' marks a second voice, which the lyrics show right-aligned.
  align: 'start' | 'end';
}

export interface LyricDocument {
  occurrenceId: string;
  revision: string;
  translationSource: string;
  source: string;
  lines: LyricLine[];
  issue: string | null;
}

export interface Welcome {
  hostId: string;
  hostName: string;
  hostEpoch: string;
  remoteId: string;
  token: string | null;
  hostTimeMs: number;
  capabilities: string[];
  // The Host's version name and build number, when it reports them.
  hostVersion: string | null;
  hostBuild: number | null;
}

// Where a Host update stands, as the Host reports it: checking, ready, installing, current, or failed.
export interface HostUpdateStatus {
  state: string;
  version: string | null;
  message: string | null;
}

export type CommandOutcome = 'applied' | 'rejected' | 'expired' | 'unconfirmed';

export interface CommandResult {
  commandId: string;
  outcome: CommandOutcome;
  revision: number;
  message: string | null;
  errorCode: string | null;
}

// The identity the Host uses to find a song. A catalog ID is an Apple Music ID; a library ID is a persistent ID.
export interface SongIdentity {
  source: 'catalog' | 'library';
  id: string;
}

export type SearchScope = 'catalog' | 'library';

export type QueueActionKind =
  'queue.enqueue' | 'queue.play_next' | 'queue.play_now';

export interface SongSuggestions {
  terms: string[];
  songs: Song[];
}

export type CommandAction =
  | {
      kind:
        | 'playback.pause'
        | 'playback.resume'
        | 'playback.skip'
        | 'playback.previous';
      occurrenceId: string;
    }
  | { kind: 'playback.seek'; occurrenceId: string; positionMs: number }
  | { kind: 'playback.volume'; percent: number }
  | { kind: 'playback.shuffle'; enabled: boolean }
  | { kind: 'playback.repeat'; mode: RepeatMode }
  | { kind: 'audio.selectOutput'; output: string }
  | { kind: 'library.favorite'; song: LibrarySongIdentity; favorite: boolean }
  | {
      kind: 'library.addToPlaylist';
      name: string;
      songs: LibrarySongIdentity[];
    }
  | { kind: Exclude<QueueActionKind, 'queue.play_now'>; song: SongIdentity }
  | {
      kind: 'queue.play_now';
      song: SongIdentity;
      occurrenceId: string | null;
    };

export interface ClockSample {
  sentAtRemoteMs: number;
  receivedAtHostMs: number;
  sentAtHostMs: number;
}

export type BrowseKind = 'album' | 'artist' | 'playlists' | 'playlist';

// An album or artist is named by its ID or by a song the Host resolves itself. A playlist needs its ID.
export interface BrowseRequest {
  kind: BrowseKind;
  id?: string;
  song?: SongIdentity;
}

export type BrowseCollectionKind = 'album' | 'artist' | 'playlist';

export type BrowseItem =
  | { type: 'song'; song: Song }
  | {
      type: BrowseCollectionKind;
      id: string;
      title: string;
      subtitle: string | null;
      artworkUrl: string | null;
    };

export interface BrowseSection {
  id: string;
  title: string;
  items: BrowseItem[];
}

export interface BrowsePage {
  kind: BrowseKind;
  id: string;
  title: string;
  subtitle: string | null;
  artworkUrl: string | null;
  detail: string | null;
  sections: BrowseSection[];
}
