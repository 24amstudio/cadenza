import { afterEach, describe, expect, test } from 'bun:test';
import { defaultRemoteAudioSettings } from '../app/lib/remoteAudio/config';
import {
  isJsonObject,
  parseJson,
  type JsonObject,
} from '../app/lib/protocol/json';
import {
  RemoteAudioSocketCore,
  type FramePort,
  type FramePortMessage,
  type RemoteAudioCredentials,
  type RemoteAudioOutput,
  type RemoteAudioStatus,
  type SocketLike,
} from '../app/lib/remoteAudio/socketCore';

const url = 'ws://192.168.1.5:43129/cast/live?role=remote_audio';

const credentials: RemoteAudioCredentials = {
  clientId: 'remote-1',
  token: 'paired-token-0123456789',
};

const output: RemoteAudioOutput = {
  baseLatencyMs: 5,
  outputLatencyMs: 12,
  userAgent: 'test-agent',
};

class FakeSocket implements SocketLike {
  readyState = 0;
  binaryType: BinaryType = 'blob';
  readonly sent: Array<string | ArrayBuffer | ArrayBufferView> = [];
  closed = false;
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;

  send(data: string | ArrayBuffer | ArrayBufferView): void {
    if (this.readyState !== 1) throw new Error('Still in CONNECTING state.');
    this.sent.push(data);
  }

  close(): void {
    this.closed = true;
    this.readyState = 3;
  }

  open(): void {
    this.readyState = 1;
    this.onopen?.();
  }

  deliver(data: string | ArrayBuffer): void {
    this.onmessage?.({ data });
  }

  get messages(): JsonObject[] {
    const messages: JsonObject[] = [];

    for (const item of this.sent) {
      const value = parseJson(String(item));

      if (value !== null && isJsonObject(value)) messages.push(value);
    }

    return messages;
  }
}

type PostedFrame<Type extends FramePortMessage['type']> = {
  message: Extract<FramePortMessage, { type: Type }>;
  transfer: Transferable[];
};

function hasType<Type extends FramePortMessage['type']>(
  message: FramePortMessage,
  type: Type,
): message is Extract<FramePortMessage, { type: Type }> {
  return message.type === type;
}

class FakePort implements FramePort {
  readonly posted: Array<{
    message: FramePortMessage;
    transfer: Transferable[];
  }> = [];

  postMessage(message: FramePortMessage, transfer: Transferable[] = []): void {
    this.posted.push({ message, transfer });
  }

  ofType<Type extends FramePortMessage['type']>(
    type: Type,
  ): PostedFrame<Type>[] {
    const matches: PostedFrame<Type>[] = [];

    for (const entry of this.posted) {
      if (hasType(entry.message, type))
        matches.push({ message: entry.message, transfer: entry.transfer });
    }

    return matches;
  }
}

function harness(epochMs = 1_000) {
  const sockets: FakeSocket[] = [];
  const port = new FakePort();
  const patches: Partial<RemoteAudioStatus>[] = [];
  let now = epochMs;

  const core = new RemoteAudioSocketCore({
    connect: () => {
      const socket = new FakeSocket();
      sockets.push(socket);

      return socket;
    },
    port,
    now: () => now,
    emit: (patch) => patches.push(patch),
  });

  return {
    core,
    port,
    patches,
    socket(): FakeSocket {
      const socket = sockets[0];

      if (socket === undefined) throw new Error('the core opened no socket');

      return socket;
    },
    setNow(ms: number) {
      now = ms;
    },
    status(): Partial<RemoteAudioStatus> {
      return Object.assign({}, ...patches);
    },
  };
}

function audioFrame(targetPlayoutHostUs: number): ArrayBuffer {
  const bytes = new Uint8Array(26 + 2 * 2 * 4);
  const view = new DataView(bytes.buffer);
  bytes[0] = 0x01;
  bytes[2] = 2;
  bytes[3] = 32;
  view.setBigUint64(16, BigInt(targetPlayoutHostUs));
  view.setUint16(24, 2);

  for (let index = 0; index < 4; index += 1) {
    view.setFloat32(26 + index * 4, 0.25, true);
  }

  return bytes.buffer;
}

function syncMessage(fields: JsonObject): string {
  return JSON.stringify({ version: 1, type: 'REMOTE_AUDIO_SYNC', ...fields });
}

const realWarn = console.warn;

afterEach(() => {
  console.warn = realWarn;
});

describe('socket core', () => {
  test('the handshake reports this Remote, and a settings change made before the socket opens follows it', () => {
    const h = harness();
    h.core.sendConfig({ ...defaultRemoteAudioSettings, crossoverHz: 95 });
    h.core.start(url, credentials, output);
    h.socket().open();

    const messages = h.socket().messages;
    expect(messages.map((message) => message.type)).toEqual([
      'REMOTE_AUDIO_HANDSHAKE',
      'REMOTE_AUDIO_STREAM_CONFIG',
    ]);
    expect(messages[0]?.token).toBe(credentials.token);
    expect(messages[0]?.baseLatencyMs).toBe(5);
    expect(messages[0]?.outputLatencyMs).toBe(12);
    expect(messages[1]?.crossoverHz).toBe(95);
    expect(h.status().socketOpen).toBe(true);
  });

  test('a Host command is refused until the socket is open, then sent', () => {
    const h = harness();

    expect(h.core.sendCommand('new_environment')).toBe(false);

    h.core.start(url, credentials, output);
    expect(h.core.sendCommand('new_environment')).toBe(false);

    h.socket().open();
    expect(h.core.sendCommand('new_environment')).toBe(true);
    expect(h.socket().messages.at(-1)?.type).toBe('REMOTE_AUDIO_COMMAND');
  });

  test('a sync carries the stream round trip and quality, and is answered with the playout pressure of its window', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();
    h.core.receivePlayoutCounts({ dropped: 0, concealed: 120, underrun: 48 });

    h.socket().deliver(
      syncMessage({
        transmitting: true,
        networkRttMs: 4,
        processingRttMs: 0.5,
        quality: 'standard_16_48',
        qualityReason: 'network',
        linkHealthy: true,
      }),
    );

    expect(h.status()).toMatchObject({
      transmitting: true,
      networkRttMs: 4,
      processingRttMs: 0.5,
      quality: 'standard_16_48',
      qualityReason: 'network',
    });

    const reports = h
      .socket()
      .messages.filter((message) => message.type === 'REMOTE_AUDIO_PLAYOUT');

    expect(reports).toEqual([
      {
        version: 1,
        type: 'REMOTE_AUDIO_PLAYOUT',
        underrunFrames: 48,
        concealedFrames: 120,
        longTaskMs: 0,
      },
    ]);

    h.socket().deliver(syncMessage({ linkHealthy: false }));
    expect(
      h
        .socket()
        .messages.filter((message) => message.type === 'REMOTE_AUDIO_PLAYOUT')
        .at(-1),
    ).toEqual({
      version: 1,
      type: 'REMOTE_AUDIO_PLAYOUT',
      underrunFrames: 0,
      concealedFrames: 0,
      longTaskMs: 0,
    });
  });

  test('a frame is placed on the context timeline at the instant the Host asked for it', () => {
    const h = harness(1_000);
    h.core.start(url, credentials, output);
    h.socket().open();
    h.socket().deliver(
      syncMessage({ clockOffsetUs: 0, clockDriftPpm: 0, jitterBufferMs: 28 }),
    );
    h.core.setOutputClock({ contextTime: 10, epochMs: 1_000 });

    h.socket().deliver(audioFrame(1_000_000));

    const frames = h.port.ofType('frame');
    expect(frames).toHaveLength(1);
    expect(frames[0]?.message.startFrame).toBe(480_000);
    expect(frames[0]?.transfer).toHaveLength(2);
  });

  test('no frame is placed before the core has both a clock fix and an output clock', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();

    h.socket().deliver(audioFrame(1_000_000));

    expect(h.port.ofType('frame')).toHaveLength(0);
  });

  test('a flush from the Host reaches the worklet as a flush', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();
    const flush = new Uint8Array(5);
    flush[0] = 0x02;

    h.socket().deliver(flush.buffer);

    expect(h.port.ofType('flush')).toHaveLength(1);
  });

  test('a ping is answered with a pong on the socket', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();
    const ping = new Uint8Array(17);
    ping[0] = 0x04;
    new DataView(ping.buffer).setBigUint64(9, 42n);

    h.socket().deliver(ping.buffer);

    const pongs = h
      .socket()
      .sent.filter(
        (item): item is ArrayBuffer =>
          item instanceof ArrayBuffer && new Uint8Array(item)[0] === 0x05,
      );

    expect(pongs).toHaveLength(1);
    expect(pongs[0]?.byteLength).toBe(25);
  });

  test('frames the worklet could not place reach the status as a count, and are warned about', () => {
    const h = harness();
    const warnings: string[] = [];
    console.warn = (...data: unknown[]) => {
      warnings.push(data.map(String).join(' '));
    };

    h.core.start(url, credentials, output);

    h.core.receivePlayoutCounts({ dropped: 3, concealed: 0, underrun: 0 });
    h.core.receivePlayoutCounts({ dropped: 2, concealed: 0, underrun: 0 });

    expect(h.status().playoutDroppedFrames).toBe(5);
    expect(warnings).toHaveLength(2);
    expect(warnings[1]).toContain('dropped 2 audio frames');
    expect(warnings[1]).toContain('5 since this stream started');
  });

  test('main-thread long-task time joins the next playout report', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();
    h.core.addLongTaskMs(37.4);

    h.socket().deliver(syncMessage({ linkHealthy: false }));

    expect(
      h
        .socket()
        .messages.find((message) => message.type === 'REMOTE_AUDIO_PLAYOUT')
        ?.longTaskMs,
    ).toBe(37);
  });

  test('stop closes the socket, reports idle, and sends nothing afterwards', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();

    h.core.stop();

    expect(h.socket().closed).toBe(true);
    expect(h.status()).toMatchObject({ state: 'idle', socketOpen: false });
    expect(h.core.sendCommand('new_environment')).toBe(false);
  });

  test('the stream jitter comes from the round trips the Host reports, once there are three', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();

    for (const networkRttMs of [2, 8, 2, 8]) {
      h.socket().deliver(syncMessage({ networkRttMs }));
    }

    expect(h.status().networkJitterMs).toBe(3);
  });

  test('audio dropouts count for the last thirty playout reports, about a minute, then stop counting', () => {
    const h = harness();
    h.core.start(url, credentials, output);
    h.socket().open();

    h.socket().deliver(syncMessage({ linkHealthy: true }));
    h.core.receivePlayoutCounts({ dropped: 0, concealed: 480, underrun: 0 });
    h.socket().deliver(syncMessage({ linkHealthy: true }));

    expect(h.status().dropoutMs60s).toBe(10);

    for (let report = 0; report < 29; report += 1) {
      h.socket().deliver(syncMessage({ linkHealthy: true }));
    }

    expect(h.status().dropoutMs60s).toBe(10);

    h.socket().deliver(syncMessage({ linkHealthy: true }));

    expect(h.status().dropoutMs60s).toBe(0);
  });
});
