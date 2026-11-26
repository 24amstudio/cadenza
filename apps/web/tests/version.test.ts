import { describe, expect, test } from 'bun:test';
import { isOlderRelease } from '../app/lib/version';

describe('release ordering', () => {
  test('a bundle is older only when its release is older than the Host', () => {
    expect(isOlderRelease('0.3.3', '0.3.4')).toBe(true);
    expect(isOlderRelease('0.3.4', '0.3.4')).toBe(false);
    expect(isOlderRelease('0.3.4', '0.3.3')).toBe(false);
  });

  test('the build date and number order releases that share a version', () => {
    expect(
      isOlderRelease(
        '0.3.4_20261123.466-aaaaaaaaaaaa',
        '0.3.4_20261124.467-bbbbbbbbbbbb',
      ),
    ).toBe(true);
    expect(
      isOlderRelease(
        '0.3.4_20261124.468-aaaaaaaaaaaa',
        '0.3.4_20261124.467-bbbbbbbbbbbb',
      ),
    ).toBe(false);
  });

  test('a value that does not parse is treated as the oldest release', () => {
    expect(isOlderRelease('development', '0.3.4')).toBe(true);
    expect(isOlderRelease('0.3.4', 'development')).toBe(false);
  });
});
