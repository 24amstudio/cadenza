import type { LyricDocument, LyricLine, LyricWord } from './protocol/types';

// 0: no lyrics, 1: untimed lines, 2: timed lines, 3: timed lines with per-word timing.
export type LyricsLevel = 0 | 1 | 2 | 3;

export function lyricsLevel(document: LyricDocument | null): LyricsLevel {
  if (document === null || document.lines.length === 0) return 0;
  const timed = document.lines.some((line) => line.endMs > line.startMs);

  if (!timed) return 1;
  const wordTimed = document.lines.some((line) => line.words.length > 0);

  return wordTimed ? 3 : 2;
}

// Background vocals are timed as separate lines that overlap their main line, so every line sounding at this position
// is active. Provider end markers can leave short gaps between lines. Then the most recently started line stays active,
// so the highlight and the scroll never drop out with playback. Cadenza Remote uses the same rule.
export function activeLineIndices(
  lines: LyricLine[],
  positionMs: number,
): number[] {
  const sounding: number[] = [];
  let latest = -1;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];

    if (
      line === undefined ||
      line.endMs <= line.startMs ||
      line.startMs > positionMs
    ) {
      continue;
    }

    latest = index;

    if (positionMs < line.endMs) sounding.push(index);
  }

  if (sounding.length > 0) return sounding;

  return latest >= 0 ? [latest] : [];
}

function wordFillPercent(word: LyricWord, positionMs: number): number {
  if (positionMs <= word.startMs) return 0;

  if (positionMs >= word.endMs) return 100;

  return ((positionMs - word.startMs) / (word.endMs - word.startMs)) * 100;
}

// A word sweeps while the position is inside it. Provider timings can overlap, so several words of one line, and words
// of several lines, can be inside their span at the same moment.
function isSounding(word: LyricWord, positionMs: number): boolean {
  return word.startMs <= positionMs && positionMs < word.endMs;
}

// Fill for each word of a line, as a percentage. On a line that is sounding, every word fills from its own timing, so
// words that overlap each sweep together instead of one stealing the animation from the other. Any other line shows
// whole words: sung, or not yet.
export function wordFills(
  line: LyricLine,
  positionMs: number,
  sweeping: boolean,
): number[] {
  return line.words.map((word) => {
    if (!sweeping) return word.startMs <= positionMs ? 100 : 0;

    return wordFillPercent(word, positionMs);
  });
}

// Every word that sweeps now, across every active line. Overlapping lines, such as a second voice or background vocals,
// each keep their own sweep. The view animates exactly these words.
export function sweepTargets(
  lines: LyricLine[],
  positionMs: number,
): { line: number; word: number }[] {
  const targets: { line: number; word: number }[] = [];

  for (const lineIndex of activeLineIndices(lines, positionMs)) {
    lines[lineIndex]?.words.forEach((word, wordIndex) => {
      if (isSounding(word, positionMs)) {
        targets.push({ line: lineIndex, word: wordIndex });
      }
    });
  }

  return targets;
}

// Width of the soft edge on the sweeping word, as a percentage of the word. It is widest halfway through the word and
// zero at both ends, so a word that has not started or has finished has a hard edge.
const sweepEdgePercent = 12;

export function sweepEdgeWidth(fill: number): number {
  return sweepEdgePercent * (1 - Math.abs(fill / 50 - 1));
}
