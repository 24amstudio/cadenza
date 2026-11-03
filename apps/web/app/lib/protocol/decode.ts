import {
  arrayField,
  booleanField,
  counterField,
  isJsonObject,
  objectField,
  parseJson,
  stringArrayField,
  stringField,
  type JsonObject,
  type JsonValue,
} from './json';
import type {
  ClockSample,
  CommandOutcome,
  CommandResult,
  CurrentPlayback,
  LyricDocument,
  LyricLine,
  LyricWord,
  QueueEntry,
  Snapshot,
  Song,
  Welcome,
} from './types';

// Messages the web client handles. Other protocol messages, such as session status, heartbeats, and update status,
// are intentionally ignored.
export type HostMessage =
  | { type: 'welcome'; requestId: string | null; welcome: Welcome }
  | { type: 'state'; snapshot: Snapshot }
  | { type: 'command.result'; result: CommandResult }
  | { type: 'remote.configured'; requestId: string | null }
  | {
      type: 'error';
      requestId: string | null;
      errorCode: string;
      message: string;
    }
  | { type: 'lyrics'; requestId: string | null; lyrics: LyricDocument }
  | { type: 'lyrics.unavailable'; occurrenceId: string | null; message: string }
  | {
      type: 'artwork';
      requestId: string;
      artworkUrl: string;
      dataBase64: string;
    }
  | { type: 'artwork.unavailable'; requestId: string; artworkUrl: string }
  | { type: 'clock'; requestId: string; sample: ClockSample }
  | { type: 'analytics.credit'; sequence: number };

export function decodeHostMessage(text: string): HostMessage | null {
  const value = parseJson(text);

  if (!isJsonObject(value)) return null;

  switch (stringField(value, 'type')) {
    case 'welcome':
      return decodeWelcomeMessage(value);
    case 'state':
      return decodeStateMessage(value);
    case 'command.result':
      return decodeResultMessage(value);
    case 'remote.configured':
      return {
        type: 'remote.configured',
        requestId: stringField(value, 'request_id'),
      };
    case 'error':
      return decodeErrorMessage(value);
    case 'lyrics':
      return decodeLyricsMessage(value);
    case 'lyrics.unavailable':
      return decodeLyricsUnavailableMessage(value);
    case 'artwork':
      return decodeArtworkMessage(value);
    case 'artwork.unavailable':
      return decodeArtworkUnavailableMessage(value);
    case 'clock':
      return decodeClockMessage(value);
    case 'analytics.credit':
      return decodeCreditMessage(value);
    default:
      return null;
  }
}

function decodeWelcomeMessage(object: JsonObject): HostMessage | null {
  const welcome = objectField(object, 'welcome');

  if (welcome === null) return null;
  const hostId = stringField(welcome, 'host_id');
  const hostName = stringField(welcome, 'host_name');
  const hostEpoch = stringField(welcome, 'host_epoch');
  const remoteId = stringField(welcome, 'remote_id');
  const hostTimeMs = counterField(welcome, 'host_time_ms');
  const capabilities = stringArrayField(welcome, 'capabilities');

  if (
    !hostId ||
    !hostName ||
    !hostEpoch ||
    !remoteId ||
    hostTimeMs === null ||
    capabilities === null
  ) {
    return null;
  }

  return {
    type: 'welcome',
    requestId: stringField(object, 'request_id'),
    welcome: {
      hostId,
      hostName,
      hostEpoch,
      remoteId,
      token: stringField(welcome, 'token'),
      hostTimeMs,
      capabilities,
    },
  };
}

function decodeStateMessage(object: JsonObject): HostMessage | null {
  const snapshot = objectField(object, 'snapshot');
  const decoded = snapshot === null ? null : decodeSnapshot(snapshot);

  return decoded === null ? null : { type: 'state', snapshot: decoded };
}

function decodeResultMessage(object: JsonObject): HostMessage | null {
  const result = decodeCommandResult(object);

  return result === null ? null : { type: 'command.result', result };
}

function decodeErrorMessage(object: JsonObject): HostMessage | null {
  const errorCode = stringField(object, 'error_code');

  if (errorCode === null) return null;

  return {
    type: 'error',
    requestId: stringField(object, 'request_id'),
    errorCode,
    message: stringField(object, 'message') ?? '',
  };
}

function decodeLyricsMessage(object: JsonObject): HostMessage | null {
  const lyrics = objectField(object, 'lyrics');
  const decoded = lyrics === null ? null : decodeLyricDocument(lyrics);

  if (decoded === null) return null;

  return {
    type: 'lyrics',
    requestId: stringField(object, 'request_id'),
    lyrics: decoded,
  };
}

function decodeLyricsUnavailableMessage(object: JsonObject): HostMessage {
  return {
    type: 'lyrics.unavailable',
    occurrenceId: stringField(object, 'occurrence_id'),
    message: stringField(object, 'message') ?? '',
  };
}

function decodeArtworkMessage(object: JsonObject): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const artworkUrl = stringField(object, 'artwork_url');
  const dataBase64 = stringField(object, 'artwork_data_base64');

  if (requestId === null || artworkUrl === null || dataBase64 === null)
    return null;

  return { type: 'artwork', requestId, artworkUrl, dataBase64 };
}

function decodeArtworkUnavailableMessage(
  object: JsonObject,
): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const artworkUrl = stringField(object, 'artwork_url');

  if (requestId === null || artworkUrl === null) return null;

  return { type: 'artwork.unavailable', requestId, artworkUrl };
}

function decodeClockMessage(object: JsonObject): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const clock = objectField(object, 'clock');

  if (requestId === null || clock === null) return null;
  const sentAtRemoteMs = counterField(clock, 'sent_at_remote_ms');
  const receivedAtHostMs = counterField(clock, 'received_at_host_ms');
  const sentAtHostMs = counterField(clock, 'sent_at_host_ms');

  if (
    sentAtRemoteMs === null ||
    receivedAtHostMs === null ||
    sentAtHostMs === null
  )
    return null;

  return {
    type: 'clock',
    requestId,
    sample: { sentAtRemoteMs, receivedAtHostMs, sentAtHostMs },
  };
}

function decodeCreditMessage(object: JsonObject): HostMessage | null {
  const sequence = counterField(object, 'sequence');

  return sequence === null ? null : { type: 'analytics.credit', sequence };
}

export function decodeSnapshot(object: JsonObject): Snapshot | null {
  const hostId = stringField(object, 'host_id');
  const hostEpoch = stringField(object, 'host_epoch');
  const revision = counterField(object, 'revision');
  const sequence = counterField(object, 'sequence');
  const playing = booleanField(object, 'playing');
  const volume = counterField(object, 'volume');
  const synchronized = booleanField(object, 'synchronized');
  const queue = decodeList(arrayField(object, 'queue'), decodeQueueEntry);

  if (
    !hostId ||
    !hostEpoch ||
    revision === null ||
    sequence === null ||
    playing === null ||
    volume === null ||
    volume > 100 ||
    synchronized === null ||
    queue === null
  ) {
    return null;
  }

  const currentObject = objectField(object, 'current');
  const current = currentObject === null ? null : decodeCurrent(currentObject);

  return {
    hostId,
    hostEpoch,
    revision,
    sequence,
    playing,
    volume,
    current,
    queue,
    synchronized,
    issue: stringField(object, 'issue'),
  };
}

function decodeCurrent(object: JsonObject): CurrentPlayback | null {
  const occurrenceId = stringField(object, 'occurrence_id');
  const requesterName = stringField(object, 'requester_name');
  const song = objectField(object, 'song');
  const positionMs = counterField(object, 'position_ms');
  const sampledAtHostMs = counterField(object, 'sampled_at_host_ms');
  const decodedSong = song === null ? null : decodeSong(song);

  if (
    !occurrenceId ||
    requesterName === null ||
    decodedSong === null ||
    positionMs === null ||
    sampledAtHostMs === null
  ) {
    return null;
  }

  return {
    occurrenceId,
    entryId: stringField(object, 'entry_id'),
    requesterName,
    song: decodedSong,
    positionMs,
    sampledAtHostMs,
  };
}

function decodeQueueEntry(object: JsonObject): QueueEntry | null {
  const id = stringField(object, 'id');
  const requesterName = stringField(object, 'requester_name');
  const song = objectField(object, 'song');
  const decodedSong = song === null ? null : decodeSong(song);

  if (!id || requesterName === null || decodedSong === null) return null;

  return {
    id,
    requesterName,
    song: decodedSong,
    estimatedWaitMs: counterField(object, 'estimated_wait_ms'),
  };
}

function decodeSong(object: JsonObject): Song | null {
  const source = stringField(object, 'source');
  const id = stringField(object, 'id');
  const title = stringField(object, 'title');
  const artist = stringField(object, 'artist');
  const album = stringField(object, 'album');

  if (
    !isSongSource(source) ||
    id === null ||
    title === null ||
    artist === null ||
    album === null
  )
    return null;

  return {
    source,
    id,
    title,
    artist,
    album,
    durationMs: counterField(object, 'duration_ms'),
    artworkUrl: stringField(object, 'artwork_url'),
  };
}

function isSongSource(value: string | null): value is Song['source'] {
  return value === 'catalog' || value === 'library' || value === 'unknown';
}

function decodeLyricDocument(object: JsonObject): LyricDocument | null {
  const occurrenceId = stringField(object, 'occurrence_id');
  const revision = stringField(object, 'revision');
  const translationSource = stringField(object, 'translation_source');
  const source = stringField(object, 'source');
  const lines = decodeList(arrayField(object, 'lines'), decodeLyricLine);

  if (
    !occurrenceId ||
    !revision ||
    !translationSource ||
    !source ||
    lines === null
  )
    return null;

  return {
    occurrenceId,
    revision,
    translationSource,
    source,
    lines,
    issue: stringField(object, 'issue'),
  };
}

function decodeLyricLine(object: JsonObject): LyricLine | null {
  const id = stringField(object, 'id');
  const text = stringField(object, 'text');
  const startMs = counterField(object, 'start_ms');
  const endMs = counterField(object, 'end_ms');
  const words = decodeList(arrayField(object, 'words'), decodeLyricWord);

  if (
    !id ||
    text === null ||
    startMs === null ||
    endMs === null ||
    words === null
  )
    return null;

  return {
    id,
    text,
    startMs,
    endMs,
    translation: stringField(object, 'translation'),
    words,
  };
}

function decodeLyricWord(object: JsonObject): LyricWord | null {
  const text = stringField(object, 'text');
  const startMs = counterField(object, 'start_ms');
  const endMs = counterField(object, 'end_ms');

  if (text === null || startMs === null || endMs === null) return null;

  return { text, startMs, endMs };
}

function decodeCommandResult(object: JsonObject): CommandResult | null {
  const commandId = stringField(object, 'command_id');
  const outcome = stringField(object, 'outcome');
  const revision = counterField(object, 'revision');

  if (!commandId || !isCommandOutcome(outcome) || revision === null)
    return null;

  return {
    commandId,
    outcome,
    revision,
    message: stringField(object, 'message'),
    errorCode: stringField(object, 'error_code'),
  };
}

function isCommandOutcome(value: string | null): value is CommandOutcome {
  return (
    value === 'applied' ||
    value === 'rejected' ||
    value === 'expired' ||
    value === 'unconfirmed'
  );
}

// Decodes every element or none. A single malformed element invalidates the whole list so a partial queue is never
// shown as if it were authoritative.
function decodeList<Item>(
  values: JsonValue[] | null,
  decode: (object: JsonObject) => Item | null,
): Item[] | null {
  if (values === null) return null;
  const items: Item[] = [];

  for (const value of values) {
    if (!isJsonObject(value)) return null;
    const item = decode(value);

    if (item === null) return null;
    items.push(item);
  }

  return items;
}
