import { describe, expect, test } from 'bun:test';
import { RemoteAudioCore } from '../public/remote-audio/core.js';
import {
  contextFrameForHost,
  remoteUsForHost,
  type ClockFix,
} from '../app/lib/remoteAudio/clockMap';
import { nextSequence, sequenceStep } from '../app/lib/remoteAudio/sequence';

const sampleRate = 48_000;
const quantum = 128;

interface Core {
  write(
    startFrame: number,
    left: Float32Array,
    right: Float32Array,
    currentFrame: number,
  ): void;
  render(left: Float32Array, right: Float32Array): void;
  flush(): void;
  setTargetFill(frames: number): void;
  readonly fillFrames: number;
  readonly rate: number;
}

function block(
  start: number,
  value: (frame: number) => number,
  length = quantum,
): Float32Array {
  return Float32Array.from({ length }, (_, index) => value(start + index));
}

describe('remote audio playout', () => {
  test('contiguous frames play at their playout positions without drift', () => {
    const core: Core = new RemoteAudioCore(sampleRate);
    // A unique, exactly representable value for every frame position.
    const value = (frame: number) => frame / 1_048_576;
    // Three blocks ahead keeps the fill at 384 frames, so the rate stays exactly 1.
    core.setTargetFill(3 * quantum);

    for (let block_ = 0; block_ < 3; block_ += 1) {
      const start = block_ * quantum;
      core.write(start, block(start, value), block(start, value), 0);
    }

    const left = new Float32Array(quantum);
    const right = new Float32Array(quantum);

    for (let index = 0; index < 6; index += 1) {
      // Render first, then write the block that keeps the fill constant three blocks ahead.
      core.render(left, right);
      const playedFrom = index * quantum;

      for (let frame = 0; frame < quantum; frame += 1) {
        expect(left[frame]).toBe(Math.fround(value(playedFrom + frame)));
      }

      const start = (index + 3) * quantum;
      core.write(
        start,
        block(start, value),
        block(start, value),
        (index + 1) * quantum,
      );
    }

    expect(core.rate).toBe(1);
  });

  test('a gap fades out before it and fades in after it, with silence between', () => {
    const core: Core = new RemoteAudioCore(sampleRate);
    core.setTargetFill(1);
    core.write(
      0,
      block(0, () => 1),
      block(0, () => 1),
      0,
    );
    // The second segment is 256 frames, so the 144-frame fade-in has written audio to read.
    core.write(
      768,
      block(768, () => 1, 256),
      block(768, () => 1, 256),
      0,
    );

    const left = new Float32Array(1_024);
    const right = new Float32Array(1_024);

    core.render(left, right);

    // The unread tail before the gap ends near zero, so the cut is not a click.
    expect(Math.abs(left[127] ?? 1)).toBeLessThan(0.01);
    // The silence inside the gap is exact.
    expect(left[400]).toBe(0);
    // The new segment rises from zero over the 3 ms fade.
    expect(left[768]).toBeLessThan(0.01);
    expect(left[768 + 143]).toBeGreaterThan(0.99);
  });

  test('a flush empties the buffer, and nothing from before it plays after', () => {
    const core: Core = new RemoteAudioCore(sampleRate);
    core.setTargetFill(1);
    core.write(
      0,
      block(0, () => 0.5),
      block(0, () => 0.5),
      0,
    );
    core.flush();

    const left = new Float32Array(quantum);
    const right = new Float32Array(quantum);
    core.render(left, right);

    expect(core.fillFrames).toBe(0);
    expect(Array.from(left).every((sample) => sample === 0)).toBe(true);
  });

  test('a frame that arrives after its playout position is dropped, not played late', () => {
    const core: Core = new RemoteAudioCore(sampleRate);
    core.setTargetFill(1);
    core.write(
      0,
      block(0, () => 0.25),
      block(0, () => 0.25),
      0,
    );
    const left = new Float32Array(quantum);
    const right = new Float32Array(quantum);
    core.render(left, right);

    // The read position has passed frame 16 by now, so this 16-frame block is entirely late.
    const before = core.fillFrames;
    core.write(
      10,
      block(10, () => 0.9, 16),
      block(10, () => 0.9, 16),
      0,
    );

    expect(core.fillFrames).toBe(before);
  });

  test('the controller keeps a ±80 ppm clock skew within 0.2 ms over one hour', () => {
    const core: Core = new RemoteAudioCore(sampleRate);
    const cushion = Math.round(0.028 * sampleRate);
    const target = cushion + quantum;
    const skew = 80e-6;
    const warmupQuanta = Math.round((120 * sampleRate) / quantum);
    const totalQuanta = Math.round((3_600 * sampleRate) / quantum);
    const left = new Float32Array(quantum).fill(0.1);
    const right = new Float32Array(quantum).fill(-0.1);
    const out = new Float32Array(quantum);
    const outRight = new Float32Array(quantum);
    let worstMs = 0;

    core.setTargetFill(target);

    for (let quantumIndex = 0; quantumIndex < totalQuanta; quantumIndex += 1) {
      // The Host's content runs (1 + skew) times faster than this output clock, so each frame lands that much later.
      const startFrame =
        Math.round(quantumIndex * quantum * (1 + skew)) + cushion;

      core.write(startFrame, left, right, quantumIndex * quantum);
      // The controller acts on the fill at the start of each render, so the error is measured at the same point.

      if (quantumIndex > warmupQuanta) {
        const errorMs = ((core.fillFrames - target) / sampleRate) * 1_000;
        worstMs = Math.max(worstMs, Math.abs(errorMs));
      }

      core.render(out, outRight);
    }

    expect(worstMs).toBeLessThan(0.2);
    expect(Math.abs(core.rate - 1 - skew)).toBeLessThan(5e-6);
  }, 120_000);
});

describe('clock mapping', () => {
  test('extrapolates the Remote clock with drift, and returns the same Host instant', () => {
    const sendHostUs = 3_600_000_000;
    const driftPpm = 80;
    const offsetAtSend = 5_000_000 + (driftPpm * sendHostUs) / 1_000_000;
    // A message that arrives 1 ms after it was sent reads the Remote clock at that instant.

    const arrivedAtRemoteUs =
      sendHostUs + 1_000 + offsetAtSend + (driftPpm * 1_000) / 1_000_000;

    const fix: ClockFix = {
      offsetUs: offsetAtSend,
      driftPpm,
      arrivedAtRemoteUs,
    };

    const target = sendHostUs + 10_000_000;
    const expected = target + 5_000_000 + (driftPpm * target) / 1_000_000;

    expect(Math.abs(remoteUsForHost(target, fix) - expected)).toBeLessThan(2);
  });

  test('maps a playout instant to the AudioContext frame that plays it', () => {
    const fix: ClockFix = {
      offsetUs: 0,
      driftPpm: 0,
      arrivedAtRemoteUs: 5_000_000,
    };
    // The context was at 10 s when performance.now() was 5000 ms. The target is 20 ms later on both clocks.

    const frame = contextFrameForHost(
      5_020_000,
      fix,
      { contextTime: 10, performanceTime: 5_000 },
      sampleRate,
    );

    expect(frame).toBe(Math.round((10 + 0.02) * sampleRate));
  });
});

describe('sequence numbers', () => {
  test('classifies in-order, gapped, and late frames, including the 32-bit wrap', () => {
    expect(sequenceStep(null, 9)).toEqual({ kind: 'start' });
    expect(sequenceStep(10, 10)).toEqual({ kind: 'in_order' });
    expect(sequenceStep(10, 13)).toEqual({ kind: 'gap', missing: 3 });
    expect(sequenceStep(10, 9)).toEqual({ kind: 'late' });
    expect(nextSequence(0xffff_ffff)).toBe(0);
    expect(sequenceStep(nextSequence(0xffff_ffff), 0)).toEqual({
      kind: 'in_order',
    });
    expect(sequenceStep(0, 0xffff_ffff)).toEqual({ kind: 'late' });
  });
});
