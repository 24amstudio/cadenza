import { describe, expect, test } from 'bun:test';
import {
  LYRIC_NUDGE_LIMIT_MS,
  LYRIC_NUDGE_STEP_MS,
  lyricClockMs,
  nudgeDelay,
  syncFirstLineDelay,
} from '../app/lib/lyricNudge';

describe('karaoke nudge', () => {
  test('a press shows lyrics half a second later or earlier', () => {
    expect(nudgeDelay(0, LYRIC_NUDGE_STEP_MS)).toBe(500);
    expect(nudgeDelay(0, -LYRIC_NUDGE_STEP_MS)).toBe(-500);
    expect(lyricClockMs(30_000, nudgeDelay(0, LYRIC_NUDGE_STEP_MS))).toBe(
      29_500,
    );
  });

  test('the delay stops at the limit instead of growing without bound', () => {
    expect(nudgeDelay(LYRIC_NUDGE_LIMIT_MS, LYRIC_NUDGE_STEP_MS)).toBe(
      LYRIC_NUDGE_LIMIT_MS,
    );
    expect(nudgeDelay(-LYRIC_NUDGE_LIMIT_MS, -LYRIC_NUDGE_STEP_MS)).toBe(
      -LYRIC_NUDGE_LIMIT_MS,
    );
  });

  test('Sync First Line makes the first line active where the user pressed it', () => {
    const firstLineStartMs = 12_000;
    const pressedAtMs = 12_400;
    const delay = syncFirstLineDelay(firstLineStartMs, pressedAtMs);

    expect(lyricClockMs(pressedAtMs, delay)).toBe(firstLineStartMs);
  });
});
