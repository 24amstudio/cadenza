import type { LyricDocument, LyricLine } from './protocol/types';

// 0: no lyrics, 1: untimed lines, 2: timed lines, 3: timed lines with per-word timing.
export type LyricsLevel = 0 | 1 | 2 | 3;

export function lyricsLevel(document: LyricDocument | null): LyricsLevel {
  if (document === null || document.lines.length === 0) return 0;
  const timed = document.lines.some((line) => line.endMs > line.startMs);

  if (!timed) return 1;
  const wordTimed = document.lines.some((line) => line.words.length > 0);

  return wordTimed ? 3 : 2;
}

// Lines are sorted by start time. The active line is the last one that has started, so the highlight never lags
// behind playback and the first line is active from its start time onward.
export function activeLineIndex(
  lines: LyricLine[],
  positionMs: number,
): number {
  let active = -1;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];

    if (line !== undefined && line.startMs <= positionMs) active = index;
    else break;
  }

  return active;
}

export function activeWordIndex(line: LyricLine, positionMs: number): number {
  let active = -1;

  for (let index = 0; index < line.words.length; index += 1) {
    const word = line.words[index];

    if (word !== undefined && word.startMs <= positionMs) active = index;
    else break;
  }

  return active;
}
