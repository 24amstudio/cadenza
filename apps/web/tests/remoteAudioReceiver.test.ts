import { afterEach, expect, test } from 'bun:test';
import { defaultRemoteAudioSettings } from '../app/lib/remoteAudio/config';
import { lanAudioSocketUrl } from '../app/lib/host/endpoint';
import { RemoteAudioReceiver } from '../app/lib/remoteAudio/receiver';

const realAudioContext = globalThis.AudioContext;
const realAudioWorkletNode = globalThis.AudioWorkletNode;
const realWebSocket = globalThis.WebSocket;

afterEach(() => {
  Reflect.set(globalThis, 'AudioContext', realAudioContext);
  Reflect.set(globalThis, 'AudioWorkletNode', realAudioWorkletNode);
  Reflect.set(globalThis, 'WebSocket', realWebSocket);
});

const hostSocket = 'ws://192.168.1.5:43129/cast/live?role=remote_audio';
const credentials = { clientId: 'remote-1', token: 'paired-token-0123456789' };

const sockets: FakeSocket[] = [];

// Like a browser socket, send() throws until the socket has opened.
class FakeSocket {
  static readonly OPEN = 1;
  static readonly CLOSED = 3;
  readyState = 0;
  readonly sent: string[] = [];
  binaryType = '';
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;

  constructor(readonly url: string) {
    sockets.push(this);
  }

  send(message: string): void {
    if (this.readyState !== FakeSocket.OPEN) {
      throw new Error(
        "Failed to execute 'send' on 'WebSocket': Still in CONNECTING state.",
      );
    }

    this.sent.push(message);
  }

  close(): void {
    this.readyState = FakeSocket.CLOSED;
  }

  open(): void {
    this.readyState = FakeSocket.OPEN;
    this.onopen?.();
  }
}

class FakeAudioContext {
  baseLatency = 0.005;
  outputLatency = 0.012;
  destination = {};
  audioWorklet = { addModule: async () => {} };

  async resume(): Promise<void> {}

  async close(): Promise<void> {}
}

class FakeWorkletNode {
  connect(): void {}

  disconnect(): void {}
}

function installFakes(): void {
  sockets.length = 0;
  Reflect.set(globalThis, 'WebSocket', FakeSocket);
  Reflect.set(globalThis, 'AudioContext', FakeAudioContext);
  Reflect.set(globalThis, 'AudioWorkletNode', FakeWorkletNode);
}

function firstSocket(): FakeSocket {
  const socket = sockets[0];

  if (socket === undefined) throw new Error('the receiver opened no socket');

  return socket;
}

test('a settings change made before the socket opens is sent after the handshake', async () => {
  installFakes();
  const receiver = new RemoteAudioReceiver(hostSocket, credentials);

  await receiver.start('/');
  // The socket is still connecting here, so this must not throw.
  receiver.sendConfig({ ...defaultRemoteAudioSettings, crossoverHz: 95 });

  const socket = firstSocket();
  socket.open();

  const messages = socket.sent.map((message) => JSON.parse(message));

  expect(messages.map((message) => message.type)).toEqual([
    'REMOTE_AUDIO_HANDSHAKE',
    'REMOTE_AUDIO_STREAM_CONFIG',
  ]);
  expect(messages[1].crossoverHz).toBe(95);

  receiver.stop();
});

test('a Host command is refused, not thrown, before the socket opens', async () => {
  installFakes();
  const receiver = new RemoteAudioReceiver(hostSocket, credentials);

  await receiver.start('/');

  expect(receiver.sendCommand('new_environment')).toBe(false);
  expect(firstSocket().sent).toEqual([]);

  receiver.stop();
});

test('the Wi-Fi audio socket dials the Host address, not its Bonjour name', () => {
  expect(
    lanAudioSocketUrl({
      address: '192.168.1.5',
      name: 'darrells-macbook-air.local',
      port: 43129,
    }),
  ).toBe('ws://192.168.1.5:43129/v1/socket');
});
