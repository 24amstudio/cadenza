import { describe, expect, test } from 'bun:test';
import type { BluetoothLink } from '../app/lib/host/bluetooth';
import {
  reconnectWithRetries,
  silentReconnectDelaysMs,
} from '../app/lib/host/bluetoothReconnect';

const link: BluetoothLink = {
  deviceId: 'device-1',
  socket: {
    onOpen: null,
    onMessage: null,
    onClose: null,
    send: () => undefined,
    close: () => undefined,
  },
};

describe('silent Bluetooth reconnect', () => {
  test('keeps trying while the Host is still starting, then links', async () => {
    const waits: number[] = [];
    let attempts = 0;

    const result = await reconnectWithRetries(
      async () => {
        attempts += 1;

        return attempts < 3 ? null : link;
      },
      async (delayMs) => {
        waits.push(delayMs);
      },
    );

    expect(result).toBe(link);
    expect(waits).toEqual(silentReconnectDelaysMs.slice(0, 2));
  });

  test('a failed GATT connection counts as a failed attempt, and the retries stop after the last delay', async () => {
    const waits: number[] = [];
    let attempts = 0;

    const result = await reconnectWithRetries(
      async () => {
        attempts += 1;

        throw new Error('GATT server is not reachable');
      },
      async (delayMs) => {
        waits.push(delayMs);
      },
    );

    expect(result).toBeNull();
    expect(attempts).toBe(silentReconnectDelaysMs.length + 1);
    expect(waits).toEqual(silentReconnectDelaysMs);
  });
});
