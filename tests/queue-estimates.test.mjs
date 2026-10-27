import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { openDatabase, pairRemotes, queueEntry } from './database.mjs';

const estimateSql = readFileSync(
  new URL('../apps/host/storage/queue-estimates.sql', import.meta.url),
  'utf8',
);

test('queue waits include the current remainder and preserve request attribution', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  queueEntry(database, 'current', 'remote-b', 100, 'current');
  queueEntry(database, 'a-next', 'remote-a', 10);
  queueEntry(database, 'b-next', 'remote-b', 20);
  queueEntry(database, 'already-played', 'remote-a', 0, 'completed');
  queueEntry(database, 'canceled', 'remote-a', 30, 'canceled');
  database.exec(
    "UPDATE queue_entries SET duration_ms = 240000 WHERE entry_id = 'b-next'",
  );

  const rows = database.prepare(estimateSql).all({ position_ms: 60000 });

  assert.deepEqual(
    rows.map((row) => row['entry_id']),
    ['current', 'a-next', 'b-next'],
  );
  assert.deepEqual(
    rows.map((row) => row['requested_by']),
    ['remote-b', 'remote-a', 'remote-b'],
  );
  assert.deepEqual(
    rows.map((row) => row['estimated_wait_ms']),
    [0, 120000, 300000],
  );
  assert.deepEqual(
    rows.map((row) => row['total_remaining_ms']),
    [540000, 540000, 540000],
  );

  const afterSeek = database.prepare(estimateSql).all({ position_ms: 999999 });

  assert.equal(afterSeek[1]?.['estimated_wait_ms'], 0);
  assert.equal(afterSeek[2]?.['total_remaining_ms'], 420000);
});

test('unknown durations propagate to downstream waits without inventing a total', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  queueEntry(database, 'current', 'remote-a', 0, 'current');
  queueEntry(database, 'unknown-duration', 'remote-a', 10);
  queueEntry(database, 'later', 'remote-b', 20);
  database.exec(
    "UPDATE queue_entries SET duration_ms = NULL WHERE entry_id = 'unknown-duration'",
  );

  const query = database.prepare(estimateSql);
  const rows = query.all({ position_ms: 60000 });

  assert.equal(rows[1]?.['estimated_wait_ms'], 120000);
  assert.equal(rows[2]?.['estimated_wait_ms'], null);
  assert.equal(rows[0]?.['total_remaining_ms'], null);
  assert.equal(
    query.all({ position_ms: null })[1]?.['estimated_wait_ms'],
    null,
  );
  database.exec('DELETE FROM queue_entries');
  assert.deepEqual(query.all({ position_ms: null }), []);
});

test('queue totals outside the protocol integer range remain unknown', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  queueEntry(database, 'very-long', 'remote-a', 10);
  queueEntry(database, 'after', 'remote-b', 20);
  database.exec(
    "UPDATE queue_entries SET duration_ms = 9007199254740991 WHERE entry_id = 'very-long'",
  );

  const rows = database.prepare(estimateSql).all({ position_ms: null });

  assert.equal(rows[1]?.['estimated_wait_ms'], 9007199254740991);
  assert.equal(rows[0]?.['total_remaining_ms'], null);
});
