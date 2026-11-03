export type TransportKind = 'webrtc' | 'websocket' | 'sse' | 'bluetooth';

export type ConnectionState =
  'unpaired' | 'connecting' | 'connected' | 'unreachable';

export type PairingState = 'idle' | 'scanning' | 'paired' | 'failed';

export type CommandPayload = Record<string, string | number | boolean | null>;

export interface Song {
  id: string;
  title: string;
  artist: string;
  album: string;
  artwork: string;
  durationSeconds: number;
}

export interface QueueItem extends Song {
  requestId: string;
  requester: string;
  waitLabel: string;
}

export interface Snapshot {
  revision: number;
  current: Song | null;
  positionSeconds: number;
  isPlaying: boolean;
  queue: QueueItem[];
  lyricsAvailable: boolean;
}

export interface TransportStatus {
  kind: TransportKind;
  label: string;
  state: ConnectionState;
  detail: string;
}

export interface CommandReceipt {
  commandId: string;
  outcome: 'accepted' | 'rejected' | 'pending' | 'expired';
  message: string;
}

export interface RemoteTransport {
  readonly kind: TransportKind;
  connect(): Promise<void>;
  close(): void;
  send(command: string, payload: CommandPayload): Promise<CommandReceipt>;
}
