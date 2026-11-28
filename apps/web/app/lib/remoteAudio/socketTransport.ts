import type { SocketLike } from './socketCore';

interface WebSocketStreamConnection {
  readonly readable: ReadableStream<string | ArrayBuffer>;
  readonly writable: WritableStream<string | ArrayBuffer | ArrayBufferView>;
}

interface WebSocketStreamHandle {
  readonly opened: Promise<WebSocketStreamConnection>;
  readonly closed: Promise<unknown>;
  close(options?: { closeCode?: number; reason?: string }): void;
}

export type WebSocketStreamConstructor = new (
  url: string,
) => WebSocketStreamHandle;

declare global {
  var WebSocketStream: WebSocketStreamConstructor | undefined;
}

const readyStates = { connecting: 0, open: 1, closing: 2, closed: 3 };

class WebSocketStreamSocket implements SocketLike {
  readyState = readyStates.connecting;
  binaryType: BinaryType = 'arraybuffer';
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  readonly #stream: WebSocketStreamHandle;
  #writer: WritableStreamDefaultWriter<
    string | ArrayBuffer | ArrayBufferView
  > | null = null;
  #finished = false;

  constructor(url: string, Stream: WebSocketStreamConstructor) {
    this.#stream = new Stream(url);
    this.#stream.opened.then(
      (connection) => this.#open(connection),
      () => this.#finish(true),
    );
    this.#stream.closed.then(
      () => this.#finish(false),
      () => this.#finish(true),
    );
  }

  send(data: string | ArrayBuffer | ArrayBufferView): void {
    if (this.#writer === null)
      throw new Error('The audio socket is still connecting.');

    if (this.readyState !== readyStates.open) return;

    void this.#writer.write(data).catch(() => this.#finish(true));
  }

  close(): void {
    if (this.readyState === readyStates.closed) return;

    this.readyState = readyStates.closing;
    this.#stream.close();
  }

  #open(connection: WebSocketStreamConnection): void {
    this.readyState = readyStates.open;
    this.#writer = connection.writable.getWriter();
    this.onopen?.();
    void this.#read(connection.readable.getReader());
  }

  async #read(
    reader: ReadableStreamDefaultReader<string | ArrayBuffer>,
  ): Promise<void> {
    for (;;) {
      const next = await reader.read().catch(() => null);

      if (next === null || next.done) return;

      this.onmessage?.({ data: next.value });
    }
  }

  #finish(failed: boolean): void {
    if (this.#finished) return;

    this.#finished = true;
    this.readyState = readyStates.closed;

    if (failed) this.onerror?.();

    this.onclose?.();
  }
}

class PlainWebSocketSocket implements SocketLike {
  readonly #socket: WebSocket;
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;

  constructor(url: string) {
    this.#socket = new WebSocket(url);
    this.#socket.onopen = () => this.onopen?.();
    this.#socket.onmessage = (event) => this.onmessage?.({ data: event.data });
    this.#socket.onclose = () => this.onclose?.();
    this.#socket.onerror = () => this.onerror?.();
  }

  get readyState(): number {
    return this.#socket.readyState;
  }

  get binaryType(): BinaryType {
    return this.#socket.binaryType;
  }

  set binaryType(value: BinaryType) {
    this.#socket.binaryType = value;
  }

  send(data: string | ArrayBuffer | ArrayBufferView): void {
    this.#socket.send(data);
  }

  close(): void {
    this.#socket.close();
  }
}

export function openRemoteAudioSocket(
  url: string,
  streamConstructor:
    WebSocketStreamConstructor | undefined = globalThis.WebSocketStream,
): SocketLike {
  if (streamConstructor === undefined) return new PlainWebSocketSocket(url);

  return new WebSocketStreamSocket(url, streamConstructor);
}
