import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { Ajv2020 } from 'ajv/dist/2020.js';
import common from '../shared/protocol/v1/common.schema.json' with { type: 'json' };
import state from '../shared/protocol/v1/state.schema.json' with { type: 'json' };
import cast from '../shared/protocol/v1/cast.schema.json' with { type: 'json' };

const castSchemaPath = new URL(
  '../shared/protocol/v1/cast.schema.json',
  import.meta.url,
);

const ajv = new Ajv2020({ strict: true, allErrors: true });

ajv.addSchema(common);

ajv.addSchema(state);

const validateCast = ajv.compile(cast);

const receiverProfile = {
  version: 1,
  type: 'RECEIVER_PROFILE',
  receiverId: 'tv-living-room-01',
  transportType: 'cadenza_android_tv_receiver',
  displayName: 'Living Room Google TV',
  hasDisplay: true,
  isStandby: false,
  isTouchSupported: false,
  maxAudioChannels: 6,
  supportedCodecs: ['ac-3', 'ec-3', 'flac', 'pcm'],
  lipSyncOffsetMs: 0,
};

const trackSuite = {
  version: 1,
  type: 'TRACK_SUITE_PAYLOAD',
  trackId: 'catalog:1440657000',
  title: 'Sample Song',
  artist: 'Sample Artist',
  album: 'Sample Album',
  durationMs: 214_000,
  quality: 'Dolby Atmos',
  artworkUrl: 'http://192.168.1.10:8765/api/v1/cast/artwork/1440657000.jpg',
  motionUrl: 'http://192.168.1.10:8765/api/v1/cast/motion/1440657000.mp4',
  lines: [
    {
      id: 'line-1',
      text: 'First line',
      translation: 'Baris pertama',
      start_ms: 1000,
      end_ms: 4000,
      align: 'start',
      words: [{ text: 'First', start_ms: 1000, end_ms: 2000 }],
    },
  ],
};

test('a receiver profile from a Tier-2 or Tier-3 receiver validates', () => {
  assert.equal(
    validateCast(receiverProfile),
    true,
    JSON.stringify(validateCast.errors),
  );
  assert.equal(
    validateCast({ ...receiverProfile, transportType: 'cadenza_web_tv_stage' }),
    true,
  );
});

test('every stage message type validates from its fixture', () => {
  const fixtures = [
    trackSuite,
    {
      version: 1,
      type: 'PREFETCH_NEXT_SUITE',
      trackId: 'catalog:2',
      reason: 'near_end',
    },
    {
      version: 1,
      type: 'OPTIMISTIC_STATE',
      isPlaying: true,
      targetPositionMs: 12_345,
      playbackRate: 1,
      hostMonoTimeMs: 987_654,
      audioLatencyMs: 40,
    },
    {
      version: 1,
      type: 'CLOCK_CALIBRATE',
      actualPositionMs: 12_380,
      audioLatencyMs: 40,
      hostMonoTimeMs: 987_700,
    },
    {
      version: 1,
      type: 'VIDEO_KARAOKE_PAYLOAD',
      source: 'lan_mp4',
      mediaUrl: 'http://192.168.1.10:8765/api/v1/cast/video/7/video.mp4',
      subtitleUrl: 'http://192.168.1.10:8765/api/v1/cast/video/7/lyrics.vtt',
      userOffsetMs: -500,
    },
    {
      version: 1,
      type: 'STAGE_PLAYBACK',
      codec: 'ac3',
      channels: 6,
      path: 'mse',
      active: true,
    },
    {
      version: 1,
      type: 'STAGE_LOG',
      level: 'warn',
      message: 'Playback paused: the audio context was suspended.',
    },
  ];

  for (const fixture of fixtures) {
    assert.equal(
      validateCast(fixture),
      true,
      `${fixture.type}: ${JSON.stringify(validateCast.errors)}`,
    );
  }
});

test('a playback report names only a codec and channel count the Host can send', () => {
  const report = {
    version: 1,
    type: 'STAGE_PLAYBACK',
    codec: 'ac3',
    channels: 6,
    path: 'mse',
    active: true,
  };

  assert.equal(validateCast({ ...report, codec: 'flac' }), false);
  assert.equal(validateCast({ ...report, channels: 0 }), false);
  assert.equal(validateCast({ ...report, path: 'mse path' }), false);
});

test('stage messages reject unknown types, unknown fields, and out-of-range values', () => {
  assert.equal(
    validateCast({ ...receiverProfile, type: 'RECEIVER_STATUS' }),
    false,
  );
  assert.equal(
    validateCast({ ...receiverProfile, requestedBy: 'remote' }),
    false,
  );
  assert.equal(
    validateCast({ ...receiverProfile, maxAudioChannels: 9 }),
    false,
  );
  assert.equal(
    validateCast({ ...receiverProfile, lipSyncOffsetMs: 251 }),
    false,
  );
  assert.equal(
    validateCast({ ...receiverProfile, supportedCodecs: ['ac-3', 'ac-3'] }),
    false,
  );
  assert.equal(validateCast({ ...trackSuite, quality: 'Hi-Res' }), false);
  assert.equal(
    validateCast({
      version: 1,
      type: 'OPTIMISTIC_STATE',
      isPlaying: false,
      targetPositionMs: -1,
      playbackRate: 1,
      hostMonoTimeMs: 0,
      audioLatencyMs: 0,
    }),
    false,
  );
  assert.equal(
    validateCast({
      version: 1,
      type: 'OPTIMISTIC_STATE',
      isPlaying: false,
      targetPositionMs: 0,
      playbackRate: 0,
      hostMonoTimeMs: 0,
      audioLatencyMs: 0,
    }),
    false,
  );
});

test('Widevine and FairPlay routes are not part of the zero-account Cast contract', () => {
  assert.equal(
    validateCast({ ...receiverProfile, supportsWidevineL1: true }),
    false,
    'a receiver cannot advertise Widevine L1 in this contract',
  );
  assert.equal(
    validateCast({
      version: 1,
      type: 'VIDEO_KARAOKE_PAYLOAD',
      source: 'hls_widevine',
      mediaUrl: 'http://192.168.1.10:8765/video.m3u8',
      subtitleUrl: 'http://192.168.1.10:8765/lyrics.vtt',
      userOffsetMs: 0,
    }),
    false,
  );
  assert.equal(
    validateCast({
      version: 1,
      type: 'VIDEO_KARAOKE_PAYLOAD',
      source: 'lan_mp4',
      mediaUrl: 'http://192.168.1.10:8765/video.mp4',
      subtitleUrl: 'http://192.168.1.10:8765/lyrics.vtt',
      userOffsetMs: 0,
      licenseUrl: 'https://example.invalid/license',
    }),
    false,
  );
});

test('stage URLs stay on plain HTTP LAN addresses and the contract names no paid console IDs', () => {
  const karaoke = {
    version: 1,
    type: 'VIDEO_KARAOKE_PAYLOAD',
    source: 'airplay_hls_proxy',
    mediaUrl: 'https://play.example.invalid/master.m3u8',
    subtitleUrl: 'http://192.168.1.10:8765/lyrics.vtt',
    userOffsetMs: 0,
  };

  assert.equal(validateCast(karaoke), false);

  const source = readFileSync(castSchemaPath, 'utf8');

  const withoutMetaSchema = source.replace(/"\$schema": "[^"]*"/, '');

  assert.equal(/https:\/\//.test(withoutMetaSchema), false);
  assert.equal(/applicationId|appId|receiverUrl/i.test(source), false);
});

// The binary contract is defined by shared/protocol/examples/cast-stage-frames.json. Every decoder in the Host tests, the
// web stage, and the Android TV receiver reads the same bytes, so this file defines the reference decoder for them.
/** @type {{ frames: { name: string, hex: string, expect: Record<string, any> }[], rejects: { name: string, hex: string }[] }} */
const stageFixtures = JSON.parse(
  readFileSync(
    new URL(
      '../shared/protocol/examples/cast-stage-frames.json',
      import.meta.url,
    ),
    'utf8',
  ),
);

const sampleRates = new Map([
  [1, 48_000],
  [2, 44_100],
]);

const audioCodecs = new Set([1, 2, 3, 4]);
const maxPayloadBytes = 65_536;

/** @param {Buffer} bytes */
function decodeStageFrame(bytes) {
  if (bytes.length === 0) throw new Error('empty frame');

  const type = bytes.readUInt8(0);

  if (type === 0x02) {
    if (bytes.length !== 5) throw new Error('flush frame must be 5 bytes');

    return { type: 'FLUSH_STREAM', generationSeq: bytes.readUInt32BE(1) };
  }

  if (type === 0x03) {
    if (bytes.length < 8) throw new Error('init segment header is truncated');

    const codec = bytes.readUInt8(1);
    const channels = bytes.readUInt8(2);
    const sampleRateCode = bytes.readUInt8(3);
    const payloadLength = bytes.readUInt32BE(4);

    checkAudioHeader(codec, channels, sampleRateCode);

    if (payloadLength > maxPayloadBytes)
      throw new Error('payload exceeds the frame limit');

    if (bytes.length - 8 !== payloadLength)
      throw new Error('payload length does not match the frame');

    return {
      type: 'INIT_SEGMENT',
      codec,
      channels,
      sampleRate: sampleRates.get(sampleRateCode),
      payload: bytes.subarray(8),
    };
  }

  if (type !== 0x01) throw new Error('unknown frame type');

  if (bytes.length < 16) throw new Error('audio frame header is truncated');

  const codec = bytes.readUInt8(1);
  const channels = bytes.readUInt8(2);
  const sampleRateCode = bytes.readUInt8(3);
  const payloadLength = bytes.readUInt32BE(12);

  checkAudioHeader(codec, channels, sampleRateCode);

  if (payloadLength > maxPayloadBytes)
    throw new Error('payload exceeds the frame limit');

  if (bytes.length - 16 !== payloadLength)
    throw new Error('payload length does not match the frame');

  return {
    type: 'AUDIO_FRAME',
    codec,
    channels,
    sampleRate: sampleRates.get(sampleRateCode),
    presentationTimeUs: bytes.readBigUInt64BE(4),
    payload: bytes.subarray(16),
  };
}

/** @param {number} codec @param {number} channels @param {number} sampleRateCode */
function checkAudioHeader(codec, channels, sampleRateCode) {
  if (!audioCodecs.has(codec)) throw new Error('unknown codec');

  if (channels < 1 || channels > 8)
    throw new Error('channel count out of range');

  if (!sampleRates.has(sampleRateCode))
    throw new Error('unknown sample rate code');
}

for (const fixture of stageFixtures.frames) {
  test(`stage frame fixture ${fixture.name} decodes to its documented fields`, () => {
    const decoded = decodeStageFrame(Buffer.from(fixture.hex, 'hex'));

    assert.equal(decoded.type, fixture.expect.type);

    if (fixture.expect.codec !== undefined)
      assert.equal(decoded.codec, fixture.expect.codec);

    if (fixture.expect.channels !== undefined)
      assert.equal(decoded.channels, fixture.expect.channels);

    if (fixture.expect.sampleRate !== undefined)
      assert.equal(decoded.sampleRate, fixture.expect.sampleRate);

    if (fixture.expect.generationSeq !== undefined) {
      assert.equal(decoded.generationSeq, fixture.expect.generationSeq);
    }

    if (fixture.expect.presentationTimeUs !== undefined) {
      assert.equal(
        decoded.presentationTimeUs,
        BigInt(fixture.expect.presentationTimeUs),
      );
    }

    if ('payload' in decoded && fixture.expect.payloadHex !== undefined) {
      assert.equal(
        Buffer.from(decoded.payload).toString('hex'),
        fixture.expect.payloadHex,
      );
    }
  });
}

for (const reject of stageFixtures.rejects) {
  test(`malformed stage frame ${reject.name} is rejected before a receiver uses it`, () => {
    assert.throws(
      () => decodeStageFrame(Buffer.from(reject.hex, 'hex')),
      (error) => error instanceof Error,
    );
  });
}

test('the audio frame header is exactly 16 bytes and the flush frame is 5 bytes', () => {
  const audio = stageFixtures.frames.find(
    (frame) => frame.name === 'aac_stereo_fragment_48k',
  );

  const flush = stageFixtures.frames.find(
    (frame) => frame.name === 'flush_generation_7',
  );

  assert.equal(Buffer.from(audio?.hex ?? '', 'hex').length - 4, 16);
  assert.equal(Buffer.from(flush?.hex ?? '', 'hex').length, 5);
});
