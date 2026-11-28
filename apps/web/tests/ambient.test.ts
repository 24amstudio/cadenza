import { describe, expect, test } from 'bun:test';
import { defaultAmbientMode, parseAmbientMode } from '../app/lib/ambient';

describe('ambient mode', () => {
  test('a saved mode is kept', () => {
    expect(parseAmbientMode('basic')).toBe('basic');
    expect(parseAmbientMode('alive')).toBe('alive');
  });

  test('a missing or unknown saved mode falls back to the default', () => {
    expect(parseAmbientMode(null)).toBe(defaultAmbientMode);
    expect(parseAmbientMode('neon')).toBe(defaultAmbientMode);
  });
});
