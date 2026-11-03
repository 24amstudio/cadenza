import type { SocketLike } from './client';

// Adapts the browser WebSocket to the small surface the client needs. Only text frames are accepted; binary data is
// never part of the Host protocol.
export function openBrowserSocket(url: string): SocketLike {
  const socket = new WebSocket(url);

  const adapter: SocketLike = {
    onOpen: null,
    onMessage: null,
    onClose: null,
    send: (text) => socket.send(text),
    close: () => socket.close(),
  };

  socket.onopen = () => adapter.onOpen?.();
  socket.onmessage = (event: MessageEvent<unknown>) => {
    if (isText(event.data)) adapter.onMessage?.(event.data);
  };

  socket.onclose = () => adapter.onClose?.();

  return adapter;
}

function isText(value: unknown): value is string {
  return String(value) === value;
}
