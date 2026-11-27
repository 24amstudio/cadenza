// Maps the Host's playout instants onto this page's AudioContext timeline. The Host's `REMOTE_AUDIO_SYNC` gives the
// Remote clock minus the Host clock at the moment the message was sent. The Remote takes that as valid when the message
// arrives, and extrapolates with the reported drift. Both clocks count microseconds, and the Remote uses the page's
// `performance.now()` base.

/** The clock relation from the latest sync message. */
export interface ClockFix {
  /** Remote clock minus Host clock, in microseconds. */
  offsetUs: number;
  /** The drift between the two crystals, in parts per million. */
  driftPpm: number;
  /** The Remote's `performance.now()` in microseconds when the message arrived. */
  arrivedAtRemoteUs: number;
}

/** A pair from `AudioContext.getOutputTimestamp()`, relating the context clock to `performance.now()` in milliseconds. */
export interface OutputTimestamp {
  contextTime: number;
  performanceTime: number;
}

/** The Remote clock reading for one Host instant, in microseconds. */
export function remoteUsForHost(hostUs: number, fix: ClockFix): number {
  // The arrival time gives the Host time when the message was sent, because the link delay does not move the offset.
  const hostAtArrival = fix.arrivedAtRemoteUs - fix.offsetUs;

  const offsetAtHost =
    fix.offsetUs + ((hostUs - hostAtArrival) * fix.driftPpm) / 1_000_000;

  return hostUs + offsetAtHost;
}

/** The AudioContext frame at which a Host instant plays, on the frame counter a worklet also reads. */
export function contextFrameForHost(
  hostUs: number,
  fix: ClockFix,
  timestamp: OutputTimestamp,
  sampleRate: number,
): number {
  const remoteMs = remoteUsForHost(hostUs, fix) / 1_000;

  const contextTime =
    timestamp.contextTime + (remoteMs - timestamp.performanceTime) / 1_000;

  return Math.round(contextTime * sampleRate);
}
