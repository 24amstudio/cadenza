// Host deadlines use the Host's monotonic clock. The browser estimates the offset with NTP-style probes: t0 is when the
// browser sent a probe, t1 and t2 are when the Host received and sent it, and t3 is when the browser received the reply.

export interface ClockProbe {
  sentAtRemoteMs: number;
  receivedAtRemoteMs: number;
  receivedAtHostMs: number;
  sentAtHostMs: number;
}

export interface ClockEstimate {
  offsetMs: number;
  roundTripMs: number;
}

// The probe with the shortest round trip has the least asymmetric queuing delay, so its offset is the most reliable.
export function bestClockEstimate(probes: ClockProbe[]): ClockEstimate | null {
  let best: ClockEstimate | null = null;

  for (const probe of probes) {
    const roundTripMs =
      probe.receivedAtRemoteMs -
      probe.sentAtRemoteMs -
      (probe.sentAtHostMs - probe.receivedAtHostMs);

    if (roundTripMs < 0) continue;

    const offsetMs =
      (probe.receivedAtHostMs -
        probe.sentAtRemoteMs +
        (probe.sentAtHostMs - probe.receivedAtRemoteMs)) /
      2;

    if (best === null || roundTripMs < best.roundTripMs) {
      best = { offsetMs, roundTripMs };
    }
  }

  return best;
}
