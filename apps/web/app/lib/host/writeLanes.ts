// Frames the page writes over Bluetooth, in two lanes. A control frame (a command, a transport action, a search, a clock
// probe) is written before any bulk frame, so a user's tap is not held behind an artwork or lyrics request. A frame is
// never split: the lane is chosen again at each frame boundary.

export type WriteLane = 'control' | 'bulk';

// Requests for large or optional data. They can wait for control traffic, and they are asked for again when they are
// needed, so they lose nothing by waiting.
const bulkTypes = new Set([
  'artwork.get',
  'motion.get',
  'lyrics.get',
  'browse.get',
  'log.report',
]);

export function laneOf(text: string): WriteLane {
  const type = /"type":"([^"]{1,64})"/.exec(text.slice(0, 96))?.[1];

  return type !== undefined && bulkTypes.has(type) ? 'bulk' : 'control';
}

export class WriteQueue<T> {
  private readonly control: T[] = [];
  private readonly bulk: T[] = [];

  push(lane: WriteLane, item: T): void {
    if (lane === 'control') this.control.push(item);
    else this.bulk.push(item);
  }

  // The next frame to write: control first, each lane in the order its frames were queued.
  next(): T | undefined {
    return this.control.shift() ?? this.bulk.shift();
  }

  get isEmpty(): boolean {
    return this.control.length === 0 && this.bulk.length === 0;
  }
}
