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

// The last word that has started. Provider timings can overlap, so an earlier word may still be ending.
function latestStartedWord(words: LyricWord[], positionMs: number): number {
  let latest = -1;

  for (let index = 0; index < words.length; index += 1) {
    const word = words[index];

    if (
      word !== undefined &&
      word.endMs > word.startMs &&
      word.startMs <= positionMs
    ) {
      latest = index;
    }
  }

  return latest;
}

// Fill for each word of a line, as a percentage. Only one word on screen sweeps at a time: the latest started word of the
// newest active line. Earlier words are sung, later words are not, and every other line shows whole words.
export function wordFills(
  line: LyricLine,
  positionMs: number,
  sweeping: boolean,
): number[] {
  const latest = latestStartedWord(line.words, positionMs);

  return line.words.map((word, index) => {
    if (!sweeping) return word.startMs <= positionMs ? 100 : 0;

    if (index === latest) return wordFillPercent(word, positionMs);

    return index < latest ? 100 : 0;
  });
}
