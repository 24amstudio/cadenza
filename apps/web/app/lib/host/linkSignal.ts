export const signalBarCount = 4;

// Bars follow the round trip to Cadenza Host, which is what a control waits for. A link with no clock reply yet shows one
// bar, and a link that is down shows none.
export function signalBars(link: {
  connected: boolean;
  roundTripMs: number | null;
}): number {
  if (!link.connected) return 0;

  if (link.roundTripMs === null) return 1;

  if (link.roundTripMs <= 80) return 4;

  if (link.roundTripMs <= 200) return 3;

  if (link.roundTripMs <= 500) return 2;

  return 1;
}
