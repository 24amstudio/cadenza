import { describe, expect, test } from 'bun:test';
import {
  decodeSingPageState,
  nextSingLine,
  singPageClockMs,
} from '../app/lib/sing/singPage';
import type { JsonObject } from '../app/lib/protocol/json';
import type { LyricLine } from '../app/lib/protocol/types';

function wire(overrides: JsonObject = {}): string {
  return JSON.stringify({
    type: 'sing_state',
    occurrence_id: 'occurrence-1',
    title: 'Song',
    artist: 'Artist',
    position_ms: 12_000,
    playing: true,
    ...overrides,
  });
}

function line(startMs: number, endMs: number, text: string): LyricLine {
  return {
    id: text,
    text,
    startMs,
    endMs,
    translation: null,
    words: [],
    align: 'start',
  };
}

describe('the Sing window state', () => {
  test('decodes the playing song and its lyric clock', () => {
    expect(decodeSingPageState(wire())).toEqual({
      occurrenceId: 'occurrence-1',
      title: 'Song',
      artist: 'Artist',
      positionMs: 12_000,
      playing: true,
    });
  });

  test('accepts a clock before the first line, which lip sync can produce', () => {
    expect(decodeSingPageState(wire({ position_ms: -250 }))?.positionMs).toBe(
      -250,
    );
  });

  test('refuses another message type, a missing field, or a wrong type', () => {
    expect(decodeSingPageState(wire({ type: 'lyrics' }))).toBeNull();
    expect(decodeSingPageState(wire({ playing: 'yes' }))).toBeNull();
    expect(decodeSingPageState(wire({ occurrence_id: null }))).toBeNull();
    expect(decodeSingPageState('not json')).toBeNull();
  });
});

describe('the Sing window clock', () => {
  const state = {
    occurrenceId: 'occurrence-1',
    title: 'Song',
    artist: 'Artist',
    positionMs: 12_000,
    playing: true,
  };

  test('moves a playing song on from the moment its state arrived', () => {
    expect(singPageClockMs(state, 1_000, 1_750)).toBe(12_750);
  });

  test('holds a paused song where the Host left it', () => {
    expect(singPageClockMs({ ...state, playing: false }, 1_000, 9_000)).toBe(
      12_000,
    );
  });

  test('never runs backwards when the clock reads earlier than the arrival', () => {
    expect(singPageClockMs(state, 1_000, 400)).toBe(12_000);
  });
});

describe('the next line', () => {
  const lines = [
    line(1_000, 2_000, 'first'),
    line(2_000, 2_000, 'untimed'),
    line(3_000, 4_000, 'second'),
  ];

  test('is the first timed line that has not started', () => {
    expect(nextSingLine(lines, 500)?.text).toBe('first');
    expect(nextSingLine(lines, 1_500)?.text).toBe('second');
  });

  test('is absent once every timed line has started', () => {
    expect(nextSingLine(lines, 3_500)).toBeNull();
  });
});
