import { describe, expect, test } from 'bun:test';
import { castDisplayLabel, castPresentationLabel } from '../app/lib/cast';

describe('Cast labels', () => {
  test('a device names what its screen can do without claiming it plays audio', () => {
    expect(castDisplayLabel('none')).toBe('audio only');
    expect(castDisplayLabel('display')).toBe('screen');
    expect(castDisplayLabel('unknown')).toBe('capability unknown');
  });

  test('the presentation mode reads as the Settings choice', () => {
    expect(castPresentationLabel('auto')).toBe('Auto');
    expect(castPresentationLabel('audio_only')).toBe('Audio Only');
    expect(castPresentationLabel('full_suite')).toBe('Full Cadenza Suite');
  });
});
