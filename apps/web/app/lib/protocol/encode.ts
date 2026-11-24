import type {
  BrowseRequest,
  CommandAction,
  SearchScope,
  SongIdentity,
} from './types';

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

// The Host keeps these with the Remote's identity. It accepts up to 100 entries per report.
export function encodeLogReport(
  entries: readonly { level: string; action: string; message: string }[],
): string {
  return JSON.stringify({
    version: 1,
    type: 'log.report',
    log_entries: entries.map(({ level, action, message }) => ({
      level,
      action,
      message,
    })),
  });
}

// Asks the Host to check for an update, or to install one it has found. The Host answers with host.update.status.
export function encodeHostUpdate(
  requestId: string,
  action: 'check' | 'install',
): string {
  return JSON.stringify({
    version: 1,
    type: 'host.update',
    request_id: requestId,
    update_action: action,
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
  });
}

// The song's motion video, sent as motion chunks under this request. A song without one is answered with motion.unavailable.
export function encodeMotionGet(
  requestId: string,
  occurrenceId: string,
): string {
  return JSON.stringify({
    version: 1,
    type: 'motion.get',
    request_id: requestId,
    occurrence_id: occurrenceId,
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

/** Asks the Host for the ranked shelf. Nothing is queued by it, and the reply echoes the request id. */
export function encodeRecommendationShelf(requestId: string): string {
  return JSON.stringify({
    version: 1,
    type: 'recommendation.query',
    request_id: requestId,
    recommendation_query: {
      intent: null,
      horizon: 1,
      filters: { explicit_allowed: false, locked: false },
      model_version: 1,
      shelf: true,
    },
  });
}

export function encodeCreditAck(sequence: number): string {
  return JSON.stringify({ version: 1, type: 'analytics.ack', sequence });
}

// The answer is search.result with this request ID, or an error carrying it.
export function encodeSearch(
  requestId: string,
  query: string,
  scope: SearchScope,
): string {
  return JSON.stringify({
    version: 1,
    type: 'search',
    request_id: requestId,
    query,
    scope,
  });
}

// Apple Music completions for text being typed. The answer is search.suggestions with this request ID.
export function encodeSearchSuggest(requestId: string, query: string): string {
  return JSON.stringify({
    version: 1,
    type: 'search.suggest',
    request_id: requestId,
    query,
  });
}

// Preparation makes the Host know a song well enough to queue it. The answer is song.ready or an error.
// What the Host needs to find a library song whose ID no longer resolves. The Host reads it only for the song in `song`.
export interface SongDetails {
  title: string;
  artist: string;
  album: string;
  durationMs: number | null;
}

export function encodeSongPrepare(
  requestId: string,
  song: SongIdentity,
  details?: SongDetails,
): string {
  return JSON.stringify({
    version: 1,
    type: 'song.prepare',
    request_id: requestId,
    song: encodeIdentity(song),
    song_metadata:
      details === undefined ? undefined : encodeMetadata(song, details),
  });
}

// The answer is browse.result with this request ID, or an error carrying it.
export function encodeBrowseGet(
  requestId: string,
  request: BrowseRequest,
): string {
  return JSON.stringify({
    version: 1,
    type: 'browse.get',
    request_id: requestId,
    browse: {
      kind: request.kind,
      id: request.id,
      song:
        request.song === undefined ? undefined : encodeIdentity(request.song),
    },
  });
}

export function encodeOperationCancel(requestId: string): string {
  return JSON.stringify({
    version: 1,
    type: 'operation.cancel',
    request_id: requestId,
  });
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
    case 'playback.shuffle':
      return { kind: action.kind, enabled: action.enabled };
    case 'playback.repeat':
      return { kind: action.kind, mode: action.mode };
    case 'audio.selectOutput':
      return { kind: action.kind, output: action.output };
    case 'library.favorite':
      return {
        kind: action.kind,
        song: encodeIdentity(action.song),
        enabled: action.favorite,
      };
    case 'library.addToPlaylist':
      return {
        kind: action.kind,
        name: action.name,
        songs: action.songs.map(encodeIdentity),
      };
    case 'playback.pause':
    case 'playback.resume':
    case 'playback.skip':
    case 'playback.previous':
      return { kind: action.kind, occurrence_id: action.occurrenceId };
    case 'queue.enqueue':
    case 'queue.play_next':
      return { kind: action.kind, song: encodeIdentity(action.song) };
    case 'queue.play_now':
      return {
        kind: action.kind,
        song: encodeIdentity(action.song),
        occurrence_id: action.occurrenceId,
      };
  }
}

// Commands and searches take exactly the source and ID. Only song.prepare adds metadata, through encodeMetadata.
function encodeIdentity(song: SongIdentity) {
  return { source: song.source, id: song.id };
}

function encodeMetadata(song: SongIdentity, details: SongDetails) {
  return {
    source: song.source,
    id: song.id,
    title: details.title,
    artist: details.artist,
    album: details.album,
    duration_ms: details.durationMs,
  };
}
