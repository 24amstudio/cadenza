import type { PairingProof } from '../protocol/encode';
import type { CredentialStore } from './credentials';
import type { TasteDigest } from '../tasteDigest';
import type {
  CommandResult,
  HostUpdateStatus,
  LyricDocument,
  Snapshot,
  Welcome,
} from '../protocol/types';

export type HostPhase =
  | 'unpaired'
  | 'pairing'
  | 'pairing-failed'
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'bluetooth-idle';

export type Readiness = 'ready' | 'syncing' | 'offline';

// What the client is waiting on from the Host, keyed by request ID.
export interface PendingPairing {
  proof: PairingProof;
  name: string;
}

export type PendingRequest =
  | { kind: 'lyrics'; occurrenceId: string }
  | {
      kind: 'artwork';
      artworkUrl: string;
      lane: ArtworkLane;
      occurrenceId: string | null;
    }
  | { kind: 'rename'; name: string };

export type HostChange =
  | { kind: 'phase'; phase: HostPhase; attempt: number; message: string | null }
  | { kind: 'welcome'; welcome: Welcome }
  | { kind: 'snapshot'; snapshot: Snapshot }
  | { kind: 'clock'; offsetMs: number; roundTripMs: number }
  | { kind: 'hostUpdate'; status: HostUpdateStatus }
  // Each frame sent or received, so the sidebar can show traffic in both directions.
  | { kind: 'traffic'; direction: 'in' | 'out' }
  | { kind: 'lyrics'; lyrics: LyricDocument }
  | { kind: 'lyricsUnavailable'; occurrenceId: string | null }
  // A preview has full: false. The full image has full: true, and so does a failure, with a null image. The request ID
  // is null when nothing could be sent.
  | {
      kind: 'artwork';
      artworkUrl: string;
      dataUrl: string | null;
      full: boolean;
      requestId: string | null;
    }
  // A null video is a failure, or the Host's answer that the song has no motion when unavailable is true.
  | {
      kind: 'motion';
      artworkUrl: string;
      video: Uint8Array<ArrayBuffer> | null;
      unavailable: boolean;
      requestId: string | null;
    }
  | { kind: 'commandResolved'; result: CommandResult }
  | { kind: 'notice'; message: string };

// Only the methods the client uses. Browser WebSocket instances are adapted to this shape by the app.
export interface SocketLike {
  onOpen: (() => void) | null;
  onMessage: ((text: string) => void) | null;
  onClose: (() => void) | null;
  send(text: string): void;
  close(): void;
}

export interface HostClientOptions {
  url: string;
  remoteVersion: string;
  defaultName: string;
  openSocket: (url: string) => SocketLike;
  credentials: CredentialStore;
  monotonicNow: () => number;
  schedule: (callback: () => void, delayMs: number) => () => void;
  newId: () => string;
  onChange: (change: HostChange) => void;
  // Asks for a preview before the full artwork. Only the Bluetooth page sets this, and only the Host's capability enables it.
  progressiveArtwork?: boolean;
  // What this browser shares at connect once the listener opts in. Null sends no digest.
  tasteDigest?: () => TasteDigest | null;
}

export type ArtworkLane = 'preview' | 'still' | 'motion';

// What the page asks an artwork for. A preview is the small image alone. A still is the full image. Motion is the playing
// song's video, asked for apart from the still so a failed or refused video never leaves the cover at preview size.
export type ArtworkMode =
  | { kind: 'preview' }
  | { kind: 'still' }
  | { kind: 'motion'; occurrenceId: string };
