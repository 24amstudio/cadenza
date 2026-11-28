import { contextFrameForHost, type ClockFix } from './clockMap';

export interface OutputClockSample {
  contextTime: number;
  epochMs: number;
}

export function outputClockAt(sample: OutputClockSample, nowEpochMs: number) {
  return {
    contextTime: sample.contextTime + (nowEpochMs - sample.epochMs) / 1_000,
    performanceTime: nowEpochMs,
  };
}

export function playoutFrame(
  hostUs: number,
  fix: ClockFix,
  sample: OutputClockSample,
  nowEpochMs: number,
  sampleRate: number,
): number {
  return contextFrameForHost(
    hostUs,
    fix,
    outputClockAt(sample, nowEpochMs),
    sampleRate,
  );
}
