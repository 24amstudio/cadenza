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
}

export interface QueueEntry {
  id: string;
  requesterName: string;
  song: Song;
  estimatedWaitMs: number | null;
}

export interface Snapshot {
  hostId: string;
  hostEpoch: string;
  revision: number;
  sequence: number;
  playing: boolean;
  volume: number;
  current: CurrentPlayback | null;
  queue: QueueEntry[];
  synchronized: boolean;
  issue: string | null;
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
}

export type CommandOutcome = 'applied' | 'rejected' | 'expired' | 'unconfirmed';

export interface CommandResult {
  commandId: string;
  outcome: CommandOutcome;
  revision: number;
  message: string | null;
  errorCode: string | null;
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
  | { kind: 'playback.volume'; percent: number };

export interface ClockSample {
  sentAtRemoteMs: number;
  receivedAtHostMs: number;
  sentAtHostMs: number;
}
