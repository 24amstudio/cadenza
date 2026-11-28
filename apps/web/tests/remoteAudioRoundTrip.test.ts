import { describe, expect, test } from 'bun:test';
import { streamRoundTrip } from '../app/lib/remoteAudio/roundTrip';

describe('stream round trip', () => {
  test('shows nothing while the Host sends no audio, even with exchanges on record', () => {
    expect(
      streamRoundTrip({
        transmitting: false,
        networkRttMs: 9,
        processingRttMs: 1,
      }),
    ).toBeNull();
  });

  test('shows nothing before the first exchange completes', () => {
    expect(
      streamRoundTrip({
        transmitting: true,
        networkRttMs: null,
        processingRttMs: null,
      }),
    ).toBeNull();
  });

  test('rounds each part, and the total is their sum, so the figures add up', () => {
    expect(
      streamRoundTrip({
        transmitting: true,
        networkRttMs: 9.4,
        processingRttMs: 0.7,
      }),
    ).toEqual({ totalMs: 10, networkMs: 9, processingMs: 1 });
  });

  test('the total is the sum of the rounded parts, not the rounded sum of the raw parts', () => {
    expect(
      streamRoundTrip({
        transmitting: true,
        networkRttMs: 2.4,
        processingRttMs: 2.4,
      }),
    ).toEqual({ totalMs: 4, networkMs: 2, processingMs: 2 });
  });
});
