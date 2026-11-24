/** How far the ambient content may move from its centre, in CSS pixels, so it never sits on the same OLED pixels long. */
export const DRIFT_RADIUS_PX = 8;

/** How often the ambient content moves to its next position. */
export const DRIFT_INTERVAL_MS = 45_000;

const STEPS: readonly (readonly [number, number])[] = [
  [0, 0],
  [1, 0],
  [1, 1],
  [0, 1],
  [-1, 1],
  [-1, 0],
  [-1, -1],
  [0, -1],
];

export interface DriftOffset {
  x: number;
  y: number;
}

/** The offset for one drift step. The steps repeat, and every offset stays within DRIFT_RADIUS_PX of the centre. */
export function driftOffset(step: number): DriftOffset {
  const index =
    ((Math.trunc(step) % STEPS.length) + STEPS.length) % STEPS.length;

  const [x, y] = STEPS[index] ?? [0, 0];

  return { x: x * DRIFT_RADIUS_PX, y: y * DRIFT_RADIUS_PX };
}
