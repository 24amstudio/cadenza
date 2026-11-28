import { describe, expect, test } from 'bun:test';
import { outputClockAt, playoutFrame } from '../app/lib/remoteAudio/timeline';

describe('output timeline', () => {
  test('the output clock extrapolates at wall-clock rate from the last sample', () => {
    expect(outputClockAt({ contextTime: 2, epochMs: 5_000 }, 5_500)).toEqual({
      contextTime: 2.5,
      performanceTime: 5_500,
    });
  });

  test('a playout instant that has already passed maps to an earlier frame than the one playing now', () => {
    const frame = playoutFrame(
      1_000_000,
      { offsetUs: 0, driftPpm: 0, arrivedAtRemoteUs: 1_000_000 },
      { contextTime: 10, epochMs: 1_000 },
      1_500,
      48_000,
    );

    expect(frame).toBe(480_000);
    expect(10.5 * 48_000 - frame).toBe(24_000);
  });
});
