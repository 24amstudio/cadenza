import { expect, test } from 'bun:test';
import type { ServerWebSocket } from 'bun';
import type {
  SocketWorkerInbound,
  SocketWorkerOutbound,
} from '../app/lib/remoteAudio/socketWorker';
import type { RemoteAudioStatus } from '../app/lib/remoteAudio/socketCore';
import {
  isJsonObject,
  parseJson,
  stringField,
  type JsonObject,
} from '../app/lib/protocol/json';

function audioFrame(targetPlayoutHostUs: number): Uint8Array {
  const bytes = new Uint8Array(26 + 2 * 2 * 4);
  const view = new DataView(bytes.buffer);
  bytes[0] = 0x01;
  bytes[2] = 2;
  bytes[3] = 32;
  view.setBigUint64(16, BigInt(targetPlayoutHostUs));
  view.setUint16(24, 2);

  return bytes;
}

function pingFrame(sequence: number): Uint8Array {
  const bytes = new Uint8Array(17);
  bytes[0] = 0x04;
  const view = new DataView(bytes.buffer);
  view.setBigUint64(1, BigInt(sequence));
  view.setBigUint64(9, BigInt(1_000));

  return bytes;
}

function waitFor<T>(read: () => T | undefined, timeoutMs = 3_000): Promise<T> {
  const started = Date.now();

  return new Promise((resolve, reject) => {
    const check = () => {
      const value = read();

      if (value !== undefined) return resolve(value);

      if (Date.now() - started > timeoutMs)
        return reject(new Error('timed out'));
      setTimeout(check, 10);
    };

    check();
  });
}

test('the socket worker shakes hands with the Host, answers pings, and places frames on the worklet port', async () => {
  const handshakes: JsonObject[] = [];
  const hostSockets: ServerWebSocket<unknown>[] = [];
  const pongs: Uint8Array[] = [];

  const server = Bun.serve({
    port: 0,
    fetch(request, serverInstance) {
      if (serverInstance.upgrade(request)) return undefined;

      return new Response('not a websocket', { status: 400 });
    },
    websocket: {
      open(socket) {
        hostSockets.push(socket);
      },
      message(socket, message) {
        if (message instanceof Uint8Array) {
          if (message[0] === 0x05) pongs.push(message);

          return;
        }

        {
          const parsed = parseJson(message);

          if (parsed === null || !isJsonObject(parsed)) return;

          if (stringField(parsed, 'type') !== 'REMOTE_AUDIO_HANDSHAKE') return;

          handshakes.push(parsed);
          socket.send(
            JSON.stringify({
              version: 1,
              type: 'REMOTE_AUDIO_SYNC',
              clockOffsetUs: 0,
              clockDriftPpm: 0,
              jitterBufferMs: 28,
              transmitting: true,
              networkRttMs: 4,
              processingRttMs: 0.5,
              quality: 'lossless_24_48',
              qualityReason: 'steady',
              linkHealthy: true,
            }),
          );
        }
      },
    },
  });

  const worker = new Worker(
    new URL('../app/lib/remoteAudio/socketWorker.ts', import.meta.url),
    {
      type: 'module',
    },
  );

  const statuses: Partial<RemoteAudioStatus>[] = [];
  worker.onmessage = (event: MessageEvent<SocketWorkerOutbound>) => {
    if (event.data.type === 'status') statuses.push(event.data.patch);
  };

  const channel = new MessageChannel();

  const frames: Array<{
    type: string;
    startFrame: number | undefined;
    channels: number | undefined;
  }> = [];

  channel.port2.onmessage = (
    event: MessageEvent<{
      type: string;
      startFrame?: number;
      left?: Float32Array;
      right?: Float32Array;
    }>,
  ) => {
    const data = event.data;
    frames.push({
      type: data.type,
      startFrame: data.startFrame,
      channels: data.right === undefined ? undefined : 2,
    });
  };

  const start: SocketWorkerInbound = {
    type: 'start',
    url: `ws://127.0.0.1:${server.port}/cast/live?role=remote_audio`,
    credentials: { clientId: 'remote-1', token: 'paired-token-0123456789' },
    output: { baseLatencyMs: 5, outputLatencyMs: 12, userAgent: 'test-agent' },
    port: channel.port1,
  };

  worker.postMessage(start, [channel.port1]);

  try {
    await waitFor(() => statuses.find((patch) => patch.transmitting === true));

    expect(handshakes).toHaveLength(1);
    expect(handshakes[0]?.type).toBe('REMOTE_AUDIO_HANDSHAKE');
    expect(handshakes[0]?.baseLatencyMs).toBe(5);
    expect(statuses.find((patch) => patch.socketOpen === true)).toBeDefined();
    expect(
      statuses.find((patch) => patch.quality === 'lossless_24_48'),
    ).toBeDefined();

    const epochMs = performance.timeOrigin + performance.now();

    const clock: SocketWorkerInbound = {
      type: 'clock',
      sample: { contextTime: 10, epochMs },
    };

    worker.postMessage(clock);

    const ping = hostSockets[0];
    expect(ping).toBeDefined();
    ping?.send(pingFrame(7));
    const pong = await waitFor(() => pongs[0]);
    expect(pong.byteLength).toBe(25);

    const hostNowUs = Math.round(epochMs * 1_000);
    hostSockets[0]?.send(audioFrame(hostNowUs));

    const frame = await waitFor(() =>
      frames.find((entry) => entry.type === 'frame'),
    );

    expect(Number.isInteger(frame.startFrame)).toBe(true);
    expect(frame.channels).toBe(2);
  } finally {
    worker.postMessage({ type: 'stop' } satisfies SocketWorkerInbound);
    worker.terminate();
    server.stop(true);
  }
});
