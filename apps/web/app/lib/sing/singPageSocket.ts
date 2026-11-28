import { isText } from '../host/browserSocket';
import { decodeHostMessage } from '../protocol/decode';
import type { LyricDocument } from '../protocol/types';
import { decodeSingPageState, type SingPageState } from './singPage';

export interface SingPageHandlers {
  onState(state: SingPageState, receivedAtMs: number): void;
  onLyrics(lyrics: LyricDocument): void;
  onConnection(connected: boolean): void;
}

const retryDelaysMs = [1_000, 2_000, 4_000, 8_000];

export function connectSingPage(
  url: string,
  handlers: SingPageHandlers,
): () => void {
  let socket: WebSocket | null = null;
  let retry: ReturnType<typeof setTimeout> | null = null;
  let attempt = 0;
  let stopped = false;

  const receive = (text: string) => {
    const state = decodeSingPageState(text);

    if (state !== null) {
      handlers.onState(state, performance.now());

      return;
    }

    const message = decodeHostMessage(text);

    if (message?.type === 'lyrics') handlers.onLyrics(message.lyrics);
  };

  const open = () => {
    const next = new WebSocket(url);
    socket = next;

    next.onopen = () => {
      attempt = 0;
      handlers.onConnection(true);
    };

    next.onmessage = (event: MessageEvent<unknown>) => {
      if (isText(event.data)) receive(event.data);
    };

    next.onclose = () => {
      if (socket === next) socket = null;
      handlers.onConnection(false);

      if (stopped) return;

      const delay =
        retryDelaysMs[Math.min(attempt, retryDelaysMs.length - 1)] ?? 8_000;

      attempt += 1;
      retry = setTimeout(() => {
        retry = null;
        open();
      }, delay);
    };
  };

  open();

  return () => {
    stopped = true;

    if (retry !== null) clearTimeout(retry);
    socket?.close();
    socket = null;
  };
}
