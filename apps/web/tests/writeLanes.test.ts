import { describe, expect, test } from 'bun:test';
import { laneOf, WriteQueue } from '../app/lib/host/writeLanes';

describe('Bluetooth write lanes', () => {
  test('a control frame is written before the bulk frames already waiting', () => {
    const queue = new WriteQueue<string>();

    queue.push('bulk', 'artwork-1');
    queue.push('bulk', 'artwork-2');
    queue.push('control', 'command');
    queue.push('bulk', 'artwork-3');

    expect([queue.next(), queue.next(), queue.next(), queue.next()]).toEqual([
      'command',
      'artwork-1',
      'artwork-2',
      'artwork-3',
    ]);
    expect(queue.isEmpty).toBe(true);
  });

  test('frames of one lane keep their order', () => {
    const queue = new WriteQueue<string>();

    queue.push('control', 'first');
    queue.push('control', 'second');

    expect(queue.next()).toBe('first');
    expect(queue.next()).toBe('second');
  });

  test('only requests for large or optional data are bulk', () => {
    expect(laneOf('{"version":1,"type":"artwork.get","request_id":"a"}')).toBe(
      'bulk',
    );
    expect(laneOf('{"version":1,"type":"motion.get","request_id":"a"}')).toBe(
      'bulk',
    );
    expect(laneOf('{"version":1,"type":"lyrics.get","request_id":"a"}')).toBe(
      'bulk',
    );
    expect(laneOf('{"version":1,"type":"command","command_id":"c"}')).toBe(
      'control',
    );
    expect(
      laneOf('{"version":1,"type":"artwork.cancel","request_id":"a"}'),
    ).toBe('control');
    expect(laneOf('{"version":1,"type":"clock","request_id":"k"}')).toBe(
      'control',
    );
    expect(laneOf('not json at all')).toBe('control');
  });
});
