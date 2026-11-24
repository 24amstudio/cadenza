import { describe, expect, test } from 'bun:test';
import { qualityLabel } from '../app/lib/playback';
import { decodeSnapshot } from '../app/lib/protocol/decode';
import type { JsonObject } from '../app/lib/protocol/json';

const snapshot: JsonObject = {
  host_id: 'host',
  host_epoch: 'epoch',
  revision: 1,
  sequence: 1,
  playing: true,
  volume: 50,
  synchronized: true,
  shuffle: false,
  repeat: 'off',
  queue: [],
};

describe('AAC audio tier', () => {
  test('a snapshot that reports AAC keeps it and labels it', () => {
    const decoded = decodeSnapshot({ ...snapshot, quality: 'aac' });

    expect(decoded?.quality).toBe('aac');
    expect(decoded && qualityLabel(decoded.quality)).toBe('AAC');
  });
});
