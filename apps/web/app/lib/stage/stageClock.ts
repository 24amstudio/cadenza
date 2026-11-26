// Playback position on the receiver. The Host sends a position only when a command changes playback or a track starts,
// so the receiver advances the last position by its own monotonic clock between those messages.

export interface StageClockBaseline {
  positionMs: number;
  localMs: number;
  playing: boolean;
  rate: number;
}

export class StageClock {
  private baseline: StageClockBaseline = {
    positionMs: 0,
    localMs: 0,
    playing: false,
    rate: 1,
  };

  /** Replaces the position, from an optimistic state or a calibration, at the local time it arrived. */
  set(
    positionMs: number,
    playing: boolean,
    rate: number,
    localMs: number,
  ): void {
    this.baseline = { positionMs, localMs, playing, rate };
  }

  /** The track position at `localMs`, never negative, and clamped to the track length when it is known. */
  positionAt(localMs: number, durationMs: number): number {
    const { positionMs, localMs: since, playing, rate } = this.baseline;
    const advanced = playing ? Math.max(0, localMs - since) * rate : 0;
    const position = Math.max(0, positionMs + advanced);

    return durationMs > 0 ? Math.min(position, durationMs) : position;
  }

  get isPlaying(): boolean {
    return this.baseline.playing;
  }
}

/** The delay between a Host position and what a listener hears: the AVR offset and the saved karaoke nudge. */
export function lyricPositionMs(
  positionMs: number,
  lipSyncOffsetMs: number,
  userOffsetMs: number,
): number {
  return positionMs - lipSyncOffsetMs - userOffsetMs;
}

/** Retry delays for the stage socket: 1 s, doubling, capped at 30 s. The Host may be away for a long time. */
export function stageRetryDelayMs(attempt: number): number {
  const safe = Math.max(0, Math.min(attempt, 16));

  return Math.min(30_000, 1_000 * 2 ** safe);
}
