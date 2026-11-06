import type { CommandAction } from './types';

// Outgoing frames carry exactly the keys the Host accepts for each message type. Unknown or extra keys are rejected by
// the Host, so these builders never spread caller-provided objects into a frame.

export interface AuthPayload {
  remoteId: string;
  token: string;
  lastCreditSequence: number;
  name: string;
  remoteVersion: string;
}

export interface CommandEnvelope {
  commandId: string;
  hostEpoch: string;
  expiresAtHostMs: number;
  expectedRevision: number;
  action: CommandAction;
}

// The one-use QR secret pairs over the LAN. The four-digit PIN pairs over Bluetooth, as in Cadenza Remote.
export type PairingProof = { secret: string } | { pin: string };

export function encodePair(
  proof: PairingProof,
  name: string,
  remoteVersion: string,
): string {
  const credential =
    'pin' in proof ? { pin: proof.pin } : { secret: proof.secret };

  return JSON.stringify({
    version: 1,
    type: 'pair',
    pair: {
      ...credential,
      name,
      remote_version: remoteVersion,
      heartbeat: true,
    },
  });
}

export function encodeHello(auth: AuthPayload): string {
  return JSON.stringify({
    version: 1,
    type: 'hello',
    auth: {
      remote_id: auth.remoteId,
      token: auth.token,
      last_credit_sequence: auth.lastCreditSequence,
      name: auth.name,
      remote_version: auth.remoteVersion,
      heartbeat: true,
    },
  });
}

export function encodeRemoteConfigure(requestId: string, name: string): string {
  return JSON.stringify({
    version: 1,
    type: 'remote.configure',
    request_id: requestId,
    name,
    heartbeat: true,
  });
}

// performance.now() is fractional, but the Host accepts integer counters only. A fractional value made every probe fail,
// so the browser never learned the Host clock and every command stayed unsent.
export function encodeClock(requestId: string, sentAtRemoteMs: number): string {
  return JSON.stringify({
    version: 1,
    type: 'clock',
    request_id: requestId,
    clock: { sent_at_remote_ms: Math.round(sentAtRemoteMs) },
  });
}

export function encodeLyricsGet(requestId: string): string {
  return JSON.stringify({
    version: 1,
    type: 'lyrics.get',
    request_id: requestId,
  });
}

export interface ArtworkRequestOptions {
  // A progressive request sends a small preview before the full image.
  progressive: boolean;
  // The preview alone, for a row that is not playing yet.
  previewOnly: boolean;
  // The song a full image is for. The Host stops the request when that song is no longer playing.
  occurrenceId: string | null;
  // Whether the song's motion video may replace the full image.
  motion: boolean;
}

export function encodeArtworkGet(
  requestId: string,
  artworkUrl: string,
  options: ArtworkRequestOptions,
): string {
  // JSON.stringify drops undefined keys, so the Host sees a flag only when it was requested.
  return JSON.stringify({
    version: 1,
    type: 'artwork.get',
    request_id: requestId,
    artwork_url: artworkUrl,
    progressive: options.progressive ? true : undefined,
    preview_only: options.previewOnly ? true : undefined,
    motion: options.motion ? true : undefined,
    occurrence_id: options.occurrenceId ?? undefined,
  });
}

export function encodeArtworkCancel(requestId: string): string {
  return JSON.stringify({
    version: 1,
    type: 'artwork.cancel',
    request_id: requestId,
  });
}

// The Host shows a Remote as connected only after the Remote reports a path, with the round trip it measured.
export function encodeSessionStatus(report: {
  reportedAtMs: number;
  transport: 'ble' | 'lan';
  rttMs: number;
}): string {
  return JSON.stringify({
    version: 1,
    type: 'session.status',
    status: {
      reported_at_ms: report.reportedAtMs,
      device: 'remote',
      paths: [
        {
          transport: report.transport,
          state: 'connected',
          rtt_ms: report.rttMs,
        },
      ],
    },
  });
}

export function encodeCommandStatus(commandId: string): string {
  return JSON.stringify({
    version: 1,
    type: 'command.status',
    command_id: commandId,
  });
}

export function encodeCreditAck(sequence: number): string {
  return JSON.stringify({ version: 1, type: 'analytics.ack', sequence });
}

export function encodeCommand(envelope: CommandEnvelope): string {
  return JSON.stringify({
    version: 1,
    type: 'command',
    command_id: envelope.commandId,
    host_epoch: envelope.hostEpoch,
    expires_at_host_ms: envelope.expiresAtHostMs,
    expected_revision: envelope.expectedRevision,
    action: encodeAction(envelope.action),
  });
}

function encodeAction(action: CommandAction) {
  switch (action.kind) {
    case 'playback.seek':
      return {
        kind: action.kind,
        occurrence_id: action.occurrenceId,
        position_ms: action.positionMs,
      };
    case 'playback.volume':
      return { kind: action.kind, percent: action.percent };
    case 'playback.pause':
    case 'playback.resume':
    case 'playback.skip':
    case 'playback.previous':
      return { kind: action.kind, occurrence_id: action.occurrenceId };
  }
}
