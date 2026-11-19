import { describe, expect, test } from 'bun:test';
import { ControlQueue } from '../app/lib/host/controlQueue';
import type { CommandResult } from '../app/lib/protocol/types';
import {
  answerClockProbes,
  epoch,
  harness,
  occurrenceId,
  playingSnapshotFrame,
  socketAt,
  token,
  welcome,
} from './support/hostClient';

function connected(roundTripMs = 10) {
  const setup = harness();
  const socket = () => socketAt(setup.sockets, 0);

  setup.client.start('S'.repeat(43));
  socket().open();
  socket().receive(welcome(token));
  socket().receive(playingSnapshotFrame(18));
  answerClockProbes(socket(), setup.clock, roundTripMs);

  return { ...setup, socket };
}

function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('command deadlines', () => {
  test('use the widest window the Host accepts on a fast link', () => {
    const { client, socket } = connected(10);
    const hostNow = client.hostNowMs() ?? 0;

    void client.sendCommand({ kind: 'playback.skip', occurrenceId });

    const remainingMs =
      Number(socket().framesOfType('command')[0]?.expires_at_host_ms) - hostNow;

    // The old 900 ms deadline left 100 ms of the Host's second unused before the link's own share.
    expect(remainingMs).toBeGreaterThan(950);
    expect(remainingMs).toBeLessThanOrEqual(1_000);
  });

  test('shrink with the measured round trip on a slow link, and stay inside the Host window', () => {
    const { client, socket } = connected(400);
    const hostNow = client.hostNowMs() ?? 0;

    void client.sendCommand({ kind: 'playback.skip', occurrenceId });

    const remainingMs =
      Number(socket().framesOfType('command')[0]?.expires_at_host_ms) - hostNow;

    // 1000 ms limit, less 25 ms of margin and half of the 400 ms round trip.
    expect(remainingMs).toBeGreaterThanOrEqual(774);
    expect(remainingMs).toBeLessThanOrEqual(776);
  });

  test('a command can go out after the first clock reply, without waiting for the whole burst', async () => {
    const { client, sockets } = harness();

    client.start('S'.repeat(43));
    const socket = socketAt(sockets, 0);
    socket.open();
    socket.receive(welcome(token));
    socket.receive(playingSnapshotFrame(18));
    expect(client.readiness()).toBe('syncing');

    const probe = socket.framesOfType('clock')[0];
    const waiting = client.awaitReadiness(3_000);

    socket.receive({
      type: 'clock',
      request_id: probe?.request_id ?? null,
      clock: {
        sent_at_remote_ms: 0,
        received_at_host_ms: 1_005,
        sent_at_host_ms: 1_005,
      },
    });

    expect(await waiting).toBe('ready');
    expect(client.readiness()).toBe('ready');
  });
});

describe('controls over a live session', () => {
  test('a rejected stale revision is retried against the newer state and leaves the controls free', async () => {
    const { client, socket, clock } = connected();
    const finished: CommandResult[] = [];
    let pending: string[] = [];

    const queue = new ControlQueue(
      {
        awaitReadiness: (timeoutMs) => client.awaitReadiness(timeoutMs),
        awaitRevision: (minRevision, timeoutMs) =>
          client.awaitRevision(minRevision, timeoutMs),
        latestSnapshot: () => client.latestSnapshot(),
        send: (action) => client.sendCommand(action),
        wait: (ms) => new Promise((resolve) => clock.schedule(resolve, ms)),
      },
      {
        pendingChanged: (keys) => {
          pending = [...keys];
        },
        finished: (_key, result) => finished.push(result),
        notice: () => undefined,
      },
    );

    queue.press({ key: 'next' });
    await tick();
    const first = socket().framesOfType('command')[0];

    expect(first).toMatchObject({ expected_revision: 18 });
    expect(pending).toEqual(['next']);

    // The queue moved on between the press and the Host's check.
    socket().receive({
      type: 'command.result',
      command_id: first?.command_id,
      host_epoch: epoch,
      outcome: 'rejected',
      error_code: 'stale_revision',
      revision: 19,
    });
    await tick();
    expect(socket().framesOfType('command')).toHaveLength(1);

    socket().receive(playingSnapshotFrame(19));
    await tick();

    const second = socket().framesOfType('command')[1];

    expect(second).toMatchObject({ expected_revision: 19 });
    expect(second?.command_id).not.toBe(first?.command_id);

    socket().receive({
      type: 'command.result',
      command_id: second?.command_id,
      host_epoch: epoch,
      outcome: 'applied',
      revision: 20,
    });
    await tick();

    expect(finished).toMatchObject([{ outcome: 'applied' }]);
    expect(pending).toEqual([]);
  });
});

// The control queue wired as the earlier tests wire it, collecting each finished press and the pending controls.
function queueFor({ client, clock }: ReturnType<typeof connected>) {
  const finished: CommandResult[] = [];
  let pending: string[] = [];

  const queue = new ControlQueue(
    {
      awaitReadiness: (timeoutMs) => client.awaitReadiness(timeoutMs),
      awaitRevision: (minRevision, timeoutMs) =>
        client.awaitRevision(minRevision, timeoutMs),
      latestSnapshot: () => client.latestSnapshot(),
      send: (action) => client.sendCommand(action),
      wait: (ms) => new Promise((resolve) => clock.schedule(resolve, ms)),
    },
    {
      pendingChanged: (keys) => {
        pending = [...keys];
      },
      finished: (_key, result) => finished.push(result),
      notice: () => undefined,
    },
  );

  return { queue, finished, pendingKeys: () => pending };
}

describe('refused commands', () => {
  test('an error that names a pending command settles it at once as rejected, and the controls unlock', async () => {
    const setup = connected();
    const socket = () => socketAt(setup.sockets, 0);
    const { queue, finished, pendingKeys } = queueFor(setup);
    const message = 'The command contains unexpected or missing fields.';

    queue.press({ key: 'next' });
    await tick();
    const sent = socket().framesOfType('command')[0];

    socket().receive({
      type: 'error',
      command_id: sent?.command_id,
      error_code: 'invalid_command',
      message,
    });
    await tick();

    expect(finished).toMatchObject([
      { outcome: 'rejected', errorCode: 'invalid_command', message },
    ]);
    expect(pendingKeys()).toEqual([]);

    // Past the settle deadline the refused command is neither reported as unconfirmed nor sent again.
    setup.clock.advance(5_000);
    await tick();
    expect(finished).toHaveLength(1);
    expect(socket().framesOfType('command')).toHaveLength(1);
  });

  test('an error that names no pending command is still shown as a notice', () => {
    const setup = connected();

    socketAt(setup.sockets, 0).receive({
      type: 'error',
      command_id: 'no-such-command',
      error_code: 'invalid_command',
      message: 'The command contains unexpected or missing fields.',
    });

    expect(setup.changes).toContainEqual({
      kind: 'notice',
      message: 'The command contains unexpected or missing fields.',
    });
  });
});
