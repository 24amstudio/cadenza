import { describe, expect, test } from 'bun:test';
import {
  ArtworkCoordinator,
  type ArtworkHolder,
  type ArtworkPort,
  type ArtworkSupport,
} from '../app/lib/host/artworkCoordinator';
import type { ArtworkMode } from '../app/lib/host/client';
import { Clock } from './support/hostClient';

const url = 'https://example.com/album.jpg';
const song = { url, occurrenceId: 'occurrence-1' };

class FakePort implements ArtworkPort {
  state: ArtworkSupport = 'ready';
  motion = true;
  readonly requests: { id: string; mode: ArtworkMode; url: string }[] = [];
  readonly cancelled: string[] = [];

  support(): ArtworkSupport {
    return this.state;
  }

  supportsMotion(): boolean {
    return this.motion;
  }

  request(url: string, mode: ArtworkMode): string | null {
    const id = `request-${this.requests.length + 1}`;
    this.requests.push({ id, mode, url });

    return id;
  }

  cancel(requestId: string): void {
    this.cancelled.push(requestId);
  }

  kinds(): string[] {
    return this.requests.map((request) => request.mode.kind);
  }

  latest(): string {
    return this.requests.at(-1)?.id ?? '';
  }
}

class FakeHolder implements ArtworkHolder {
  preview = false;
  full = false;
  video = false;
  readonly unavailable: string[] = [];

  hasImage(): boolean {
    return this.preview || this.full;
  }

  hasFullImage(): boolean {
    return this.full;
  }

  hasMotion(): boolean {
    return this.video;
  }

  markUnavailable(missing: string): void {
    this.unavailable.push(missing);
  }
}

function setup() {
  const port = new FakePort();
  const holder = new FakeHolder();
  const clock = new Clock();

  const coordinator = new ArtworkCoordinator(
    port,
    holder,
    clock.schedule,
    () => clock.now,
  );

  return { port, holder, clock, coordinator };
}

describe('ArtworkCoordinator', () => {
  test('asks for the still of the playing song, and a failed still is retried until the full image replaces the preview', () => {
    const { port, holder, clock, coordinator } = setup();
    holder.preview = true;

    coordinator.setPlaying(song);
    expect(port.kinds()).toEqual(['still']);

    // The Host refuses, then the digest fails: neither leaves the cover at preview size for good.
    coordinator.artworkArrived(port.latest(), true, false);
    clock.advance(1_500);
    expect(port.kinds()).toEqual(['still', 'still']);

    coordinator.artworkArrived(port.latest(), true, false);
    clock.advance(4_000);
    expect(port.kinds()).toEqual(['still', 'still', 'still']);

    holder.full = true;
    coordinator.artworkArrived(port.latest(), true, true);
    clock.advance(60_000);

    expect(port.kinds().filter((kind) => kind === 'still')).toHaveLength(3);
    expect(holder.unavailable).toEqual([]);
  });

  test('a request the Host never answers times out and is asked for again', () => {
    const { port, clock, coordinator } = setup();

    coordinator.setPlaying(song);
    clock.advance(20_000);

    expect(port.cancelled).toEqual(['request-1']);
    clock.advance(1_500);
    expect(port.kinds()).toEqual(['still', 'still']);
  });

  test('shows the placeholder only after the retries are spent, and tries again on a later snapshot', () => {
    const { port, holder, clock, coordinator } = setup();

    coordinator.setPlaying(song);

    for (const delay of [1_500, 4_000, 10_000, 0]) {
      coordinator.artworkArrived(port.latest(), true, false);
      clock.advance(delay);
    }

    // The motion video is still worth asking for, but the cover is shown as unavailable.
    expect(port.kinds()).toEqual([
      'still',
      'still',
      'still',
      'still',
      'motion',
    ]);
    expect(holder.unavailable).toEqual([url]);

    // The next snapshot after the cooldown tries the still once more.
    coordinator.setPlaying(song);
    expect(port.kinds().filter((kind) => kind === 'still')).toHaveLength(4);
    clock.advance(60_000);
    coordinator.setPlaying(song);
    expect(port.kinds().filter((kind) => kind === 'still')).toHaveLength(5);
  });

  test('asks for motion only after the still, and a corrupt video leaves the still in place', () => {
    const { port, holder, clock, coordinator } = setup();

    coordinator.setPlaying(song);
    expect(port.kinds()).toEqual(['still']);

    holder.full = true;
    coordinator.artworkArrived(port.latest(), true, true);
    expect(port.kinds()).toEqual(['still', 'motion']);

    // One retry for a failed video, then it is dropped for this song.
    coordinator.motionArrived(port.latest(), false, false);
    clock.advance(1_500);
    expect(port.kinds()).toEqual(['still', 'motion', 'motion']);

    coordinator.motionArrived(port.latest(), false, false);
    clock.advance(60_000);
    coordinator.setPlaying(song);

    expect(port.kinds()).toEqual(['still', 'motion', 'motion']);
    expect(holder.unavailable).toEqual([]);
  });

  test('a song the Host has no motion for is not asked again', () => {
    const { port, holder, coordinator } = setup();
    holder.full = true;

    coordinator.setPlaying(song);
    coordinator.motionArrived(port.latest(), false, true);
    coordinator.setPlaying(song);
    coordinator.setPlaying(song);

    expect(port.kinds()).toEqual(['motion']);
  });

  test('asks again after a reconnect, for the song and for covers that are still missing', () => {
    const { port, coordinator } = setup();

    coordinator.wantPreview(url);
    coordinator.setPlaying(song);
    expect(port.kinds()).toEqual(['preview', 'still']);

    coordinator.disconnected();
    coordinator.connected();

    expect(port.kinds()).toEqual(['preview', 'still', 'preview', 'still']);
  });

  test('waits for the link instead of failing a request made before it is ready', () => {
    const { port, coordinator } = setup();
    port.state = 'offline';

    coordinator.wantPreview(url);
    expect(port.requests).toHaveLength(0);

    port.state = 'ready';
    coordinator.connected();

    expect(port.kinds()).toEqual(['preview']);
  });

  test('abandons the old motion when another song starts, and gives the new one a fresh try', () => {
    const { port, holder, coordinator } = setup();
    holder.full = true;

    coordinator.setPlaying(song);
    const oldMotion = port.latest();

    coordinator.setPlaying({ url, occurrenceId: 'occurrence-2' });

    expect(port.cancelled).toEqual([oldMotion]);
    expect(port.kinds()).toEqual(['motion', 'motion']);
  });

  test('a Host without artwork marks the cover unavailable without asking', () => {
    const { port, holder, coordinator } = setup();
    port.state = 'unsupported';

    coordinator.setPlaying(song);

    expect(port.requests).toHaveLength(0);
    expect(holder.unavailable).toEqual([url]);
  });
});

describe('ArtworkCoordinator prefetch', () => {
  test('the next cover is asked for only once the playing cover is settled', () => {
    const port = new FakePort();
    const clock = new Clock();
    const loaded = new Set<string>();

    const holder: ArtworkHolder = {
      hasImage: (address) => loaded.has(address),
      hasFullImage: (address) => loaded.has(address),
      hasMotion: () => false,
      markUnavailable: () => {},
    };

    const coordinator = new ArtworkCoordinator(
      port,
      holder,
      clock.schedule,
      () => clock.now,
    );

    const next = 'https://example.com/next.jpg';

    coordinator.setPlaying(song);
    coordinator.prefetch(next);

    expect(port.requests.some((request) => request.url === next)).toBe(false);

    loaded.add(url);
    coordinator.artworkArrived(port.latest(), true, true);

    coordinator.prefetch(next);

    expect(port.requests.some((request) => request.url === next)).toBe(true);
  });
});
