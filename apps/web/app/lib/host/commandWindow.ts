// Host authorization (apps/host/storage/authorize-command.sql) refuses a command whose deadline is already past
// (expired) or more than this far ahead of the Host's clock (invalid_deadline). The deadline is the whole budget for the
// frame to cross the link, wait for Music's lock, and be read back, so it uses the widest window the Host accepts.
const hostDeadlineLimitMs = 1_000;

// Rounding and the Host's own clock granularity. Without it a deadline asked for at the limit can land past it.
const safetyMarginMs = 25;

// A link this uncertain cannot meet any deadline. The floor keeps the deadline in the future rather than past.
const minimumWindowMs = 150;

// The clock uncertainty is how far the estimated Host time can be ahead of the real one, so the window gives that up.
export function commandWindowMs(uncertaintyMs: number): number {
  return Math.max(
    minimumWindowMs,
    hostDeadlineLimitMs - safetyMarginMs - Math.max(0, uncertaintyMs),
  );
}

export function commandExpiryMs(
  hostNowMs: number,
  uncertaintyMs: number,
): number {
  return Math.max(0, Math.round(hostNowMs + commandWindowMs(uncertaintyMs)));
}
