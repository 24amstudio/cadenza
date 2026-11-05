import { describe, expect, test } from 'bun:test';
import {
  HostClient,
  type HostChange,
  type HostClientOptions,
  type SocketLike,
} from '../app/lib/host/client';
import type {
  CredentialStore,
  StoredCredential,
} from '../app/lib/host/credentials';
import {
  counterField,
  isJsonObject,
  objectField,
  parseJson,
  type JsonObject,
  type JsonValue,
} from '../app/lib/protocol/json';
import type { CommandResult } from '../app/lib/protocol/types';

const remoteId = '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c';
const epoch = '6e4f9a10-1111-4222-8333-444455556666';
const occurrenceId = '0a0b0c0d-1111-4222-8333-444455556666';
const token = 'T'.repeat(43);
const hostOffsetMs = 1_000;

type Message = { [key: string]: JsonValue | undefined };

function socketAt(sockets: FakeSocket[], index: number): FakeSocket {
  const socket = sockets[index];

  if (socket === undefined) throw new Error(`No socket at index ${index}`);

  return socket;
}

class FakeSocket implements SocketLike {
  onOpen: (() => void) | null = null;
  onMessage: ((text: string) => void) | null = null;
  onClose: (() => void) | null = null;
  readonly frames: JsonObject[] = [];
  closed = false;

  send(text: string): void {
    const value = parseJson(text);

    if (value !== null && isJsonObject(value)) this.frames.push(value);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.onClose?.();
  }

  open(): void {
    this.onOpen?.();
  }

  serverDrop(): void {
    this.close();
  }

  // Undefined fields are omitted by JSON.stringify, matching frames that carry no value for that key.
  receive(message: Message): void {
    this.onMessage?.(JSON.stringify({ version: 1, ...message }));
  }

  framesOfType(type: string): JsonObject[] {
    return this.frames.filter((frame) => frame.type === type);
  }
}

class Clock {
  now = 0;
  private tasks: { at: number; run: () => void; cancelled: boolean }[] = [];

  schedule = (callback: () => void, delayMs: number): (() => void) => {
    const task = { at: this.now + delayMs, run: callback, cancelled: false };
    this.tasks.push(task);

    return () => {
      task.cancelled = true;
    };
  };

  advance(ms: number): void {
    const target = this.now + ms;

    for (;;) {
      const due = this.tasks
        .filter((task) => !task.cancelled && task.at <= target)
        .sort((first, second) => first.at - second.at)[0];

      if (due === undefined) break;
      this.now = due.at;
      this.tasks = this.tasks.filter((task) => task !== due);
      due.run();
    }

    this.now = target;
  }
}

class MemoryCredentials implements CredentialStore {
  value: StoredCredential | null = null;
  read(): StoredCredential | null {
    return this.value;
  }
  write(credential: StoredCredential): void {
    this.value = credential;
  }
  clear(): void {
    this.value = null;
  }
}

interface Harness {
  client: HostClient;
  sockets: FakeSocket[];
  changes: HostChange[];
  clock: Clock;
  credentials: MemoryCredentials;
}

function harness(
  credentials: MemoryCredentials = new MemoryCredentials(),
  progressiveArtwork = false,
): Harness {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const changes: HostChange[] = [];
  let ids = 0;

  const options: HostClientOptions = {
    url: 'wss://host.test/v1/socket',
    remoteVersion: 'cadenza-web test',
    defaultName: 'Web browser on Mac',
    openSocket: () => {
      const socket = new FakeSocket();
      sockets.push(socket);

      return socket;
    },
    credentials,
    monotonicNow: () => clock.now,
    schedule: clock.schedule,
    newId: () => {
      ids += 1;

      return `id-${ids}`;
    },
    onChange: (change) => changes.push(change),
    progressiveArtwork,
  };

  return {
    client: new HostClient(options),
    sockets,
    changes,
    clock,
    credentials,
  };
}

function welcome(
  issuedToken: string | null,
  capabilities: string[] = ['artwork.host-cache'],
): JsonObject {
  return {
    type: 'welcome',
    welcome: {
      host_id: remoteId,
      host_name: 'Living room Mac',
      host_epoch: epoch,
      remote_id: remoteId,
      token: issuedToken,
      host_time_ms: hostOffsetMs,
      capabilities,
    },
  };
}

// Answers each clock probe as the Host would: 10 ms round trip, Host clock 1000 ms ahead. A reply triggers the next
// probe, so the loop continues until no unanswered probe remains.
function answerClockProbes(socket: FakeSocket, clock: Clock): void {
  const answered = new Set<JsonValue | undefined>();

  for (;;) {
    const frame = socket
      .framesOfType('clock')
      .find((candidate) => !answered.has(candidate.request_id));

    if (frame === undefined) return;
    answered.add(frame.request_id);
    const sample = objectField(frame, 'clock');

    const sentAtRemote =
      sample === null ? null : counterField(sample, 'sent_at_remote_ms');

    if (sentAtRemote === null) return;
    clock.advance(10);
    socket.receive({
      type: 'clock',
      request_id: frame.request_id ?? null,
      clock: {
        sent_at_remote_ms: sentAtRemote,
        received_at_host_ms: sentAtRemote + hostOffsetMs + 5,
        sent_at_host_ms: sentAtRemote + hostOffsetMs + 5,
      },
    });
  }
}

function snapshotFrame(revision: number): JsonObject {
  return {
    type: 'state',
    snapshot: {
      host_id: remoteId,
      host_epoch: epoch,
      revision,
      sequence: 1,
      host_time_ms: 2_000,
      allow_cross_remote_edits: false,
      playing: true,
      volume: 50,
      current: null,
      queue: [],
      quality: 'unknown',
      synchronized: true,
      observation_gap: false,
    },
  };
}

function phases(changes: HostChange[]): string[] {
  return changes.flatMap((change) =>
    change.kind === 'phase' ? [change.phase] : [],
  );
}

function results(changes: HostChange[]): CommandResult[] {
  return changes.flatMap((change) =>
    change.kind === 'commandResolved' ? [change.result] : [],
  );
}

describe('HostClient pairing and reconnection', () => {
  test('opens no socket while the browser has never been paired', () => {
    const { client, sockets, changes } = harness();

    client.start(null);

    expect(sockets).toHaveLength(0);
    expect(phases(changes)).toEqual(['unpaired']);
  });

  test('pairs with the invitation secret and stores the issued credential', () => {
    const { client, sockets, credentials, changes } = harness();
    const secret = 'S'.repeat(43);

    client.start(secret);
    const socket = sockets[0];
    socket?.open();
    const pair = socket?.framesOfType('pair')[0];

    expect(pair).toMatchObject({
      pair: { secret, name: 'Web browser on Mac' },
    });
    socket?.receive(welcome(token));

    expect(credentials.value).toMatchObject({
      remoteId,
      token,
      name: 'Web browser on Mac',
    });
    expect(phases(changes)).toEqual(['pairing', 'connected']);
  });

  test('reports a rejected invitation without keeping a credential', () => {
    const { client, sockets, credentials, changes } = harness();

    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive({
      type: 'error',
      error_code: 'authentication',
      message: 'The pairing PIN is invalid.',
    });

    expect(credentials.value).toBeNull();
    expect(phases(changes).at(-1)).toBe('pairing-failed');
  });

  test('reconnects with the stored credential instead of pairing again', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Desk',
      lastCreditSequence: 4,
    };
    const { client, sockets, changes } = harness(credentials);

    client.start(null);
    socketAt(sockets, 0).open();
    const hello = socketAt(sockets, 0).framesOfType('hello')[0];

    expect(hello).toMatchObject({
      auth: {
        remote_id: remoteId,
        token,
        last_credit_sequence: 4,
        name: 'Desk',
      },
    });
    socketAt(sockets, 0).receive(welcome(null));
    expect(phases(changes).at(-1)).toBe('connected');
  });

  test('forgets a credential that the Host revokes', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Desk',
      lastCreditSequence: 0,
    };
    const { client, sockets, changes, clock } = harness(credentials);

    client.start(null);
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive({
      type: 'error',
      error_code: 'revoked',
      message: 'This Remote is no longer paired.',
    });
    clock.advance(60_000);

    expect(credentials.value).toBeNull();
    expect(phases(changes).at(-1)).toBe('unpaired');
    expect(sockets).toHaveLength(1);
  });

  test('acknowledges analytics credits and remembers the last sequence', () => {
    const { client, sockets, credentials } = harness();

    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));
    socketAt(sockets, 0).receive({ type: 'analytics.credit', sequence: 7 });

    expect(socketAt(sockets, 0).framesOfType('analytics.ack')).toEqual([
      { version: 1, type: 'analytics.ack', sequence: 7 },
    ]);
    expect(credentials.value?.lastCreditSequence).toBe(7);
  });

  test('applies a rename only after the Host confirms it', () => {
    const { client, sockets, credentials, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));

    client.renameRemote('Desk');
    expect(credentials.value?.name).toBe('Web browser on Mac');

    const request = socketAt(sockets, 0).framesOfType('remote.configure')[0]
      ?.request_id;

    socketAt(sockets, 0).receive({
      type: 'remote.configured',
      request_id: request,
    });

    expect(credentials.value?.name).toBe('Desk');
    expect(changes.some((change) => change.kind === 'notice')).toBe(true);
  });
});

describe('HostClient commands', () => {
  test('sends a command only after a clock estimate and resolves it from the Host result', async () => {
    const { client, sockets, clock } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));
    socketAt(sockets, 0).receive(snapshotFrame(18));
    answerClockProbes(socketAt(sockets, 0), clock);

    const pending = client.sendCommand({
      kind: 'playback.pause',
      occurrenceId,
    });

    const command = socketAt(sockets, 0).framesOfType('command')[0];

    expect(command).toMatchObject({
      host_epoch: epoch,
      expected_revision: 18,
      action: { kind: 'playback.pause', occurrence_id: occurrenceId },
    });
    socketAt(sockets, 0).receive({
      type: 'command.result',
      command_id: command?.command_id,
      host_epoch: epoch,
      outcome: 'applied',
      revision: 19,
    });

    expect(await pending).toMatchObject({ outcome: 'applied', revision: 19 });
  });

  test('a command expires within the one-second window the Host accepts', async () => {
    const { client, sockets, clock } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));
    socketAt(sockets, 0).receive(snapshotFrame(18));
    answerClockProbes(socketAt(sockets, 0), clock);

    const hostNow = client.hostNowMs();
    void client.sendCommand({ kind: 'playback.pause', occurrenceId });

    const command = socketAt(sockets, 0).framesOfType('command')[0];
    const remainingMs = Number(command?.expires_at_host_ms) - (hostNow ?? 0);

    expect(remainingMs).toBeGreaterThan(0);
    expect(remainingMs).toBeLessThanOrEqual(1_000);
  });

  test('keeps probing while connected, and a slow asymmetric probe does not move the offset', () => {
    const { client, sockets, clock } = harness();

    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));
    socketAt(sockets, 0).receive(snapshotFrame(18));
    answerClockProbes(socketAt(sockets, 0), clock);
    expect((client.hostNowMs() ?? 0) - clock.now).toBe(hostOffsetMs);

    clock.advance(5_000);
    const probe = socketAt(sockets, 0).framesOfType('clock').at(-1);

    const sample = probe === undefined ? null : objectField(probe, 'clock');

    const sentAtRemote =
      sample === null ? null : counterField(sample, 'sent_at_remote_ms');

    expect(sentAtRemote).not.toBeNull();

    // The reply crosses a slow link: 180 ms out and 20 ms back. An estimate built from it would be 80 ms off.
    clock.advance(200);
    socketAt(sockets, 0).receive({
      type: 'clock',
      request_id: probe?.request_id ?? null,
      clock: {
        sent_at_remote_ms: sentAtRemote,
        received_at_host_ms: (sentAtRemote ?? 0) + 180 + hostOffsetMs,
        sent_at_host_ms: (sentAtRemote ?? 0) + 180 + hostOffsetMs,
      },
    });

    expect((client.hostNowMs() ?? 0) - clock.now).toBe(hostOffsetMs);
  });

  test('refuses to send before the Host has a clock estimate', async () => {
    const { client, sockets } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));
    socketAt(sockets, 0).receive(snapshotFrame(3));

    const result = await client.sendCommand({
      kind: 'playback.skip',
      occurrenceId,
    });

    expect(result).toMatchObject({
      outcome: 'rejected',
      errorCode: 'unavailable',
    });
    expect(socketAt(sockets, 0).framesOfType('command')).toHaveLength(0);
  });

  test('reports an interrupted command as unconfirmed and never sends it again', async () => {
    const { client, sockets, clock, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));
    socketAt(sockets, 0).receive(snapshotFrame(18));
    answerClockProbes(socketAt(sockets, 0), clock);

    const pending = client.sendCommand({ kind: 'playback.skip', occurrenceId });

    const commandId = socketAt(sockets, 0).framesOfType('command')[0]
      ?.command_id;

    socketAt(sockets, 0).serverDrop();
    const outcome = await pending;

    expect(outcome.outcome).toBe('unconfirmed');
    clock.advance(1_000);
    socketAt(sockets, 1).open();
    socketAt(sockets, 1).receive(welcome(null));

    expect(socketAt(sockets, 1).framesOfType('command')).toHaveLength(0);
    const statusFrames = socketAt(sockets, 1).framesOfType('command.status');
    expect(statusFrames).toHaveLength(1);
    expect(statusFrames[0]?.command_id).toBe(commandId);

    socketAt(sockets, 1).receive({
      type: 'command.result',
      command_id: commandId,
      host_epoch: epoch,
      outcome: 'applied',
      revision: 19,
    });
    expect(results(changes)).toEqual([
      expect.objectContaining({ commandId, outcome: 'applied' }),
    ]);
  });

  test('does not request artwork that the Host did not advertise', () => {
    const { client, sockets, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, []));

    client.requestArtwork('https://example.com/cover.jpg');

    expect(socketAt(sockets, 0).framesOfType('artwork.get')).toHaveLength(0);
    expect(changes).toContainEqual({
      kind: 'artwork',
      artworkUrl: 'https://example.com/cover.jpg',
      dataUrl: null,
    });
  });
});

describe('HostClient over Bluetooth', () => {
  test('pairs with the Host PIN and stores the name the user entered', () => {
    const { client, credentials, changes } = harness();
    const link = new FakeSocket();

    client.startBluetooth(false);
    client.pairOverBluetooth(link, '4821', 'Desk');

    expect(link.framesOfType('pair')).toEqual([
      {
        version: 1,
        type: 'pair',
        pair: {
          pin: '4821',
          name: 'Desk',
          remote_version: 'cadenza-web test',
          heartbeat: true,
        },
      },
    ]);

    link.receive(welcome(token));

    expect(credentials.value).toMatchObject({ remoteId, token, name: 'Desk' });
    expect(phases(changes)).toEqual(['unpaired', 'pairing', 'connected']);
  });

  test('a rejected PIN ends the attempt and stores no credential', () => {
    const { client, credentials, changes } = harness();
    const link = new FakeSocket();

    client.startBluetooth(false);
    client.pairOverBluetooth(link, '0000', 'Desk');
    link.receive({
      type: 'error',
      error_code: 'authentication',
      message: 'The pairing PIN is invalid or expired.',
    });

    expect(credentials.value).toBeNull();
    expect(link.closed).toBe(true);
    expect(changes.at(-1)).toEqual({
      kind: 'phase',
      phase: 'pairing-failed',
      attempt: 0,
      message: 'The pairing PIN is invalid or expired.',
    });
  });

  test('a link that drops after pairing waits for a user gesture instead of reopening', () => {
    const { client, sockets, clock, credentials, changes } = harness();
    const link = new FakeSocket();

    client.startBluetooth(false);
    client.pairOverBluetooth(link, '4821', 'Desk');
    link.receive(welcome(token));
    link.serverDrop();
    clock.advance(60_000);

    expect(credentials.value).toMatchObject({ remoteId, token });
    expect(phases(changes).at(-1)).toBe('bluetooth-idle');
    expect(sockets).toHaveLength(0);
  });

  test('reconnects with the stored credential over a new link', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Desk',
      lastCreditSequence: 4,
    };
    const { client, changes } = harness(credentials);
    const link = new FakeSocket();

    client.startBluetooth(false);
    client.connectOverBluetooth(link);

    expect(link.framesOfType('hello')).toEqual([
      {
        version: 1,
        type: 'hello',
        auth: {
          remote_id: remoteId,
          token,
          last_credit_sequence: 4,
          name: 'Desk',
          remote_version: 'cadenza-web test',
          heartbeat: true,
        },
      },
    ]);

    link.receive(welcome(null));

    expect(phases(changes)).toEqual([
      'bluetooth-idle',
      'connecting',
      'connected',
    ]);
  });

  test('a stored credential with a remembered device reconnects without the pairing view', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Desk',
      lastCreditSequence: 0,
    };
    const { client, changes } = harness(credentials);

    expect(client.startBluetooth(true)).toBe(true);
    expect(phases(changes)).toEqual(['connecting']);
  });

  test('a failed silent reconnect falls back to the connect button, not onboarding', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Desk',
      lastCreditSequence: 0,
    };
    const { client, changes } = harness(credentials);

    client.startBluetooth(true);
    client.bluetoothReconnectFailed();

    expect(phases(changes)).toEqual(['connecting', 'bluetooth-idle']);
  });

  test('never opens a Bluetooth session without a stored credential', () => {
    const { client, changes } = harness();
    const link = new FakeSocket();

    client.startBluetooth(false);
    client.connectOverBluetooth(link);

    expect(link.frames).toHaveLength(0);
    expect(phases(changes)).toEqual(['unpaired']);
  });

  test('a progressive artwork request shows the preview, then the verified full image', async () => {
    const { client, sockets, changes } = harness(new MemoryCredentials(), true);
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(
      welcome(token, ['artwork.host-cache', 'artwork.progressive']),
    );
    const artworkUrl = 'https://example.com/cover.jpg';

    client.requestArtwork(artworkUrl);

    const request = socketAt(sockets, 0).framesOfType('artwork.get').at(-1);
    expect(request?.progressive).toBe(true);
    const requestId = String(request?.request_id);

    const file = Uint8Array.from({ length: 2_500 }, (_, index) =>
      index < 3 ? [0xff, 0xd8, 0xff][index]! : index % 251,
    );

    const digest = Array.from(
      new Uint8Array(await crypto.subtle.digest('SHA-256', file)),
      (byte) => byte.toString(16).padStart(2, '0'),
    ).join('');

    const preview = Buffer.from([0xff, 0xd8, 0xff, 0xe0]).toString('base64');
    const previewUrl = `data:image/jpeg;base64,${preview}`;

    socketAt(sockets, 0).receive({
      type: 'artwork',
      request_id: requestId,
      artwork_url: artworkUrl,
      artwork_data_base64: preview,
      variant: 'preview',
    });

    expect(latestArtwork(changes)).toBe(previewUrl);

    const chunkSize = 1_000;
    const count = Math.ceil(file.length / chunkSize);

    for (let index = count - 1; index >= 0; index -= 1) {
      socketAt(sockets, 0).receive({
        type: 'artwork.chunk',
        request_id: requestId,
        artwork_url: artworkUrl,
        chunk_index: index,
        chunk_count: count,
        total_bytes: file.length,
        sha256: digest,
        data_base64: Buffer.from(
          file.subarray(index * chunkSize, (index + 1) * chunkSize),
        ).toString('base64'),
      });
    }

    // Verification is asynchronous, so the full image replaces the preview a moment after the last chunk.
    for (
      let attempt = 0;
      attempt < 400 && latestArtwork(changes) === previewUrl;
      attempt += 1
    ) {
      await new Promise((resolve) => setTimeout(resolve, 5));
    }

    const full = latestArtwork(changes);
    expect(full?.startsWith('data:image/jpeg;base64,')).toBe(true);
    expect(Buffer.from(String(full).split(',')[1] ?? '', 'base64')).toEqual(
      Buffer.from(file),
    );
  });
});

function latestArtwork(changes: HostChange[]): string | null | undefined {
  const artwork = changes.filter((change) => change.kind === 'artwork').at(-1);

  return artwork?.kind === 'artwork' ? artwork.dataUrl : undefined;
}
