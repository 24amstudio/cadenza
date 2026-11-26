import { describe, expect, test } from 'bun:test';
import { DRIFT_RADIUS_PX, driftOffset } from '../app/lib/oledDrift';

describe('driftOffset', () => {
  test('every step stays within the drift radius and the steps repeat, so the content keeps moving', () => {
    const offsets = Array.from({ length: 16 }, (_, step) => driftOffset(step));

    for (const { x, y } of offsets) {
      expect(Math.abs(x)).toBeLessThanOrEqual(DRIFT_RADIUS_PX);
      expect(Math.abs(y)).toBeLessThanOrEqual(DRIFT_RADIUS_PX);
    }

    expect(offsets[0]).toEqual(offsets[8]);
    expect(
      new Set(offsets.slice(0, 8).map(({ x, y }) => `${x},${y}`)).size,
    ).toBe(8);
  });

  test('a step moves the content to a different position from the one before it', () => {
    for (let step = 0; step < 8; step += 1) {
      expect(driftOffset(step)).not.toEqual(driftOffset(step + 1));
    }
  });
});
