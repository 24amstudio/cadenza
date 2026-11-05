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

// A progressive request asks for a small preview first, then the full image in chunks.
export function encodeArtworkGet(
  requestId: string,
  artworkUrl: string,
  progressive = false,
): string {
  // JSON.stringify drops the undefined key, so the Host sees progressive only when it was requested.
  return JSON.stringify({
    version: 1,
    type: 'artwork.get',
    request_id: requestId,
    artwork_url: artworkUrl,
    progressive: progressive ? true : undefined,
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
