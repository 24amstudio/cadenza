/** One press of the karaoke nudge changes the lyric delay by half a second. */
export const LYRIC_NUDGE_STEP_MS = 500;

/** The delay can be set at most ten seconds either way, which covers a misaligned lyric document. */
export const LYRIC_NUDGE_LIMIT_MS = 10_000;

function clampDelay(delayMs: number): number {
  return Math.min(
    LYRIC_NUDGE_LIMIT_MS,
    Math.max(-LYRIC_NUDGE_LIMIT_MS, Math.round(delayMs)),
  );
}

/** Shows lyrics later by a positive step, or earlier by a negative one. */
export function nudgeDelay(delayMs: number, stepMs: number): number {
  return clampDelay(delayMs + stepMs);
}

/** The delay that makes the first timed line active at the playback position where the user pressed Sync First Line. */
export function syncFirstLineDelay(
  firstLineStartMs: number,
  positionMs: number,
): number {
  return clampDelay(positionMs - firstLineStartMs);
}

/** The position the lyrics are matched against once the delay is applied. */
export function lyricClockMs(positionMs: number, delayMs: number): number {
  return positionMs - delayMs;
}
