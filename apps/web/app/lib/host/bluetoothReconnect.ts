import type { BluetoothLink } from './bluetooth';
import { traceEvent } from './trace';

// A silent reconnect can miss while the Host is still starting its service or the radio is busy. The page tries again
// before it asks the user to choose the Host, and the attempts are bounded so a Host that is off does not spin forever.
export const silentReconnectDelaysMs = [1_000, 2_000, 4_000, 8_000];

export async function reconnectWithRetries(
  attempt: () => Promise<BluetoothLink | null>,
  wait: (delayMs: number) => Promise<void> = sleep,
): Promise<BluetoothLink | null> {
  for (let index = 0; index <= silentReconnectDelaysMs.length; index += 1) {
    if (index > 0) await wait(silentReconnectDelaysMs[index - 1] ?? 0);

    try {
      const link = await attempt();

      if (link !== null) return link;
    } catch (error) {
      traceEvent('bluetooth: silent reconnect attempt failed', {
        attempt: index + 1,
        error,
      });
    }
  }

  return null;
}

function sleep(delayMs: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, delayMs));
}
