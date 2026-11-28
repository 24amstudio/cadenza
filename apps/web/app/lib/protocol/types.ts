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
  // Absent on songs from Hosts that predate music-video search; those are songs.
  mediaType?: 'song' | 'musicVideo' | undefined;
}

export type VideoOutputTarget = 'host_display' | 'cast_transmitter';

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
  label: string;
  display: CastDisplay;
}

// What the Host is sending to a Cast device, if anything. `reason` is set when a transmission failed.
export interface CastTransmitState {
  state: 'idle' | 'starting' | 'transmitting' | 'failed';
  device: string | null;
  reason: string | null;
  // The codec and channel count the Host sends, and the one status line to show. Absent when nothing is sent.
  route?: CastRoute | null;
  status?: CastRouteStatus | null;
}

// A codec and channel count, such as AC-3 with 6 channels.
export interface CastRoute {
  codec: string;
  channels: number;
}

// The Host's status line for a transmission. `mismatch` marks a receiver that plays something other than what is sent.
export interface CastRouteStatus {
  text: string;
  mismatch: boolean;
}

// A Cadenza TV browser or Android TV that the Host has approved. `transmitting` means it is receiving audio.
export interface StageDevice {
  receiverId: string;
  name: string;
  transport: string;
  transmitting: boolean;
  sent?: CastRoute | null;
  playing?: CastRoute | null;
  playingPath?: string | null;
  status?: CastRouteStatus | null;
}

// A TV that shows a PIN and waits for approval. Any paired Remote may approve it with the PIN.
export interface PendingStage {
  receiverId: string;
  name: string;
  pin: string;
  expiresInMs: number;
}

export interface CastState {
  presentation: CastPresentation;
  devices: CastDevice[];
  transmit: CastTransmitState | null;
  stages: StageDevice[];
  pendingStages: PendingStage[];
}

export type SingStatus =
  'unavailable' | 'preparing' | 'ready' | 'active' | 'failed';

export interface SingSession {
  status: SingStatus;
  vocalPercent: number;
  latencyMs: number | null;
  issue: string | null;
  modelReady: boolean | null;
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
  // Where a music video's karaoke line is shown. Absent from Hosts that predate the setting.
  videoOutput?: VideoOutputTarget | null;
  // The AVR lip-sync offset, in milliseconds. Absent from Hosts that predate it.
  lipSyncOffsetMs?: number | null;
  remoteAudioTarget?: string | null;
  // The Sing mode session. Absent from Hosts that predate Sing.
  sing?: SingSession | null;
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
  // 'end' marks a second voice, which the lyrics show right-aligned. 'center' marks a group, shown in the middle.
  align: 'start' | 'center' | 'end';
}

export interface LyricDocument {
  occurrenceId: string;
  revision: string;
  translationSource: string;
  source: string;
  lines: LyricLine[];
  issue: string | null;
  // The karaoke nudge the person saved for this track, in milliseconds. Absent from Hosts that predate it.
  userOffsetMs?: number | null;
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
  // The Host's LAN address, and the Cadenza Web socket's port on it while the Host runs that listener.
  hostAddress: string | null;
  webHost: string | null;
  webPort: number | null;
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
  | { kind: 'cast.transmit'; device: string; start: boolean }
  | { kind: 'video.output'; target: VideoOutputTarget }
  | { kind: 'cast.presentation'; presentation: CastPresentation }
  | { kind: 'stage.approve'; pin: string }
  | { kind: 'lip_sync.offset'; offsetMs: number }
  | { kind: 'sing.enable' | 'sing.disable'; occurrenceId: string }
  | { kind: 'sing.mix'; occurrenceId: string; vocalPercent: number }
  | { kind: 'lyrics.offset'; song: SongIdentity; offsetMs: number }
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
