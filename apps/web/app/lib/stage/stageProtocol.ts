import {
  arrayField,
  booleanField,
  counterField,
  isJsonObject,
  isOffsetMilliseconds,
  lyricAlignField,
  type JsonObject,
  numberField,
  parseJson,
  stringField,
} from '../protocol/json';

// The zero-account stage contract, as a Tier-2 browser reads it. `shared/protocol/README.md` defines the frames, and
// `shared/protocol/examples/cast-stage-frames.json` holds the bytes that every receiver must accept.

export const STAGE_AUDIO_FRAME = 0x01;
export const STAGE_FLUSH_FRAME = 0x02;
export const STAGE_INIT_FRAME = 0x03;

export const STAGE_MAX_PAYLOAD_BYTES = 65_536;

export type StageCodec = 1 | 2 | 3 | 4;

export type StageFrame =
  | {
      type: 'AUDIO_FRAME';
      codec: StageCodec;
      channels: number;
      sampleRate: number;
      presentationTimeUs: bigint;
      payload: Uint8Array;
    }
  | {
      type: 'INIT_SEGMENT';
      codec: StageCodec;
      channels: number;
      sampleRate: number;
      payload: Uint8Array;
    }
  | { type: 'FLUSH_STREAM'; generationSeq: number };

const SAMPLE_RATES = new Map<number, number>([
  [1, 48_000],
  [2, 44_100],
]);

const CODECS = new Set<number>([1, 2, 3, 4]);

export class StageFrameError extends Error {}

function checkAudioHeader(
  codec: number,
  channels: number,
  rateCode: number,
): void {
  if (!CODECS.has(codec)) throw new StageFrameError('unknown codec');

  if (channels < 1 || channels > 8)
    throw new StageFrameError('channel count out of range');

  if (!SAMPLE_RATES.has(rateCode))
    throw new StageFrameError('unknown sample rate code');
}

/** Decodes one binary frame. Any frame that breaks the contract throws, and the caller drops it. */
export function decodeStageFrame(bytes: Uint8Array): StageFrame {
  if (bytes.byteLength === 0) throw new StageFrameError('empty frame');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const type = view.getUint8(0);

  if (type === STAGE_FLUSH_FRAME) {
    if (bytes.byteLength !== 5)
      throw new StageFrameError('flush frame must be 5 bytes');

    return { type: 'FLUSH_STREAM', generationSeq: view.getUint32(1) };
  }

  if (type === STAGE_INIT_FRAME) {
    if (bytes.byteLength < 8)
      throw new StageFrameError('init segment header is truncated');
    const codec = view.getUint8(1);
    const channels = view.getUint8(2);
    const rateCode = view.getUint8(3);
    const length = view.getUint32(4);
    checkAudioHeader(codec, channels, rateCode);

    if (length > STAGE_MAX_PAYLOAD_BYTES)
      throw new StageFrameError('payload exceeds the frame limit');

    if (bytes.byteLength - 8 !== length)
      throw new StageFrameError('payload length does not match the frame');

    return {
      type: 'INIT_SEGMENT',
      // SAFETY: checkAudioHeader accepted this codec, so it is one of the four contract values.
      // SAFETY: checkAudioHeader accepted this codec, so it is one of the four contract values.
      // SAFETY: checkAudioHeader accepted this codec, so it is one of the four contract values.
      // SAFETY: checkAudioHeader accepted this codec, so it is one of the four contract values.
      codec: codec as StageCodec,
      channels,
      sampleRate: SAMPLE_RATES.get(rateCode) ?? 0,
      payload: bytes.subarray(8),
    };
  }

  if (type !== STAGE_AUDIO_FRAME)
    throw new StageFrameError('unknown frame type');

  if (bytes.byteLength < 16)
    throw new StageFrameError('audio frame header is truncated');
  const codec = view.getUint8(1);
  const channels = view.getUint8(2);
  const rateCode = view.getUint8(3);
  const length = view.getUint32(12);
  checkAudioHeader(codec, channels, rateCode);

  if (length > STAGE_MAX_PAYLOAD_BYTES)
    throw new StageFrameError('payload exceeds the frame limit');

  if (bytes.byteLength - 16 !== length)
    throw new StageFrameError('payload length does not match the frame');

  return {
    type: 'AUDIO_FRAME',
    // SAFETY: checkAudioHeader accepted this codec, so it is one of the four contract values.
    codec: codec as StageCodec,
    channels,
    sampleRate: SAMPLE_RATES.get(rateCode) ?? 0,
    presentationTimeUs: view.getBigUint64(4),
    payload: bytes.subarray(16),
  };
}

export interface StageTrackLine {
  id: string;
  text: string;
  startMs: number;
  endMs: number;
  words: { text: string; startMs: number; endMs: number }[];
  translation: string | null;
  align: 'start' | 'center' | 'end';
}

export interface StageTrackSuite {
  trackId: string;
  title: string;
  artist: string;
  album: string;
  durationMs: number;
  quality: string | null;
  artworkUrl: string | null;
  motionUrl: string | null;
  lines: StageTrackLine[];
}

export interface StageVideoPayload {
  mediaUrl: string;
  subtitleUrl: string;
  userOffsetMs: number;
}

export type StageServerMessage =
  | { type: 'STAGE_PAIRING'; pin: string; expiresInMs: number }
  | { type: 'STAGE_ACCEPTED'; receiverToken: string }
  | { type: 'TRACK_SUITE_PAYLOAD'; suite: StageTrackSuite }
  | { type: 'PREFETCH_NEXT_SUITE'; trackId: string }
  | {
      type: 'OPTIMISTIC_STATE';
      isPlaying: boolean;
      targetPositionMs: number;
      playbackRate: number;
      hostMonoTimeMs: number;
      audioLatencyMs: number;
    }
  | {
      type: 'CLOCK_CALIBRATE';
      actualPositionMs: number;
      audioLatencyMs: number;
      hostMonoTimeMs: number;
    }
  | ({ type: 'VIDEO_KARAOKE_PAYLOAD' } & StageVideoPayload);

type MessageParser = (object: JsonObject) => StageServerMessage | null;

function parseLine(object: JsonObject): StageTrackLine | null {
  const id = stringField(object, 'id');
  const body = stringField(object, 'text');
  const startMs = counterField(object, 'start_ms');
  const endMs = counterField(object, 'end_ms');
  const wordValues = arrayField(object, 'words');

  if (
    id === null ||
    body === null ||
    startMs === null ||
    endMs === null ||
    wordValues === null
  )
    return null;

  if (id.length > 256 || body.length > 20_000) return null;

  const words = wordValues.flatMap((value) => {
    if (!isJsonObject(value)) return [];
    const word = parseWord(value);

    return word === null ? [] : [word];
  });

  if (words.length !== wordValues.length) return null;

  return {
    id,
    text: body,
    startMs,
    endMs,
    words,
    translation: stringField(object, 'translation'),
    align: lyricAlignField(object),
  };
}

function parseWord(object: JsonObject): StageTrackLine['words'][number] | null {
  const text = stringField(object, 'text');
  const startMs = counterField(object, 'start_ms');
  const endMs = counterField(object, 'end_ms');

  return text !== null && startMs !== null && endMs !== null
    ? { text, startMs, endMs }
    : null;
}

function parseSuite(object: JsonObject): StageTrackSuite | null {
  const trackId = stringField(object, 'trackId');
  const title = stringField(object, 'title');
  const artist = stringField(object, 'artist');
  const album = stringField(object, 'album');
  const durationMs = counterField(object, 'durationMs');
  const lineValues = arrayField(object, 'lines');

  if (
    trackId === null ||
    title === null ||
    artist === null ||
    album === null ||
    durationMs === null
  )
    return null;

  if (lineValues === null || lineValues.length > 2_000) return null;

  const lines = lineValues.flatMap((value) => {
    if (!isJsonObject(value)) return [];
    const line = parseLine(value);

    return line === null ? [] : [line];
  });

  if (lines.length !== lineValues.length) return null;

  return {
    trackId,
    title,
    artist,
    album,
    durationMs,
    quality: stringField(object, 'quality'),
    artworkUrl: lanUrl(stringField(object, 'artworkUrl')),
    motionUrl: lanUrl(stringField(object, 'motionUrl')),
    lines,
  };
}

function lanUrl(value: string | null): string | null {
  return value !== null &&
    value.length <= 2_048 &&
    /^http:\/\/[^/\s]+\//.test(value)
    ? value
    : null;
}

const MESSAGES = new Map<
  string,
  { fields: readonly string[]; parse: MessageParser }
>([
  [
    'STAGE_PAIRING',
    {
      fields: ['version', 'type', 'pin', 'expiresInMs'],
      parse: (object) => {
        const pin = stringField(object, 'pin');
        const expiresInMs = counterField(object, 'expiresInMs');

        return pin !== null && /^[0-9]{4}$/.test(pin) && expiresInMs !== null
          ? { type: 'STAGE_PAIRING', pin, expiresInMs }
          : null;
      },
    },
  ],
  [
    'STAGE_ACCEPTED',
    {
      fields: ['version', 'type', 'receiverToken'],
      parse: (object) => {
        const token = stringField(object, 'receiverToken');

        return token !== null && token.length >= 32 && token.length <= 128
          ? { type: 'STAGE_ACCEPTED', receiverToken: token }
          : null;
      },
    },
  ],
  [
    'TRACK_SUITE_PAYLOAD',
    {
      fields: [
        'version',
        'type',
        'trackId',
        'title',
        'artist',
        'album',
        'durationMs',
        'quality',
        'artworkUrl',
        'motionUrl',
        'lines',
      ],
      parse: (object) => {
        const suite = parseSuite(object);

        return suite === null ? null : { type: 'TRACK_SUITE_PAYLOAD', suite };
      },
    },
  ],
  [
    'PREFETCH_NEXT_SUITE',
    {
      fields: ['version', 'type', 'trackId', 'reason'],
      parse: (object) => {
        const trackId = stringField(object, 'trackId');

        return trackId === null
          ? null
          : { type: 'PREFETCH_NEXT_SUITE', trackId };
      },
    },
  ],
  [
    'OPTIMISTIC_STATE',
    {
      fields: [
        'version',
        'type',
        'isPlaying',
        'targetPositionMs',
        'playbackRate',
        'hostMonoTimeMs',
        'audioLatencyMs',
      ],
      parse: (object) => {
        const isPlaying = booleanField(object, 'isPlaying');
        const target = counterField(object, 'targetPositionMs');
        const rate = numberField(object, 'playbackRate');
        const hostMonoTimeMs = counterField(object, 'hostMonoTimeMs');
        const audioLatencyMs = counterField(object, 'audioLatencyMs');

        if (
          isPlaying === null ||
          target === null ||
          rate === null ||
          hostMonoTimeMs === null
        )
          return null;

        if (audioLatencyMs === null || rate <= 0 || rate > 4) return null;

        return {
          type: 'OPTIMISTIC_STATE',
          isPlaying,
          targetPositionMs: target,
          playbackRate: rate,
          hostMonoTimeMs,
          audioLatencyMs,
        };
      },
    },
  ],
  [
    'CLOCK_CALIBRATE',
    {
      fields: [
        'version',
        'type',
        'actualPositionMs',
        'audioLatencyMs',
        'hostMonoTimeMs',
      ],
      parse: (object) => {
        const actual = counterField(object, 'actualPositionMs');
        const audioLatencyMs = counterField(object, 'audioLatencyMs');
        const hostMonoTimeMs = counterField(object, 'hostMonoTimeMs');

        return actual !== null &&
          audioLatencyMs !== null &&
          hostMonoTimeMs !== null
          ? {
              type: 'CLOCK_CALIBRATE',
              actualPositionMs: actual,
              audioLatencyMs,
              hostMonoTimeMs,
            }
          : null;
      },
    },
  ],
  [
    'VIDEO_KARAOKE_PAYLOAD',
    {
      fields: [
        'version',
        'type',
        'source',
        'mediaUrl',
        'subtitleUrl',
        'userOffsetMs',
      ],
      parse: (object) => {
        const mediaUrl = lanUrl(stringField(object, 'mediaUrl'));
        const subtitleUrl = lanUrl(stringField(object, 'subtitleUrl'));
        const userOffsetMs = object['userOffsetMs'];

        if (
          stringField(object, 'source') !== 'lan_mp4' ||
          mediaUrl === null ||
          subtitleUrl === null
        )
          return null;

        return isOffsetMilliseconds(userOffsetMs, 5_000)
          ? {
              type: 'VIDEO_KARAOKE_PAYLOAD',
              mediaUrl,
              subtitleUrl,
              userOffsetMs,
            }
          : null;
      },
    },
  ],
]);

/** Parses one JSON text frame from the Host. Anything unknown or out of range returns null, and no state changes. */
export function parseStageMessage(raw: string): StageServerMessage | null {
  const object = parseJson(raw);

  if (!isJsonObject(object) || object['version'] !== 1) return null;
  const message = MESSAGES.get(stringField(object, 'type') ?? '');

  if (
    !message ||
    Object.keys(object).some((key) => !message.fields.includes(key))
  )
    return null;

  return message.parse(object);
}

export interface StageProfileInput {
  receiverId: string;
  displayName: string;
  maxAudioChannels: number;
  supportedCodecs: string[];
  touch: boolean;
  lipSyncOffsetMs: number;
  receiverToken: string | null;
}

interface StageProfilePayload {
  version: 1;
  type: 'RECEIVER_PROFILE';
  receiverId: string;
  transportType: 'cadenza_web_tv_stage';
  displayName: string;
  hasDisplay: true;
  isStandby: false;
  isTouchSupported: boolean;
  maxAudioChannels: number;
  supportedCodecs: string[];
  lipSyncOffsetMs: number;
  receiverToken?: string;
}

/** The `RECEIVER_PROFILE` this browser sends on connect. The codecs are the ones the browser can actually decode. */
export function receiverProfile(input: StageProfileInput): string {
  const profile: StageProfilePayload = {
    version: 1,
    type: 'RECEIVER_PROFILE',
    receiverId: input.receiverId,
    transportType: 'cadenza_web_tv_stage',
    displayName: input.displayName,
    hasDisplay: true,
    isStandby: false,
    isTouchSupported: input.touch,
    maxAudioChannels: input.maxAudioChannels,
    supportedCodecs: input.supportedCodecs,
    lipSyncOffsetMs: input.lipSyncOffsetMs,
  };

  if (input.receiverToken !== null) profile.receiverToken = input.receiverToken;

  return JSON.stringify(profile);
}

/** The most characters of one log line the Host keeps. */
export const STAGE_LOG_MAX_LENGTH = 500;

/** What this browser's audio output is playing. The Host shows it beside the route it sends. */
export interface StagePlaybackReport {
  codec: 'aac' | 'ac3' | 'pcm';
  /** The channels this output plays, or 0 when the page cannot tell. */
  channels: number;
  path: 'mse' | 'pcm_worklet';
  active: boolean;
}

export function stagePlaybackMessage(report: StagePlaybackReport): string {
  return JSON.stringify({ version: 1, type: 'STAGE_PLAYBACK', ...report });
}

export function stageLogMessage(
  level: 'info' | 'warn' | 'error',
  message: string,
): string {
  return JSON.stringify({
    version: 1,
    type: 'STAGE_LOG',
    level,
    message: message.slice(0, STAGE_LOG_MAX_LENGTH),
  });
}
