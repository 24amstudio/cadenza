import { describe, expect, test } from 'bun:test';
import { ControlQueue } from '../app/lib/host/controlQueue';
import type {
  CommandResult,
  QueueActionKind,
  SongIdentity,
} from '../app/lib/protocol/types';
import {
  answerClockProbes,
  harness,
  occurrenceId,
  playingSnapshotFrame,
  snapshotFrame,
  socketAt,
  token,
  welcome,
  type Harness,
} from './support/hostClient';

const song: SongIdentity = { source: 'catalog', id: '1440857781' };

function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

// The same port the app gives its controls, so a request takes the same path as a playback press.
function queueFor(setup: Harness) {
  const settled: (CommandResult | null)[] = [];

  const queue = new ControlQueue(
    {
      awaitReadiness: (timeoutMs) => setup.client.awaitReadiness(timeoutMs),
      awaitRevision: (revision, timeoutMs) =>
        setup.client.awaitRevision(revision, timeoutMs),
      latestSnapshot: () => setup.client.latestSnapshot(),
      send: (action) => setup.client.sendCommand(action),
      wait: () => Promise.resolve(),
    },
    { pendingChanged: () => {}, finished: () => {}, notice: () => {} },
  );

  return {
    settled,
    press: (kind: QueueActionKind) =>
      queue.press({
        key: 'queue',
        kind,
        song,
        settled: (result) => settled.push(result),
      }),
  };
}

function connected(state: 'playing' | 'idle') {
  const setup = harness();

  setup.client.start('S'.repeat(43));
  const socket = socketAt(setup.sockets, 0);
  socket.open();
  socket.receive(welcome(token));
  socket.receive(
    state === 'playing' ? playingSnapshotFrame(18) : snapshotFrame(18),
  );
  answerClockProbes(socket, setup.clock);

  return setup;
}

describe('song requests through the command path', () => {
  test('a request is sent once, and not sent again after the link drops', async () => {
    const setup = connected('playing');
    const queue = queueFor(setup);

    queue.press('queue.enqueue');
    await tick();

    const first = socketAt(setup.sockets, 0);

    expect(first.framesOfType('command')).toHaveLength(1);
    expect(first.framesOfType('command')[0]?.action).toEqual({
      kind: 'queue.enqueue',
      song: { source: 'catalog', id: '1440857781' },
    });

    first.serverDrop();
    await tick();

    expect(queue.settled.map((result) => result?.outcome)).toEqual([
      'unconfirmed',
    ]);

    setup.clock.advance(30_000);
    const reconnected = socketAt(setup.sockets, 1);
    reconnected.open();
    reconnected.receive(welcome(token));
    reconnected.receive(playingSnapshotFrame(19));
    await tick();

    const commands = setup.sockets.flatMap((socket) =>
      socket.framesOfType('command'),
    );

    expect(commands).toHaveLength(1);
  });

  test('a request for Play next is accepted while nothing is playing', async () => {
    const setup = connected('idle');
    const queue = queueFor(setup);

    queue.press('queue.play_next');
    await tick();

    expect(
      socketAt(setup.sockets, 0).framesOfType('command')[0]?.action,
    ).toEqual({
      kind: 'queue.play_next',
      song: { source: 'catalog', id: '1440857781' },
    });
  });

  test('Play now names the song that is playing', async () => {
    const setup = connected('playing');
    const queue = queueFor(setup);

    queue.press('queue.play_now');
    await tick();

    expect(
      socketAt(setup.sockets, 0).framesOfType('command')[0]?.action,
    ).toEqual({
      kind: 'queue.play_now',
      song: { source: 'catalog', id: '1440857781' },
      occurrence_id: occurrenceId,
    });
  });
});
