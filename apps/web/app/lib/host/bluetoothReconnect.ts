import type { BluetoothLink } from './bluetooth';
import { traceEvent } from './trace';

// A silent reconnect can miss while the Host is still starting its service or the radio is busy. The page tries again
// before it asks the user to choose the Host, and the attempts are bounded so a Host that is off does not spin forever.
export const silentReconnectDelaysMs = [1_000, 2_000, 4_000, 8_000];

// Up to a quarter more, so several pages that lost the Host together do not all retry at the same instant.
export function jitteredDelayMs(
  delayMs: number,
  random: () => number = Math.random,
): number {
  return Math.round(delayMs * (1 + random() * 0.25));
}

export async function reconnectWithRetries(
  attempt: () => Promise<BluetoothLink | null>,
  wait: (delayMs: number) => Promise<void> = sleep,
  random: () => number = Math.random,
): Promise<BluetoothLink | null> {
  for (let index = 0; index <= silentReconnectDelaysMs.length; index += 1) {
    if (index > 0) {
      await wait(
        jitteredDelayMs(silentReconnectDelaysMs[index - 1] ?? 0, random),
      );
    }

    try {
      const link = await attempt();

      if (link !== null) return link;
    } catch (error) {
      traceEvent('bluetooth: silent reconnect attempt failed', {
        attempt: index + 1,
        error:
          error instanceof Error
            ? { name: error.name, message: error.message }
            : 'unknown error',
      });
    }
  }

  return null;
}

function sleep(delayMs: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, delayMs));
}
