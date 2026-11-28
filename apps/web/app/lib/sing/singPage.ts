import {
  booleanField,
  isJsonObject,
  numberField,
  parseJson,
  stringField,
} from '../protocol/json';
import type { LyricLine } from '../protocol/types';

export interface SingPageState {
  occurrenceId: string;
  title: string;
  artist: string;
  positionMs: number;
  playing: boolean;
}

export function decodeSingPageState(text: string): SingPageState | null {
  const value = parseJson(text);

  if (value === null || !isJsonObject(value)) return null;
  if (stringField(value, 'type') !== 'sing_state') return null;

  const occurrenceId = stringField(value, 'occurrence_id');
  const title = stringField(value, 'title');
  const artist = stringField(value, 'artist');
  const positionMs = numberField(value, 'position_ms');
  const playing = booleanField(value, 'playing');

  if (
    occurrenceId === null ||
    title === null ||
    artist === null ||
    positionMs === null ||
    playing === null
  ) {
    return null;
  }

  return { occurrenceId, title, artist, positionMs, playing };
}

export function singPageClockMs(
  state: SingPageState,
  receivedAtMs: number,
  nowMs: number,
): number {
  if (!state.playing) return state.positionMs;

  return state.positionMs + Math.max(0, nowMs - receivedAtMs);
}

export function nextSingLine(
  lines: LyricLine[],
  positionMs: number,
): LyricLine | null {
  return (
    lines.find(
      (line) => line.endMs > line.startMs && line.startMs > positionMs,
    ) ?? null
  );
}
