import { describe, expect, test } from 'bun:test';
import { openRemoteAudioSocket } from '../app/lib/remoteAudio/socketTransport';

interface Deferred<Value> {
  promise: Promise<Value>;
  resolve(value: Value): void;
  reject(reason: Error): void;
}

function deferred<Value>(): Deferred<Value> {
  let resolve: (value: Value) => void = () => undefined;
  let reject: (reason: Error) => void = () => undefined;

  const promise = new Promise<Value>((resolveOuter, rejectOuter) => {
    resolve = resolveOuter;
    reject = rejectOuter;
  });

  return { promise, resolve, reject };
}

const streams: FakeStream[] = [];

class FakeStream {
  readonly writes: unknown[] = [];
  closeCalls = 0;
  readonly #opened = deferred<{
    readable: ReadableStream<string | ArrayBuffer>;
    writable: WritableStream<string | ArrayBuffer | ArrayBufferView>;
  }>();
  readonly #closed = deferred<{ closeCode: number; reason: string }>();
  readonly #inbound = new TransformStream<string | ArrayBuffer>();
  readonly #inboundWriter = this.#inbound.writable.getWriter();
  readonly opened = this.#opened.promise;
  readonly closed = this.#closed.promise;

  constructor(url: string) {
    void url;
    streams.push(this);
  }

  succeed(): void {
    this.#opened.resolve({
      readable: this.#inbound.readable,
      writable: new WritableStream({
        write: (chunk) => {
          this.writes.push(chunk);
        },
      }),
    });
  }

  failOpen(error: Error): void {
    this.#opened.reject(error);
    this.#closed.reject(error);
  }

  async receive(frame: string | ArrayBuffer): Promise<void> {
    await this.#inboundWriter.write(frame);
  }

  closeWith(): void {
    this.#closed.resolve({ closeCode: 1000, reason: '' });
  }

  close(): void {
    this.closeCalls += 1;
  }
}

function lastStream(): FakeStream {
  const stream = streams.at(-1);

  if (stream === undefined) throw new Error('the transport opened no stream');

  return stream;
}

async function waitFor(check: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (check()) return;

    await new Promise((resolve) => setTimeout(resolve, 5));
  }

  throw new Error('the condition never held');
}

async function settle(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 20));
}

describe('remote audio socket transport', () => {
  test('a stream socket opens after its handshake and passes text and binary frames to the handler', async () => {
    const socket = openRemoteAudioSocket('ws://host/cast/live', FakeStream);
    const received: unknown[] = [];
    let opened = 0;

    socket.onopen = () => {
      opened += 1;
    };

    socket.onmessage = (event) => {
      received.push(event.data);
    };

    expect(socket.readyState).toBe(0);

    lastStream().succeed();
    await waitFor(() => socket.readyState === 1);
    await lastStream().receive('text frame');
    await lastStream().receive(new Uint8Array([1, 2, 3]).buffer);
    await waitFor(() => received.length === 2);

    expect(opened).toBe(1);
    expect(received[0]).toBe('text frame');
    expect(received[1]).toBeInstanceOf(ArrayBuffer);
  });

  test('send is refused until the handshake completes, then writes the frame to the stream', async () => {
    const socket = openRemoteAudioSocket('ws://host/cast/live', FakeStream);

    expect(() => socket.send('too early')).toThrow();

    lastStream().succeed();
    await waitFor(() => socket.readyState === 1);
    socket.send('hello');
    await waitFor(() => lastStream().writes.length === 1);

    expect(lastStream().writes).toEqual(['hello']);
  });

  test('a refused handshake reports one error and then one close', async () => {
    const socket = openRemoteAudioSocket('ws://host/cast/live', FakeStream);
    const events: string[] = [];
    socket.onerror = () => events.push('error');
    socket.onclose = () => events.push('close');

    lastStream().failOpen(new Error('refused'));
    await settle();

    expect(events).toEqual(['error', 'close']);
    expect(socket.readyState).toBe(3);
  });

  test('close asks the stream to close, and the close is reported once', async () => {
    const socket = openRemoteAudioSocket('ws://host/cast/live', FakeStream);
    let closes = 0;
    socket.onclose = () => {
      closes += 1;
    };

    lastStream().succeed();
    await waitFor(() => socket.readyState === 1);
    socket.close();

    expect(lastStream().closeCalls).toBe(1);

    lastStream().closeWith();
    await settle();

    expect(closes).toBe(1);
    expect(socket.readyState).toBe(3);
  });

  test('without WebSocketStream the socket is a plain WebSocket that receives frames from the Host', async () => {
    const host = Bun.serve({
      port: 0,
      fetch(request, server) {
        return server.upgrade(request)
          ? undefined
          : new Response('not a websocket', { status: 400 });
      },
      websocket: {
        open(ws) {
          ws.send('hello from the host');
        },
        message() {},
      },
    });

    const socket = openRemoteAudioSocket(
      `ws://127.0.0.1:${host.port}/cast/live`,
      undefined,
    );

    try {
      const received = await new Promise<unknown>((resolve) => {
        socket.onmessage = (event) => resolve(event.data);
      });

      expect(received).toBe('hello from the host');
    } finally {
      socket.close();
      host.stop(true);
    }
  });
});
