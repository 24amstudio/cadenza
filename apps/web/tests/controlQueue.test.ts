import { describe, expect, test } from 'bun:test';
import {
  ControlQueue,
  type ControlKey,
  type ControlPort,
} from '../app/lib/host/controlQueue';
import type { Readiness } from '../app/lib/host/client';
import type {
  CommandAction,
  CommandResult,
  Snapshot,
} from '../app/lib/protocol/types';

const firstSong = 'occurrence-1';
const secondSong = 'occurrence-2';

function snapshotOf(occurrenceId: string, revision = 18): Snapshot {
  return {
    hostId: 'host',
    hostEpoch: 'epoch',
    revision,
    sequence: 1,
    playing: true,
    volume: 40,
    current: {
      occurrenceId,
      entryId: null,
      requesterName: 'Mia',
      song: {
        source: 'catalog',
        id: '1',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200_000,
        artworkUrl: null,
      },
      positionMs: 0,
      sampledAtHostMs: 0,
    },
    queue: [],
    synchronized: true,
    issue: null,
  };
}

function resultOf(
  outcome: CommandResult['outcome'],
  errorCode: string | null = null,
  revision = 19,
): CommandResult {
  return { commandId: 'command', outcome, revision, message: null, errorCode };
}

// A port whose commands stay in flight until the test answers them.
class ScriptedPort implements ControlPort {
  snapshot: Snapshot | null = snapshotOf(firstSong);
  readiness: Readiness = 'ready';
  readonly sent: CommandAction[] = [];
  readonly revisionWaits: number[] = [];
  private readonly replies: ((result: CommandResult) => void)[] = [];

  awaitReadiness(): Promise<Readiness> {
    return Promise.resolve(this.readiness);
  }

  awaitRevision(minRevision: number): Promise<void> {
    this.revisionWaits.push(minRevision);

    return Promise.resolve();
  }

  latestSnapshot(): Snapshot | null {
    return this.snapshot;
  }

  send(action: CommandAction): Promise<CommandResult> {
    this.sent.push(action);

    return new Promise((resolve) => this.replies.push(resolve));
  }

  wait(): Promise<void> {
    return Promise.resolve();
  }

  reply(result: CommandResult): void {
    this.replies.shift()?.(result);
  }
}

class OutputLog {
  readonly pending: ReadonlySet<ControlKey>[] = [];
  readonly finished: [ControlKey, CommandResult][] = [];
  readonly notices: string[] = [];
}

function queueOver(port: ControlPort) {
  const log = new OutputLog();

  const queue = new ControlQueue(port, {
    pendingChanged: (pending) => log.pending.push(pending),
    finished: (key, result) => log.finished.push([key, result]),
    notice: (message) => log.notices.push(message),
  });

  return { queue, log };
}

function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function lastPending(log: OutputLog) {
  return [...(log.pending.at(-1) ?? [])];
}

describe('ControlQueue', () => {
  test('a press made while a command is in flight is sent after it, not lost', async () => {
    const port = new ScriptedPort();
    const { queue, log } = queueOver(port);

    queue.press({ key: 'next' });
    await tick();
    queue.press({ key: 'toggle' });
    await tick();

    expect(port.sent.map((action) => action.kind)).toEqual(['playback.skip']);
    expect(lastPending(log).sort()).toEqual(['next', 'toggle']);

    port.reply(resultOf('applied'));
    await tick();
    expect(port.sent.map((action) => action.kind)).toEqual([
      'playback.skip',
      'playback.pause',
    ]);

    port.reply(resultOf('applied'));
    await tick();
    expect(lastPending(log)).toEqual([]);
  });

  test('retries a stale revision once the newer state arrived, and releases the control', async () => {
    const port = new ScriptedPort();
    const { queue, log } = queueOver(port);

    queue.press({ key: 'next' });
    await tick();
    port.reply(resultOf('rejected', 'stale_revision', 21));
    await tick();

    // The retry waits for the revision that the refusal named.
    expect(port.revisionWaits).toEqual([21]);
    expect(port.sent).toHaveLength(2);
    expect(log.finished).toHaveLength(0);

    port.reply(resultOf('applied', null, 22));
    await tick();

    expect(log.finished).toMatchObject([['next', { outcome: 'applied' }]]);
    expect(lastPending(log)).toEqual([]);
  });

  test('gives up after two retries and reports the refusal', async () => {
    const port = new ScriptedPort();
    const { queue, log } = queueOver(port);

    queue.press({ key: 'previous' });

    for (let attempt = 0; attempt < 3; attempt += 1) {
      await tick();
      port.reply(resultOf('expired', 'expired'));
    }

    await tick();

    expect(port.sent).toHaveLength(3);
    expect(log.finished).toMatchObject([['previous', { outcome: 'expired' }]]);
    expect(lastPending(log)).toEqual([]);
  });

  test('never sends an unconfirmed command again, because it may have applied', async () => {
    const port = new ScriptedPort();
    const { queue, log } = queueOver(port);

    queue.press({ key: 'next' });
    await tick();
    port.reply(resultOf('unconfirmed', 'outcome_unknown', 0));
    await tick();

    expect(port.sent).toHaveLength(1);
    expect(log.finished).toMatchObject([['next', { outcome: 'unconfirmed' }]]);
  });

  test('folds presses that wait into the newest value', async () => {
    const port = new ScriptedPort();
    const { queue } = queueOver(port);

    queue.press({ key: 'toggle' });
    await tick();
    queue.press({ key: 'seek', positionMs: 1_000, occurrenceId: firstSong });
    queue.press({ key: 'seek', positionMs: 2_000, occurrenceId: firstSong });
    queue.press({ key: 'volume', percent: 10 });
    queue.press({ key: 'volume', percent: 30 });
    queue.press({ key: 'next' });
    queue.press({ key: 'next' });

    for (let sent = 0; sent < 4; sent += 1) {
      port.reply(resultOf('applied'));
      await tick();
    }

    expect(port.sent).toEqual([
      { kind: 'playback.pause', occurrenceId: firstSong },
      { kind: 'playback.seek', occurrenceId: firstSong, positionMs: 2_000 },
      { kind: 'playback.volume', percent: 30 },
      { kind: 'playback.skip', occurrenceId: firstSong },
    ]);
  });

  test('two waiting Play/Pause presses cancel out, as pressing twice does', async () => {
    const port = new ScriptedPort();
    const { queue } = queueOver(port);

    queue.press({ key: 'next' });
    await tick();
    queue.press({ key: 'toggle' });
    queue.press({ key: 'toggle' });
    port.reply(resultOf('applied'));
    await tick();

    expect(port.sent.map((action) => action.kind)).toEqual(['playback.skip']);
  });

  test('a position chosen on a song that has since changed is not sent', async () => {
    const port = new ScriptedPort();
    const { queue, log } = queueOver(port);

    queue.press({ key: 'toggle' });
    await tick();
    queue.press({ key: 'seek', positionMs: 5_000, occurrenceId: firstSong });
    port.snapshot = snapshotOf(secondSong, 19);
    port.reply(resultOf('applied'));
    await tick();

    expect(port.sent).toHaveLength(1);
    expect(log.notices).toEqual([
      'The song changed before that position was sent.',
    ]);
    expect(lastPending(log)).toEqual([]);
  });

  test('says so when the link is down, instead of ignoring the press', async () => {
    const port = new ScriptedPort();
    port.readiness = 'offline';
    const { queue, log } = queueOver(port);

    queue.press({ key: 'toggle' });
    await tick();

    expect(port.sent).toHaveLength(0);
    expect(log.notices).toEqual(['Cadenza Host is not connected.']);
    expect(lastPending(log)).toEqual([]);
  });
});
