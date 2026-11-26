import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { StageClock, stageRetryDelayMs } from '../app/lib/stage/stageClock';
import {
  decodeStageFrame,
  parseStageMessage,
  receiverProfile,
  type StageCodec,
  type StageFrame,
} from '../app/lib/stage/stageProtocol';

interface FrameFixture {
  name: string;
  hex: string;
  expect: {
    type: StageFrame['type'];
    codec?: StageCodec;
    generationSeq?: number;
    presentationTimeUs?: number;
    payloadHex?: string;
  };
}

// The fixture file that the Host and the Node tests also read, so the browser decoder cannot drift from the contract.
// SAFETY: tests/castStage.test.mjs fixes this file's shape and fails the portable gate if it changes.
const fixtures = JSON.parse(
  readFileSync(
    new URL(
      '../../../shared/protocol/examples/cast-stage-frames.json',
      import.meta.url,
    ),
    'utf8',
  ),
) as { frames: FrameFixture[]; rejects: { name: string; hex: string }[] };

function bytesOf(hex: string): Uint8Array {
  const pairs = hex.match(/../g) ?? [];

  return Uint8Array.from(pairs, (pair) => Number.parseInt(pair, 16));
}

describe('stage binary frames', () => {
  for (const fixture of fixtures.frames) {
    test(`${fixture.name} decodes to its documented fields`, () => {
      const frame = decodeStageFrame(bytesOf(fixture.hex));
      const expected = fixture.expect;
      expect(frame.type).toBe(expected.type);

      if ('codec' in frame && expected.codec !== undefined) {
        expect(frame.codec).toBe(expected.codec);
      }

      if (
        frame.type === 'FLUSH_STREAM' &&
        expected.generationSeq !== undefined
      ) {
        expect(frame.generationSeq).toBe(expected.generationSeq);
      }

      if (
        frame.type === 'AUDIO_FRAME' &&
        expected.presentationTimeUs !== undefined
      ) {
        expect(frame.presentationTimeUs).toBe(
          BigInt(expected.presentationTimeUs),
        );
      }

      if ('payload' in frame && expected.payloadHex !== undefined) {
        expect(Buffer.from(frame.payload).toString('hex')).toBe(
          expected.payloadHex,
        );
      }
    });
  }

  for (const reject of fixtures.rejects) {
    test(`malformed frame ${reject.name} is refused`, () => {
      expect(() => decodeStageFrame(bytesOf(reject.hex))).toThrow();
    });
  }
});

describe('stage messages from the Host', () => {
  const suite = {
    version: 1,
    type: 'TRACK_SUITE_PAYLOAD',
    trackId: 'abc',
    title: 'Pedida',
    artist: 'Akad',
    album: 'Album',
    durationMs: 214000,
    artworkUrl: 'http://192.168.1.10:8765/api/v1/cast/artwork/abc.jpg',
    motionUrl: 'http://192.168.1.10:8765/api/v1/cast/motion/abc.mp4',
    lines: [
      {
        id: 'l1',
        text: 'Hello',
        start_ms: 1000,
        end_ms: 2000,
        words: [{ text: 'Hello', start_ms: 1000, end_ms: 2000 }],
        translation: 'Halo',
        align: 'start',
      },
    ],
  };

  test('a track suite parses with its lines and an unset quality badge', () => {
    const parsed = parseStageMessage(JSON.stringify(suite));
    expect(parsed?.type).toBe('TRACK_SUITE_PAYLOAD');

    if (parsed?.type !== 'TRACK_SUITE_PAYLOAD') return;
    expect(parsed.suite.quality).toBeNull();
    expect(parsed.suite.lines[0]).toMatchObject({
      startMs: 1000,
      endMs: 2000,
      translation: 'Halo',
    });
  });

  test('a suite whose artwork is not a LAN URL drops that URL', () => {
    const parsed = parseStageMessage(
      JSON.stringify({ ...suite, artworkUrl: 'https://example.com/a.jpg' }),
    );

    expect(
      parsed?.type === 'TRACK_SUITE_PAYLOAD' && parsed.suite.artworkUrl,
    ).toBeNull();
  });

  test('messages with unknown fields, types, or out-of-range values are refused', () => {
    expect(
      parseStageMessage(JSON.stringify({ ...suite, requestedBy: 'remote' })),
    ).toBeNull();
    expect(
      parseStageMessage(JSON.stringify({ version: 1, type: 'REMOTE_COMMAND' })),
    ).toBeNull();
    expect(
      parseStageMessage(
        JSON.stringify({
          version: 1,
          type: 'OPTIMISTIC_STATE',
          isPlaying: true,
          targetPositionMs: -1,
          playbackRate: 1,
          hostMonoTimeMs: 0,
          audioLatencyMs: 0,
        }),
      ),
    ).toBeNull();
    expect(parseStageMessage('not json')).toBeNull();
  });

  test('a video payload must be a plain LAN MP4 with its subtitle track', () => {
    const video = {
      version: 1,
      type: 'VIDEO_KARAOKE_PAYLOAD',
      source: 'lan_mp4',
      mediaUrl: 'http://192.168.1.10:8765/api/v1/cast/video/abc/video.mp4',
      subtitleUrl: 'http://192.168.1.10:8765/api/v1/cast/video/abc/lyrics.vtt',
      userOffsetMs: -500,
    };

    expect(parseStageMessage(JSON.stringify(video))?.type).toBe(
      'VIDEO_KARAOKE_PAYLOAD',
    );
    expect(
      parseStageMessage(JSON.stringify({ ...video, source: 'hls_widevine' })),
    ).toBeNull();
    expect(
      parseStageMessage(
        JSON.stringify({
          ...video,
          mediaUrl: 'https://cdn.example/video.m3u8',
        }),
      ),
    ).toBeNull();
  });

  test('a pairing PIN must be exactly four digits', () => {
    const pairing = (pin: string) =>
      JSON.stringify({
        version: 1,
        type: 'STAGE_PAIRING',
        pin,
        expiresInMs: 300000,
      });

    expect(parseStageMessage(pairing('0427'))).toEqual({
      type: 'STAGE_PAIRING',
      pin: '0427',
      expiresInMs: 300000,
    });
    expect(parseStageMessage(pairing('427'))).toBeNull();
  });
});

describe('receiver profile', () => {
  test('the profile names the stage transport and omits a token it does not have', () => {
    // SAFETY: receiverProfile returns JSON.stringify output, so reading it back yields the fields it wrote.
    const profile = JSON.parse(
      receiverProfile({
        receiverId: 'tv-1',
        displayName: 'Cadenza TV',
        maxAudioChannels: 2,
        supportedCodecs: ['aac', 'pcm'],
        touch: false,
        lipSyncOffsetMs: 40,
        receiverToken: null,
      }),
    ) as {
      transportType: string;
      supportedCodecs: string[];
      receiverToken?: string;
    };

    expect(profile.transportType).toBe('cadenza_web_tv_stage');
    expect(profile.supportedCodecs).toEqual(['aac', 'pcm']);
    expect('receiverToken' in profile).toBe(false);
  });
});

describe('stage clock and retries', () => {
  test('the position advances with local time while playing and holds while paused', () => {
    const clock = new StageClock();
    clock.set(10_000, true, 1, 1_000);
    expect(clock.positionAt(1_500, 0)).toBe(10_500);
    clock.set(10_000, false, 1, 1_000);
    expect(clock.positionAt(5_000, 0)).toBe(10_000);
  });

  test('the position never runs past the track length', () => {
    const clock = new StageClock();
    clock.set(0, true, 1, 0);
    expect(clock.positionAt(999_999, 214_000)).toBe(214_000);
  });

  test('reconnect delays double from one second and stay within thirty seconds', () => {
    expect(stageRetryDelayMs(0)).toBe(1_000);
    expect(stageRetryDelayMs(3)).toBe(8_000);
    expect(stageRetryDelayMs(50)).toBe(30_000);
  });
});
