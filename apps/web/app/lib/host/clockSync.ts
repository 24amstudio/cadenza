import {
  bestClockEstimate,
  type ClockEstimate,
  type ClockProbe,
} from './clock';
import { encodeClock } from '../protocol/encode';
import type { ClockSample } from '../protocol/types';
import type { Schedule } from './waiters';

// The first probes come back to back and set the offset. After that one probe runs every few seconds, so the offset
// follows the link as its round trip changes.
const probeCount = 4;
const probeIntervalMs = 5_000;

// The offset comes from the fastest round trip in this window. A slow probe carries more asymmetric queuing delay.
const windowSize = 12;

export interface ClockSyncOptions {
  send: (frame: string) => void;
  newId: () => string;
  monotonicNow: () => number;
  schedule: Schedule;
  // Called with each new estimate. The burst is done once the first probes have all returned.
  onEstimate: (estimate: ClockEstimate, burstDone: boolean) => void;
}

// Estimates the Host's monotonic clock from NTP-style probes. A deadline is measured on that clock, so commands wait for
// the first estimate, and the uncertainty tells them how much of the Host's window the link itself uses up.
export class ClockSync {
  private readonly options: ClockSyncOptions;
  private probes: ClockProbe[] = [];
  private readonly sent = new Map<string, number>();
  private cancelRefresh: (() => void) | null = null;
  private offsetMs: number | null = null;
  private uncertainty = 0;
  private roundTrip: number | null = null;

  constructor(options: ClockSyncOptions) {
    this.options = options;
  }

  get uncertaintyMs(): number {
    return this.uncertainty;
  }

  get roundTripMs(): number | null {
    return this.roundTrip;
  }

  // Milliseconds on the Host's monotonic timeline, or null until a clock estimate exists.
  hostNowMs(): number | null {
    if (this.offsetMs === null) return null;

    return this.options.monotonicNow() + this.offsetMs;
  }

  start(): void {
    this.cancelRefresh?.();
    this.probes = [];
    this.sent.clear();
    this.sendProbe();
  }

  // The link is gone, so the estimate no longer describes any Host.
  stop(): void {
    this.cancelRefresh?.();
    this.cancelRefresh = null;
    this.sent.clear();
    this.offsetMs = null;
  }

  receive(requestId: string, sample: ClockSample): void {
    const sentAtRemoteMs = this.sent.get(requestId);
    this.sent.delete(requestId);

    if (sentAtRemoteMs === undefined) return;
    this.probes.push({
      sentAtRemoteMs,
      receivedAtRemoteMs: this.options.monotonicNow(),
      receivedAtHostMs: sample.receivedAtHostMs,
      sentAtHostMs: sample.sentAtHostMs,
    });
    this.probes.splice(0, Math.max(0, this.probes.length - windowSize));
    // The first reply already gives a usable offset, so commands do not wait for the whole burst. Later probes only
    // tighten it.
    const burstDone = this.probes.length >= probeCount;
    const estimate = bestClockEstimate(this.probes);

    if (estimate !== null) {
      this.offsetMs = estimate.offsetMs;
      this.uncertainty = estimate.uncertaintyMs;
      this.roundTrip = estimate.roundTripMs;
      this.options.onEstimate(estimate, burstDone);
    }

    if (!burstDone) {
      this.sendProbe();

      return;
    }

    this.cancelRefresh?.();
    this.cancelRefresh = this.options.schedule(
      () => this.sendProbe(),
      probeIntervalMs,
    );
  }

  private sendProbe(): void {
    const requestId = this.options.newId();
    const sentAtRemoteMs = this.options.monotonicNow();
    this.sent.set(requestId, sentAtRemoteMs);
    this.options.send(encodeClock(requestId, sentAtRemoteMs));
  }
}
