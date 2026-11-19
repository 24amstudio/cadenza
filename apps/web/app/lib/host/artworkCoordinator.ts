import type { ArtworkMode } from './client';
import { traceEvent } from './trace';
import type { Schedule } from './waiters';

type LaneKind = 'preview' | 'still' | 'motion';

// idle: nothing in flight. inflight: asked, waiting. backoff: failed, a retry is scheduled. done: delivered. failed: out of
// retries. none: the Host has nothing to send, which is final until the next song or a reconnect.
type LaneStatus = 'idle' | 'inflight' | 'backoff' | 'done' | 'failed' | 'none';

interface Lane {
  kind: LaneKind;
  url: string;
  occurrenceId: string | null;
  requestId: string | null;
  attempts: number;
  status: LaneStatus;
  failedAtMs: number;
  cancelTimer: (() => void) | null;
}

export type ArtworkSupport = 'ready' | 'unsupported' | 'offline';

export interface ArtworkPort {
  support(): ArtworkSupport;
  supportsMotion(): boolean;
  // The request ID, or null when it could not be sent.
  request(url: string, mode: ArtworkMode): string | null;
  cancel(requestId: string): void;
}

// What the page already holds, and where a final failure is shown.
export interface ArtworkHolder {
  hasImage(url: string): boolean;
  hasFullImage(url: string): boolean;
  hasMotion(url: string): boolean;
  // No image will arrive for this URL, so the placeholder replaces the loading state.
  markUnavailable(url: string): void;
}

export interface PlayingArtwork {
  url: string | null;
  occurrenceId: string;
}

// A request that gets no answer is abandoned, so one dropped frame cannot leave the cover small for the whole song.
const timeoutMs: Record<LaneKind, number> = {
  preview: 10_000,
  still: 20_000,
  motion: 40_000,
};

const retryDelaysMs = [1_500, 4_000, 10_000];

const maximumRetries: Record<LaneKind, number> = {
  preview: 3,
  still: 3,
  motion: 1,
};

// A lane that ran out of retries is tried again on the next snapshot or row after this long.
const failedCooldownMs = 60_000;

// Decides what artwork to ask the Host for, and asks again when a request fails, times out, or the link drops. The still
// image is always requested for the playing song, apart from its motion video: the Host sends motion in place of nothing
// else, so a refused or corrupt video can never leave the cover at preview size.
export class ArtworkCoordinator {
  private readonly port: ArtworkPort;
  private readonly holder: ArtworkHolder;
  private readonly schedule: Schedule;
  private readonly now: () => number;
  private readonly lanes = new Map<string, Lane>();
  private readonly byRequest = new Map<string, Lane>();
  private readonly wantedPreviews = new Set<string>();
  private playing: PlayingArtwork | null = null;

  constructor(
    port: ArtworkPort,
    holder: ArtworkHolder,
    schedule: Schedule,
    now: () => number,
  ) {
    this.port = port;
    this.holder = holder;
    this.schedule = schedule;
    this.now = now;
  }

  // A row or cover that shows this URL. It is requested again after a reconnect until an image exists.
  wantPreview(url: string): void {
    this.wantedPreviews.add(url);
    this.ensure(this.lane('preview', url, null));
  }

  // Called with every snapshot, so a song whose request failed or never started is retried without waiting for a change.
  setPlaying(song: PlayingArtwork | null): void {
    const previous = this.playing;
    this.playing = song;

    if (previous?.occurrenceId !== song?.occurrenceId) this.songChanged(song);

    if (song === null || song.url === null) return;
    const still = this.lane('still', song.url, song.occurrenceId);

    this.ensure(still);

    // Motion waits for the still, so the two never compete for a slow link.
    if (this.settled(still)) {
      this.ensure(this.lane('motion', song.url, song.occurrenceId));
    }
  }

  connected(): void {
    this.dropRequests();

    for (const lane of this.lanes.values()) {
      lane.status = 'idle';
      lane.attempts = 0;
    }

    for (const url of [...this.wantedPreviews]) {
      if (this.holder.hasImage(url)) this.wantedPreviews.delete(url);
      else this.ensure(this.lane('preview', url, null));
    }

    if (this.playing !== null) this.setPlaying(this.playing);
  }

  disconnected(): void {
    this.dropRequests();

    for (const lane of this.lanes.values()) {
      if (lane.status === 'inflight' || lane.status === 'backoff') {
        lane.status = 'idle';
      }
    }
  }

  // An artwork frame for a request. A preview frame, a full image, or a failure.
  artworkArrived(
    requestId: string | null,
    full: boolean,
    hasImage: boolean,
  ): void {
    const lane = requestId === null ? undefined : this.byRequest.get(requestId);

    if (lane === undefined) return;

    if (hasImage && (full || lane.kind === 'preview')) {
      this.finish(lane, 'done');
    } else if (full) {
      this.fail(lane, 'failed');
    }
  }

  motionArrived(
    requestId: string | null,
    verified: boolean,
    unavailable: boolean,
  ): void {
    const lane = requestId === null ? undefined : this.byRequest.get(requestId);

    if (lane === undefined) return;

    if (verified) this.finish(lane, 'done');
    else if (unavailable) this.finish(lane, 'none');
    else this.fail(lane, 'failed');
  }

  private lane(kind: LaneKind, url: string, occurrenceId: string | null): Lane {
    const key = `${kind}|${url}`;
    let lane = this.lanes.get(key);

    if (lane === undefined) {
      lane = {
        kind,
        url,
        occurrenceId,
        requestId: null,
        attempts: 0,
        status: 'idle',
        failedAtMs: 0,
        cancelTimer: null,
      };
      this.lanes.set(key, lane);
    }

    lane.occurrenceId = occurrenceId ?? lane.occurrenceId;

    return lane;
  }

  private satisfied(lane: Lane): boolean {
    switch (lane.kind) {
      case 'preview':
        return this.holder.hasImage(lane.url);
      case 'still':
        return this.holder.hasFullImage(lane.url);
      case 'motion':
        return this.holder.hasMotion(lane.url);
    }
  }

  private settled(lane: Lane): boolean {
    return (
      this.satisfied(lane) ||
      lane.status === 'failed' ||
      lane.status === 'none' ||
      lane.status === 'done'
    );
  }

  private ensure(lane: Lane): void {
    if (this.satisfied(lane)) {
      lane.status = 'done';
      this.wantedPreviews.delete(lane.url);

      return;
    }

    // Done, but the page no longer holds it, such as an image evicted to bound memory.
    if (lane.status === 'done') lane.status = 'idle';

    if (lane.status === 'failed') {
      if (this.now() - lane.failedAtMs < failedCooldownMs) return;
      lane.status = 'idle';
      lane.attempts = 0;
    }

    if (lane.status === 'idle') this.start(lane);
  }

  private start(lane: Lane): void {
    const support = this.port.support();

    if (support === 'offline') return;

    if (support === 'unsupported' || !this.laneSupported(lane)) {
      this.finish(lane, lane.kind === 'motion' ? 'none' : 'failed');

      return;
    }

    const mode = this.modeFor(lane);
    const requestId = this.port.request(lane.url, mode);

    if (requestId === null) return;
    lane.requestId = requestId;
    lane.status = 'inflight';
    this.byRequest.set(requestId, lane);
    lane.cancelTimer = this.schedule(
      () => this.timedOut(lane),
      timeoutMs[lane.kind],
    );
  }

  private laneSupported(lane: Lane): boolean {
    return lane.kind !== 'motion' || this.port.supportsMotion();
  }

  private modeFor(lane: Lane): ArtworkMode {
    if (lane.kind === 'preview') return { kind: 'preview' };

    if (lane.kind === 'still') return { kind: 'still' };

    return { kind: 'motion', occurrenceId: lane.occurrenceId ?? '' };
  }

  private timedOut(lane: Lane): void {
    lane.cancelTimer = null;

    if (lane.requestId !== null) this.port.cancel(lane.requestId);
    traceEvent(`artwork ${lane.kind} timed out`, { attempts: lane.attempts });
    // A video that cannot finish in time on this link will not finish on a second try.
    this.fail(lane, lane.kind === 'motion' ? 'none' : 'failed');
  }

  private release(lane: Lane): void {
    lane.cancelTimer?.();
    lane.cancelTimer = null;

    if (lane.requestId !== null) this.byRequest.delete(lane.requestId);
    lane.requestId = null;
  }

  private finish(lane: Lane, status: 'done' | 'none' | 'failed'): void {
    this.release(lane);
    lane.status = status;
    lane.attempts = 0;

    if (status === 'failed') {
      lane.failedAtMs = this.now();
      this.giveUp(lane);
    }

    if (lane.kind === 'still') this.afterStill();
  }

  private fail(lane: Lane, outcome: 'failed' | 'none'): void {
    this.release(lane);
    lane.attempts += 1;
    traceEvent(`artwork ${lane.kind} failed`, {
      attempts: lane.attempts,
      outcome,
    });

    if (outcome === 'none') {
      this.finish(lane, 'none');

      return;
    }

    if (lane.attempts > maximumRetries[lane.kind]) {
      // A video that keeps failing is dropped for this song. The still is what the page cannot do without.
      this.finish(lane, lane.kind === 'motion' ? 'none' : 'failed');

      return;
    }

    lane.status = 'backoff';
    lane.cancelTimer = this.schedule(
      () => {
        lane.cancelTimer = null;
        lane.status = 'idle';

        if (this.relevant(lane)) this.ensure(lane);
      },
      retryDelaysMs[lane.attempts - 1] ?? 10_000,
    );
  }

  // A still or motion retry is for the song that is playing. A preview retry is for a cover someone still shows.
  private relevant(lane: Lane): boolean {
    if (lane.kind === 'preview') return this.wantedPreviews.has(lane.url);

    return (
      this.playing?.url === lane.url &&
      (lane.kind === 'still' || this.playing.occurrenceId === lane.occurrenceId)
    );
  }

  private giveUp(lane: Lane): void {
    if (lane.kind !== 'motion' && !this.holder.hasImage(lane.url)) {
      this.holder.markUnavailable(lane.url);
    }
  }

  // The still of the playing song settled, so its motion may start now.
  private afterStill(): void {
    if (this.playing !== null) this.setPlaying(this.playing);
  }

  // A new song: abandon what the old one was waiting for and give this one a fresh try at everything.
  private songChanged(song: PlayingArtwork | null): void {
    for (const lane of this.lanes.values()) {
      if (lane.kind === 'preview') continue;

      const sameStill = lane.kind === 'still' && lane.url === song?.url;

      if (sameStill) {
        lane.occurrenceId = song.occurrenceId;
      } else if (lane.status === 'inflight' || lane.status === 'backoff') {
        if (lane.requestId !== null) this.port.cancel(lane.requestId);
        this.release(lane);
        lane.status = 'idle';
      }

      if (lane.url === song?.url && lane.status === 'none') {
        lane.status = 'idle';
      }

      if (lane.url === song?.url && lane.status === 'failed') {
        lane.status = 'idle';
        lane.attempts = 0;
      }
    }
  }

  private dropRequests(): void {
    for (const lane of this.lanes.values()) this.release(lane);
    this.byRequest.clear();
  }
}
