import { describe, expect, test } from 'bun:test';
import { signalBars } from '../app/lib/host/linkSignal';

describe('signalBars', () => {
  test('a quick link shows all bars and a slow one shows fewer', () => {
    const at = (roundTripMs: number) =>
      signalBars({ connected: true, roundTripMs });

    expect(at(40)).toBe(4);
    expect(at(150)).toBe(3);
    expect(at(300)).toBe(2);
    expect(at(900)).toBe(1);
  });

  test('no clock reply yet shows one bar, and a dropped link shows none', () => {
    expect(signalBars({ connected: true, roundTripMs: null })).toBe(1);
    expect(signalBars({ connected: false, roundTripMs: 40 })).toBe(0);
  });
});
