import {
  arrayField,
  booleanField,
  counterField,
  isJsonObject,
  isOffsetMilliseconds,
  objectField,
  parseJson,
  stringArrayField,
  stringField,
  type JsonObject,
  type JsonValue,
} from './json';
import type {
  AudioOutput,
  AudioQuality,
  AutoPlayItem,
  VideoOutputTarget,
  CastDevice,
  CastDisplay,
  CastPresentation,
  CastState,
  CastTransmitState,
  HostUpdateStatus,
  BrowseCollectionKind,
  BrowseItem,
  BrowseKind,
  BrowsePage,
  BrowseSection,
  ClockSample,
  CommandOutcome,
  CommandResult,
  CurrentPlayback,
  LyricDocument,
  RecommendationShelfItem,
  LyricLine,
  LyricWord,
  QueueEntry,
  RepeatMode,
  Snapshot,
  Song,
  SongSuggestions,
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
      commandId: string | null;
      errorCode: string;
      message: string;
    }
  | { type: 'lyrics'; requestId: string | null; lyrics: LyricDocument }
  | {
      type: 'recommendation.shelf';
      requestId: string | null;
      items: RecommendationShelfItem[];
    }
  | { type: 'lyrics.unavailable'; occurrenceId: string | null; message: string }
  | {
      type: 'artwork';
      requestId: string;
      artworkUrl: string;
      dataBase64: string;
      variant: 'preview' | 'full';
    }
  | {
      type: 'artwork.chunk';
      requestId: string;
      artworkUrl: string;
      index: number;
      count: number;
      totalBytes: number;
      sha256: string;
      dataBase64: string;
    }
  | { type: 'artwork.unavailable'; requestId: string; artworkUrl: string }
  | {
      type: 'motion.chunk';
      requestId: string;
      occurrenceId: string;
      index: number;
      count: number;
      totalBytes: number;
      sha256: string;
      dataBase64: string;
    }
  | { type: 'motion.unavailable'; requestId: string; occurrenceId: string }
  | {
      type: 'artist.motion.chunk';
      requestId: string;
      index: number;
      count: number;
      totalBytes: number;
      sha256: string;
      dataBase64: string;
    }
  | { type: 'artist.motion.unavailable'; requestId: string }
  | { type: 'clock'; requestId: string; sample: ClockSample }
  | { type: 'analytics.credit'; sequence: number }
  | { type: 'search.result'; requestId: string; songs: Song[] }
  | {
      type: 'search.suggestions';
      requestId: string;
      suggestions: SongSuggestions;
    }
  | { type: 'song.ready'; requestId: string }
  | { type: 'video.started'; requestId: string }
  | { type: 'browse.result'; requestId: string; browse: BrowsePage }
  | {
      type: 'host.update.status';
      requestId: string | null;
      status: HostUpdateStatus;
    };

// Each frame type has one decoder. A type without a decoder is ignored, as it always was.
const hostDecoders = new Map<
  string,
  (object: JsonObject) => HostMessage | null
>([
  ['welcome', decodeWelcomeMessage],
  ['state', decodeStateMessage],
  ['command.result', decodeResultMessage],
  [
    'remote.configured',
    (object) => ({
      type: 'remote.configured',
      requestId: stringField(object, 'request_id'),
    }),
  ],
  ['error', decodeErrorMessage],
  ['lyrics', decodeLyricsMessage],
  ['lyrics.unavailable', decodeLyricsUnavailableMessage],
  ['artwork', decodeArtworkMessage],
  ['artwork.chunk', decodeArtworkChunkMessage],
  ['artwork.unavailable', decodeArtworkUnavailableMessage],
  ['motion.chunk', decodeMotionChunkMessage],
  ['motion.unavailable', decodeMotionUnavailableMessage],
  ['artist.motion.chunk', decodeArtistMotionChunkMessage],
  ['artist.motion.unavailable', decodeArtistMotionUnavailableMessage],
  ['clock', decodeClockMessage],
  ['analytics.credit', decodeCreditMessage],
  ['search.result', decodeSearchResultMessage],
  ['search.suggestions', decodeSearchSuggestionsMessage],
  ['song.ready', decodeSongReadyMessage],
  ['video.started', decodeVideoStartedMessage],
  ['browse.result', decodeBrowseResultMessage],
  ['host.update.status', decodeHostUpdateMessage],
  ['recommendation.result', decodeRecommendationResultMessage],
]);

function decodeRecommendationResultMessage(
  object: JsonObject,
): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const shelf = objectField(object, 'recommendation_shelf');
  const errorCode = stringField(object, 'error_code');

  if (shelf === null) {
    if (errorCode === null) return null;

    return {
      type: 'error',
      requestId,
      commandId: null,
      errorCode,
      message: 'Recommendations are not available right now.',
    };
  }

  return {
    type: 'recommendation.shelf',
    requestId,
    items: decodeShelfItems(arrayField(shelf, 'items') ?? []),
  };
}

function decodeShelfItems(values: JsonValue[]): RecommendationShelfItem[] {
  return values.flatMap((value) => {
    if (!isJsonObject(value)) return [];

    const track = objectField(value, 'track');
    const source = track === null ? null : stringField(track, 'source');
    const id = track === null ? null : stringField(track, 'id');
    const title = stringField(value, 'title');
    const artist = stringField(value, 'artist');

    if (
      !isShelfSource(source) ||
      id === null ||
      title === null ||
      artist === null
    ) {
      return [];
    }

    return [
      {
        source,
        id,
        title,
        artist,
        evidence: stringArrayField(value, 'evidence') ?? [],
      },
    ];
  });
}

function isShelfSource(value: string | null): value is 'catalog' | 'library' {
  return value === 'catalog' || value === 'library';
}

export function decodeHostMessage(text: string): HostMessage | null {
  const value = parseJson(text);

  if (!isJsonObject(value)) return null;

  const type = stringField(value, 'type');
  const decode = type === null ? undefined : hostDecoders.get(type);

  return decode?.(value) ?? null;
}

function decodeWelcomeMessage(object: JsonObject): HostMessage | null {
  const welcome = objectField(object, 'welcome');

  if (welcome === null) return null;
  const hostId = stringField(welcome, 'host_id');
  const hostName = stringField(welcome, 'host_name');
  const hostEpoch = stringField(welcome, 'host_epoch');
  const remoteId = stringField(welcome, 'remote_id');
  const hostTimeMs = counterField(welcome, 'host_time_ms');
  const hostVersion = stringField(welcome, 'host_version');
  const hostBuild = counterField(welcome, 'host_build');
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
      hostVersion,
      hostBuild,
    },
  };
}

function decodeHostUpdateMessage(object: JsonObject): HostMessage | null {
  const state = stringField(object, 'update_state');

  if (state === null) return null;

  return {
    type: 'host.update.status',
    requestId: stringField(object, 'request_id'),
    status: {
      state,
      version: stringField(object, 'update_version'),
      message: stringField(object, 'message'),
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
    commandId: stringField(object, 'command_id'),
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

  // A frame without a variant is the whole image, which is what older Hosts send.
  const variant =
    stringField(object, 'variant') === 'preview' ? 'preview' : 'full';

  return { type: 'artwork', requestId, artworkUrl, dataBase64, variant };
}

function decodeArtworkChunkMessage(object: JsonObject): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const artworkUrl = stringField(object, 'artwork_url');
  const index = counterField(object, 'chunk_index');
  const count = counterField(object, 'chunk_count');
  const totalBytes = counterField(object, 'total_bytes');
  const sha256 = stringField(object, 'sha256');
  const dataBase64 = stringField(object, 'data_base64');

  if (
    requestId === null ||
    artworkUrl === null ||
    index === null ||
    count === null ||
    totalBytes === null ||
    sha256 === null ||
    dataBase64 === null
  )
    return null;

  return {
    type: 'artwork.chunk',
    requestId,
    artworkUrl,
    index,
    count,
    totalBytes,
    sha256,
    dataBase64,
  };
}

function decodeArtworkUnavailableMessage(
  object: JsonObject,
): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const artworkUrl = stringField(object, 'artwork_url');

  if (requestId === null || artworkUrl === null) return null;

  return { type: 'artwork.unavailable', requestId, artworkUrl };
}

function decodeMotionUnavailableMessage(
  object: JsonObject,
): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const occurrenceId = stringField(object, 'occurrence_id');

  if (requestId === null || occurrenceId === null) return null;

  return { type: 'motion.unavailable', requestId, occurrenceId };
}

function decodeMotionChunkMessage(object: JsonObject): HostMessage | null {
  const occurrenceId = stringField(object, 'occurrence_id');
  const chunk = decodeChunkFields(object);

  if (occurrenceId === null || chunk === null) return null;

  return { type: 'motion.chunk', occurrenceId, ...chunk };
}

function decodeArtistMotionChunkMessage(
  object: JsonObject,
): HostMessage | null {
  const chunk = decodeChunkFields(object);

  if (chunk === null) return null;

  return { type: 'artist.motion.chunk', ...chunk };
}

function decodeArtistMotionUnavailableMessage(
  object: JsonObject,
): HostMessage | null {
  const requestId = stringField(object, 'request_id');

  if (requestId === null) return null;

  return { type: 'artist.motion.unavailable', requestId };
}

// The fields every motion video chunk carries, whether it belongs to the playing song or to an artist.
function decodeChunkFields(object: JsonObject) {
  const requestId = stringField(object, 'request_id');
  const index = counterField(object, 'chunk_index');
  const count = counterField(object, 'chunk_count');
  const totalBytes = counterField(object, 'total_bytes');
  const sha256 = stringField(object, 'sha256');
  const dataBase64 = stringField(object, 'data_base64');

  if (
    requestId === null ||
    index === null ||
    count === null ||
    totalBytes === null ||
    sha256 === null ||
    dataBase64 === null
  )
    return null;

  return { requestId, index, count, totalBytes, sha256, dataBase64 };
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

function decodeSearchResultMessage(object: JsonObject): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const songs = decodeList(arrayField(object, 'songs'), decodeSong);

  return requestId === null || songs === null
    ? null
    : { type: 'search.result', requestId, songs };
}

function decodeSearchSuggestionsMessage(
  object: JsonObject,
): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const terms = stringArrayField(object, 'terms');
  const songs = decodeList(arrayField(object, 'songs'), decodeSong);

  if (requestId === null || terms === null || songs === null) return null;

  return {
    type: 'search.suggestions',
    requestId,
    suggestions: { terms, songs },
  };
}

function decodeSongReadyMessage(object: JsonObject): HostMessage | null {
  const requestId = stringField(object, 'request_id');

  return requestId === null ? null : { type: 'song.ready', requestId };
}

function decodeVideoStartedMessage(object: JsonObject): HostMessage | null {
  const requestId = stringField(object, 'request_id');

  return requestId === null ? null : { type: 'video.started', requestId };
}

function decodeBrowseResultMessage(object: JsonObject): HostMessage | null {
  const requestId = stringField(object, 'request_id');
  const page = objectField(object, 'browse');
  const browse = page === null ? null : decodeBrowsePage(page);

  return requestId === null || browse === null
    ? null
    : { type: 'browse.result', requestId, browse };
}

function decodeBrowsePage(object: JsonObject): BrowsePage | null {
  const kind = stringField(object, 'kind');
  const id = stringField(object, 'id');
  const title = stringField(object, 'title');
  const sections = decodeList(arrayField(object, 'sections'), decodeSection);

  if (!isBrowseKind(kind) || id === null || title === null || sections === null)
    return null;

  return {
    kind,
    id,
    title,
    subtitle: stringField(object, 'subtitle'),
    artworkUrl: stringField(object, 'artwork_url'),
    detail: stringField(object, 'detail'),
    sections,
  };
}

function decodeSection(object: JsonObject): BrowseSection | null {
  const id = stringField(object, 'id');
  const title = stringField(object, 'title');
  const items = decodeList(arrayField(object, 'items'), decodeBrowseItem);

  return id === null || title === null || items === null
    ? null
    : { id, title, items };
}

function decodeBrowseItem(object: JsonObject): BrowseItem | null {
  const type = stringField(object, 'type');

  if (type === 'song') {
    const song = objectField(object, 'song');
    const decoded = song === null ? null : decodeSong(song);

    return decoded === null ? null : { type, song: decoded };
  }

  const id = stringField(object, 'id');
  const title = stringField(object, 'title');

  if (!isCollectionKind(type) || !id || title === null) return null;

  return {
    type,
    id,
    title,
    subtitle: stringField(object, 'subtitle'),
    artworkUrl: stringField(object, 'artwork_url'),
  };
}

function isBrowseKind(value: string | null): value is BrowseKind {
  return (
    value === 'album' ||
    value === 'artist' ||
    value === 'playlists' ||
    value === 'playlist'
  );
}

function isCollectionKind(value: string | null): value is BrowseCollectionKind {
  return value === 'album' || value === 'artist' || value === 'playlist';
}

export function decodeSnapshot(object: JsonObject): Snapshot | null {
  const hostId = stringField(object, 'host_id');
  const hostEpoch = stringField(object, 'host_epoch');
  const revision = counterField(object, 'revision');
  const sequence = counterField(object, 'sequence');
  const playing = booleanField(object, 'playing');
  const volume = counterField(object, 'volume');
  const synchronized = booleanField(object, 'synchronized');
  const shuffle = booleanField(object, 'shuffle');
  const repeat = stringField(object, 'repeat');
  const queue = decodeList(arrayField(object, 'queue'), decodeQueueEntry);

  // Hosts before this field existed reported no tier, which is the same as an unread one.
  const quality = stringField(object, 'quality') ?? 'unknown';

  const autoPlay = decodeList(
    arrayField(object, 'auto_play') ?? [],
    decodeAutoPlayItem,
  );

  if (
    !hostId ||
    !hostEpoch ||
    revision === null ||
    sequence === null ||
    playing === null ||
    volume === null ||
    volume > 100 ||
    synchronized === null ||
    shuffle === null ||
    !isRepeatMode(repeat) ||
    !isAudioQuality(quality) ||
    queue === null ||
    autoPlay === null
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
    shuffle,
    repeat,
    current,
    queue,
    totalRemainingMs: counterField(object, 'total_remaining_ms'),
    quality,
    autoPlay,
    synchronized,
    issue: stringField(object, 'issue'),
    audioOutputs: decodeAudioOutputs(arrayField(object, 'audio_outputs') ?? []),
    hostBudget: stringField(object, 'host_budget'),
    cast: decodeCast(objectField(object, 'cast')),
    videoOutput: decodeVideoOutput(stringField(object, 'video_output')),
    lipSyncOffsetMs: lipSyncOffsetField(object),
  };
}

// The AVR offset can be negative, so it has its own range check: whole milliseconds from -500 to 500.
// The saved karaoke nudge for the track, in milliseconds, from -5 to 5 seconds.
function userOffsetField(object: JsonObject): number | null {
  const value = object['user_offset_ms'];

  return isOffsetMilliseconds(value, 5000) ? value : null;
}

function lipSyncOffsetField(object: JsonObject): number | null {
  const value = object['lip_sync_offset_ms'];

  return isOffsetMilliseconds(value, 500) ? value : null;
}

function decodeVideoOutput(value: string | null): VideoOutputTarget | null {
  return value === 'host_display' || value === 'cast_transmitter'
    ? value
    : null;
}

// An output that does not decode is left out, so one unknown output never hides the rest.
function decodeCast(object: JsonObject | null): CastState | null {
  if (object === null) return null;

  const presentation = stringField(object, 'presentation');

  if (!isCastPresentation(presentation)) return null;

  return {
    presentation,
    devices: decodeCastDevices(arrayField(object, 'devices') ?? []),
    transmit: decodeCastTransmit(objectField(object, 'transmit')),
  };
}

function decodeCastTransmit(
  object: JsonObject | null,
): CastTransmitState | null {
  if (object === null) return null;

  const state = stringField(object, 'state');

  if (!isCastTransmitState(state)) return null;

  return {
    state,
    device: stringField(object, 'device'),
    reason: stringField(object, 'reason'),
  };
}

function isCastTransmitState(
  value: string | null,
): value is CastTransmitState['state'] {
  return (
    value === 'idle' ||
    value === 'starting' ||
    value === 'transmitting' ||
    value === 'failed'
  );
}

function isCastPresentation(value: string | null): value is CastPresentation {
  return value === 'auto' || value === 'audio_only' || value === 'full_suite';
}

function decodeCastDevices(values: JsonValue[]): CastDevice[] {
  return values.flatMap((value) => {
    if (!isJsonObject(value)) return [];

    const name = stringField(value, 'name');
    const display = stringField(value, 'display');

    if (name === null || !isCastDisplay(display)) return [];

    return [{ name, display }];
  });
}

function isCastDisplay(value: string | null): value is CastDisplay {
  return value === 'none' || value === 'display' || value === 'unknown';
}

function decodeAudioOutputs(values: JsonValue[]): AudioOutput[] {
  return values.flatMap((value) => {
    if (!isJsonObject(value)) return [];

    const output = decodeAudioOutput(value);

    return output === null ? [] : [output];
  });
}

function decodeAudioOutput(object: JsonObject): AudioOutput | null {
  const id = stringField(object, 'id');
  const name = stringField(object, 'name');
  const transport = stringField(object, 'transport');
  const isDefault = booleanField(object, 'is_default');

  if (!id || !name || !transport || isDefault === null) return null;

  return { id, name, transport, isDefault };
}

function isRepeatMode(value: string | null): value is RepeatMode {
  return value === 'off' || value === 'one' || value === 'all';
}

function isAudioQuality(value: string): value is AudioQuality {
  return (
    value === 'unknown' ||
    value === 'lossless' ||
    value === 'hi_res_lossless' ||
    value === 'dolby_atmos' ||
    value === 'aac'
  );
}

function decodeAutoPlayItem(object: JsonObject): AutoPlayItem | null {
  const title = stringField(object, 'title');
  const artist = stringField(object, 'artist');

  return title === null || artist === null ? null : { title, artist };
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
    artworkPreview: stringField(object, 'artwork_preview'),
    isLiveRadio: booleanField(object, 'is_live_radio') ?? false,
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
    mediaType: decodeMediaType(object),
  };
}

function decodeMediaType(object: JsonObject): Song['mediaType'] {
  const value = stringField(object, 'media_type');

  return value === 'song' || value === 'musicVideo' ? value : undefined;
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
    userOffsetMs: userOffsetField(object),
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
    // Anything but an explicit end is the first voice.
    align: stringField(object, 'align') === 'end' ? 'end' : 'start',
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
