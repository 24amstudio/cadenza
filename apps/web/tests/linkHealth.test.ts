import { describe, expect, test } from 'bun:test';
import {
  jitterMs,
  receiverLinkBars,
  streamSignalBars,
} from '../app/lib/remoteAudio/linkHealth';

const steady = { jitterMs: 1, dropoutMs60s: 0, hostDroppedFrames60s: 0 };

describe('receiver link bars', () => {
  test('jitter needs three round trips, and its spread is the standard deviation', () => {
    expect(jitterMs([2, 8])).toBeNull();
    expect(jitterMs([4, 4, 4, 4])).toBe(0);
    expect(jitterMs([2, 8, 2, 8])).toBe(3);
  });

  test('a steady stream keeps all four bars', () => {
    expect(streamSignalBars(steady)).toBe(4);
  });

  test('RTT jitter, audio dropouts, and Host drops each lower the bars', () => {
    expect(streamSignalBars({ ...steady, jitterMs: 8 })).toBe(2);
    expect(streamSignalBars({ ...steady, dropoutMs60s: 40 })).toBe(2);
    expect(streamSignalBars({ ...steady, hostDroppedFrames60s: 5 })).toBe(2);
  });

  test('the weakest measure sets the bars, and the control link can still lower them', () => {
    expect(
      streamSignalBars({
        jitterMs: 8,
        dropoutMs60s: 200,
        hostDroppedFrames60s: 0,
      }),
    ).toBe(1);
    expect(receiverLinkBars(2, steady)).toBe(2);
    expect(receiverLinkBars(4, { ...steady, dropoutMs60s: 200 })).toBe(1);
  });

  test('without stream health the control link alone sets the bars', () => {
    expect(receiverLinkBars(3, null)).toBe(3);
  });
});
