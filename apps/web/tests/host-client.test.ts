import { describe, expect, test } from 'bun:test';
import type { HostChange } from '../app/lib/host/client';
import {
  counterField,
  isJsonObject,
  objectField,
} from '../app/lib/protocol/json';
import {
  FakeSocket,
  MemoryCredentials,
  answerClockProbes,
  epoch,
  harness,
  hostOffsetMs,
  occurrenceId,
  phases,
  remoteId,
  results,
  snapshotFrame,
  socketAt,
  token,
  welcome,
} from './support/hostClient';

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

  test('settles a command the Host never answers as unconfirmed, then reports its late result', async () => {
    const { client, sockets, clock, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token));
    socketAt(sockets, 0).receive(snapshotFrame(18));
    answerClockProbes(socketAt(sockets, 0), clock);

    const pending = client.sendCommand({
      kind: 'playback.pause',
      occurrenceId,
    });

    const commandId = String(
      socketAt(sockets, 0).framesOfType('command')[0]?.command_id,
    );

    clock.advance(4_000);

    expect(await pending).toMatchObject({ commandId, outcome: 'unconfirmed' });

    socketAt(sockets, 0).receive({
      type: 'command.result',
      command_id: commandId,
      host_epoch: epoch,
      outcome: 'applied',
      revision: 19,
    });

    expect(results(changes)).toEqual([
      expect.objectContaining({ commandId, outcome: 'applied' }),
    ]);
    expect(socketAt(sockets, 0).framesOfType('command')).toHaveLength(1);
  });

  test('does not request artwork that the Host did not advertise', () => {
    const { client, sockets, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, []));

    client.requestArtwork('https://example.com/cover.jpg', { kind: 'preview' });

    expect(socketAt(sockets, 0).framesOfType('artwork.get')).toHaveLength(0);
    expect(changes).toContainEqual({
      kind: 'artwork',
      artworkUrl: 'https://example.com/cover.jpg',
      dataUrl: null,
      full: true,
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

    client.requestArtwork(artworkUrl, {
      kind: 'full',
      occurrenceId,
    });

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

describe('HostClient status report', () => {
  test('reports its Bluetooth path and measured round trip, so the Host shows it as connected', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Desk',
      lastCreditSequence: 0,
    };
    const { client, clock } = harness(credentials);
    const link = new FakeSocket();

    client.startBluetooth(false);
    client.connectOverBluetooth(link);
    link.receive(welcome(null));
    answerClockProbes(link, clock);

    const report = link.framesOfType('session.status').at(-1);

    expect(report).toMatchObject({
      type: 'session.status',
      status: {
        device: 'remote',
        paths: [{ transport: 'ble', state: 'connected', rtt_ms: 10 }],
      },
    });
    const status = report?.status;

    expect(
      isJsonObject(status) && Number.isInteger(status.reported_at_ms),
    ).toBe(true);
  });
});

function latestArtwork(changes: HostChange[]): string | null | undefined {
  const artwork = changes.filter((change) => change.kind === 'artwork').at(-1);

  return artwork?.kind === 'artwork' ? artwork.dataUrl : undefined;
}
