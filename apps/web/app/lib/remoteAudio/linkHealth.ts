export const rttWindowSamples = 10;

export const dropoutWindowCount = 30;

export interface StreamHealth {
  jitterMs: number | null;
  dropoutMs60s: number;
  hostDroppedFrames60s: number;
}

export function jitterMs(samples: readonly number[]): number | null {
  if (samples.length < 3) return null;

  let sum = 0;

  for (const sample of samples) sum += sample;

  const mean = sum / samples.length;
  let squares = 0;

  for (const sample of samples) squares += (sample - mean) ** 2;

  return Math.sqrt(squares / samples.length);
}

function jitterBars(jitter: number): number {
  if (jitter <= 2) return 4;

  if (jitter <= 5) return 3;

  if (jitter <= 10) return 2;

  return 1;
}

function dropoutBars(dropoutMs: number): number {
  if (dropoutMs <= 0) return 4;

  if (dropoutMs <= 20) return 3;

  if (dropoutMs <= 100) return 2;

  return 1;
}

function hostDropBars(frames: number): number {
  if (frames <= 0) return 4;

  if (frames <= 2) return 3;

  if (frames <= 10) return 2;

  return 1;
}

export function streamSignalBars(health: StreamHealth): number {
  const bars = [
    dropoutBars(health.dropoutMs60s),
    hostDropBars(health.hostDroppedFrames60s),
  ];

  if (health.jitterMs !== null) bars.push(jitterBars(health.jitterMs));

  return Math.min(...bars);
}

export function receiverLinkBars(
  controlBars: number,
  health: StreamHealth | null,
): number {
  if (health === null) return controlBars;

  return Math.min(controlBars, streamSignalBars(health));
}
