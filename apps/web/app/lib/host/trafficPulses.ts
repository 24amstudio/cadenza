import { ref, type Ref } from 'vue';

// Frames pass through the client many times a second, so each direction pulses at most once per interval. A pulse is a
// counter that the sidebar's arrow animates from, so no timer runs per frame.
const pulseIntervalMs = 100;

export class TrafficPulses {
  readonly incoming: Ref<number> = ref(0);
  readonly outgoing: Ref<number> = ref(0);
  private lastIncoming = Number.NEGATIVE_INFINITY;
  private lastOutgoing = Number.NEGATIVE_INFINITY;

  record(direction: 'in' | 'out', now: number): void {
    if (direction === 'in') {
      if (now - this.lastIncoming < pulseIntervalMs) return;

      this.lastIncoming = now;
      this.incoming.value += 1;

      return;
    }

    if (now - this.lastOutgoing < pulseIntervalMs) return;

    this.lastOutgoing = now;
    this.outgoing.value += 1;
  }
}
