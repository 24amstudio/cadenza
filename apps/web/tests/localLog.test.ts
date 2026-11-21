import { describe, expect, test } from 'bun:test';
import {
  LocalLog,
  localLogBatchLimit,
  localLogLimit,
  localLogStorageKey,
} from '../app/lib/host/localLog';

function memoryStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));

  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => void values.set(key, value),
    values,
  };
}

describe('LocalLog', () => {
  test('entries wait in the browser until they are forgotten, and survive a reload', () => {
    const storage = memoryStorage();
    const log = new LocalLog(() => storage);

    log.record('info', 'connection.closed', 'Socket closed');
    log.record('warning', 'command.result', 'Command unconfirmed');

    const reloaded = new LocalLog(() => storage);
    const pending = reloaded.pending();

    expect(pending.map((entry) => entry.action)).toEqual([
      'connection.closed',
      'command.result',
    ]);

    reloaded.forget([pending[0]?.id ?? -1]);

    expect(new LocalLog(() => storage).pending()).toHaveLength(1);
    expect(storage.values.has(localLogStorageKey)).toBe(true);
  });

  test('the oldest entries fall off, and one report carries at most a Host batch', () => {
    const log = new LocalLog(() => null);

    for (let index = 0; index < localLogLimit + 10; index++) {
      log.record('debug', 'out websocket state', `frame ${index}`);
    }

    expect(log.pending()).toHaveLength(localLogBatchLimit);
    expect(log.pending()[0]?.message).toBe('frame 10');
  });

  test('a stored list that is damaged keeps only the entries that are whole', () => {
    const stored = JSON.stringify([
      { id: 1, level: 'info', action: 'ok', message: 'kept' },
      { id: 2, level: 'loud', action: 'bad level', message: 'dropped' },
      'not an entry',
    ]);

    const log = new LocalLog(() =>
      memoryStorage({ [localLogStorageKey]: stored }),
    );

    expect(log.pending().map((entry) => entry.message)).toEqual(['kept']);
    expect(
      new LocalLog(() =>
        memoryStorage({ [localLogStorageKey]: '{' }),
      ).pending(),
    ).toEqual([]);
  });

  test('long text is clipped to the limits the Host accepts', () => {
    const log = new LocalLog(() => null);

    log.record('info', 'a'.repeat(300), 'm'.repeat(5_000));

    const [entry] = log.pending();
    expect(entry?.action).toHaveLength(120);
    expect(entry?.message).toHaveLength(2_000);
  });
});
