import { describe, expect, test } from 'bun:test';
import { decodeHostMessage } from '../app/lib/protocol/decode';
import { encodeCommand } from '../app/lib/protocol/encode';
import type { JsonObject } from '../app/lib/protocol/json';

const remoteId = '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c';
const epoch = '6e4f9a10-1111-4222-8333-444455556666';
const occurrenceId = '0a0b0c0d-1111-4222-8333-444455556666';

const song = {
  source: 'catalog',
  id: '1440857781',
  title: 'Breathe Deeper',
  artist: 'Tame Impala',
  album: 'The Slow Rush',
  duration_ms: 372000,
  artwork_url: 'https://example.com/art.jpg',
};

function stateWith(sing: JsonObject | undefined): string {
  const snapshot: JsonObject = {
    host_id: remoteId,
    host_epoch: epoch,
    revision: 18,
    sequence: 4,
    host_time_ms: 90000,
    allow_cross_remote_edits: false,
    playing: true,
    volume: 40,
    shuffle: true,
    repeat: 'all',
    current: {
      occurrence_id: occurrenceId,
      requester_name: 'Mia',
      song,
      position_ms: 126000,
      sampled_at_host_ms: 89000,
    },
    queue: [],
    quality: 'unknown',
    synchronized: true,
    observation_gap: false,
  };

  if (sing !== undefined) snapshot.sing = sing;

  return JSON.stringify({ version: 1, type: 'state', snapshot });
}

describe('Sing session decoding', () => {
  test('an active session decodes its level, latency, and model state', () => {
    const message = decodeHostMessage(
      stateWith({
        status: 'active',
        vocal_percent: 40,
        latency_ms: 120,
        backend: 'mlx-mel-roformer',
        model_ready: true,
      }),
    );

    expect(message).toMatchObject({
      type: 'state',
      snapshot: {
        revision: 18,
        sing: {
          status: 'active',
          vocalPercent: 40,
          latencyMs: 120,
          issue: null,
          modelReady: true,
        },
      },
    });
  });

  test('a Host that predates Sing decodes the snapshot without a session', () => {
    expect(decodeHostMessage(stateWith(undefined))).toMatchObject({
      type: 'state',
      snapshot: { revision: 18, sing: null },
    });
  });

  test('an unknown status or an out-of-range level is left out, and the rest of the snapshot still decodes', () => {
    expect(
      decodeHostMessage(stateWith({ status: 'listening', vocal_percent: 40 })),
    ).toMatchObject({ type: 'state', snapshot: { revision: 18, sing: null } });
    expect(
      decodeHostMessage(stateWith({ status: 'ready', vocal_percent: 101 })),
    ).toMatchObject({ type: 'state', snapshot: { revision: 18, sing: null } });
  });

  test('a failed session carries the Host issue for the retry prompt', () => {
    expect(
      decodeHostMessage(
        stateWith({
          status: 'failed',
          vocal_percent: 0,
          issue: 'Audio capture is unavailable.',
        }),
      ),
    ).toMatchObject({
      type: 'state',
      snapshot: {
        sing: { status: 'failed', issue: 'Audio capture is unavailable.' },
      },
    });
  });
});

describe('Sing command frames', () => {
  const base = {
    commandId: remoteId,
    hostEpoch: epoch,
    expiresAtHostMs: 9000,
    expectedRevision: 18,
  };

  test('start and stop carry only the occurrence', () => {
    expect(
      JSON.parse(
        encodeCommand({
          ...base,
          action: { kind: 'sing.enable', occurrenceId },
        }),
      ).action,
    ).toEqual({ kind: 'sing.enable', occurrence_id: occurrenceId });
    expect(
      JSON.parse(
        encodeCommand({
          ...base,
          action: { kind: 'sing.disable', occurrenceId },
        }),
      ).action,
    ).toEqual({ kind: 'sing.disable', occurrence_id: occurrenceId });
  });

  test('a vocal change carries the occurrence and the level', () => {
    expect(
      JSON.parse(
        encodeCommand({
          ...base,
          action: { kind: 'sing.mix', occurrenceId, vocalPercent: 35 },
        }),
      ).action,
    ).toEqual({
      kind: 'sing.mix',
      occurrence_id: occurrenceId,
      vocal_percent: 35,
    });
  });
});
