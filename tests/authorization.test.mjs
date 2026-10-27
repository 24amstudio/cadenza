import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { openDatabase, pairRemotes, queueEntry } from './database.mjs';

const authorizeSql = readFileSync(
  new URL('../apps/host/storage/authorize-command.sql', import.meta.url),
  'utf8',
);

test('request protection covers pending requests and the current song, including seek bypasses', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  queueEntry(database, 'b-current', 'remote-b', 0, 'current');
  queueEntry(database, 'a-first', 'remote-a', 10);
  queueEntry(database, 'a-second', 'remote-a', 20);
  queueEntry(database, 'b-next', 'remote-b', 30);
  queueEntry(database, 'a-last', 'remote-a', 40);
  const query = database.prepare(authorizeSql);

  const base = {
    actor_id: 'remote-a',
    host_epoch: 'boot-one',
    now_host_ms: 1000,
    expires_at_host_ms: 1800,
    expected_revision: 0,
    before_entry_id: null,
  };

  for (const kind of [
    'playback.skip',
    'playback.seek',
    'playback.stop',
    'playback.previous',
  ]) {
    assert.equal(
      query.get({ ...base, kind, entry_id: 'b-current' })?.['decision'],
      'forbidden',
      kind,
    );
  }

  assert.equal(
    query.get({ ...base, kind: 'queue.play_next', entry_id: null })?.[
      'decision'
    ],
    'allowed',
  );
  assert.equal(
    query.get({ ...base, kind: 'queue.play_now', entry_id: 'b-current' })?.[
      'decision'
    ],
    'forbidden',
  );

  assert.equal(
    query.get({ ...base, kind: 'queue.remove', entry_id: 'b-next' })?.[
      'decision'
    ],
    'forbidden',
  );
  assert.equal(
    query.get({ ...base, kind: 'queue.remove', entry_id: 'a-first' })?.[
      'decision'
    ],
    'allowed',
  );
  assert.equal(
    query.get({
      ...base,
      kind: 'queue.move',
      entry_id: 'a-second',
      before_entry_id: 'a-first',
    })?.['decision'],
    'allowed',
  );
  assert.equal(
    query.get({
      ...base,
      kind: 'queue.move',
      entry_id: 'a-last',
      before_entry_id: 'a-first',
    })?.['decision'],
    'forbidden',
  );
  assert.equal(
    query.get({ ...base, kind: 'queue.move', entry_id: 'a-first' })?.[
      'decision'
    ],
    'forbidden',
  );
  assert.equal(
    query.get({ ...base, kind: 'playback.pause', entry_id: 'b-current' })?.[
      'decision'
    ],
    'allowed',
  );
  database.exec('UPDATE host_state SET allow_cross_remote_edits = 1');
  assert.equal(
    query.get({ ...base, kind: 'playback.seek', entry_id: 'b-current' })?.[
      'decision'
    ],
    'allowed',
  );
  assert.equal(
    query.get({ ...base, kind: 'queue.remove', entry_id: 'b-next' })?.[
      'decision'
    ],
    'allowed',
  );
});

test('expired, previous-boot, stale, revoked, and unknown commands are rejected', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  const query = database.prepare(authorizeSql);

  const base = {
    actor_id: 'remote-a',
    host_epoch: 'boot-one',
    now_host_ms: 1000,
    expires_at_host_ms: 1800,
    expected_revision: 0,
    before_entry_id: null,
    entry_id: null,
    kind: 'queue.enqueue',
  };

  assert.equal(
    query.get({ ...base, expires_at_host_ms: 1000 })?.['decision'],
    'expired',
  );
  assert.equal(
    query.get({ ...base, expires_at_host_ms: 2001 })?.['decision'],
    'invalid_deadline',
  );
  assert.equal(
    query.get({ ...base, host_epoch: 'previous-boot' })?.['decision'],
    'expired',
  );
  assert.equal(
    query.get({ ...base, expected_revision: 1 })?.['decision'],
    'stale_revision',
  );
  assert.equal(
    query.get({ ...base, kind: 'host.allow-everything' })?.['decision'],
    'invalid_command',
  );
  assert.equal(
    query.get({ ...base, kind: null })?.['decision'],
    'invalid_command',
  );
  assert.equal(
    query.get({ ...base, expires_at_host_ms: 2000 })?.['decision'],
    'allowed',
  );

  for (const value of [null, '1800', -1, 1000.5]) {
    assert.equal(
      query.get({ ...base, expires_at_host_ms: value })?.['decision'],
      'invalid_deadline',
    );
  }

  assert.equal(
    query.get({ ...base, expected_revision: 0.5 })?.['decision'],
    'invalid_command',
  );
  assert.equal(
    query.get({ ...base, actor_id: 'pretend-owner' })?.['decision'],
    'revoked',
  );
  database.exec(
    "UPDATE paired_remotes SET revoked_at_ms = 200 WHERE remote_id = 'remote-a'",
  );
  assert.equal(query.get(base)?.['decision'], 'revoked');
});

test('Cadenza Host-originated requests retain Host authority even when cross-Remote editing is allowed', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  queueEntry(database, 'host-current', null, 0, 'current');
  database.exec('UPDATE host_state SET allow_cross_remote_edits = 1');
  assert.equal(
    database.prepare(authorizeSql).get({
      actor_id: 'remote-a',
      host_epoch: 'boot-one',
      now_host_ms: 1000,
      expires_at_host_ms: 1500,
      expected_revision: 0,
      before_entry_id: null,
      entry_id: 'host-current',
      kind: 'playback.skip',
    })?.['decision'],
    'forbidden',
  );
});

test('unbound native playback allows transport controls without bypassing request ownership', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());

  pairRemotes(database);

  const query = database.prepare(authorizeSql);

  const base = {
    actor_id: 'remote-a',
    host_epoch: 'boot-one',
    now_host_ms: 1000,
    expires_at_host_ms: 1500,
    expected_revision: 0,
    before_entry_id: null,
    entry_id: null,
  };

  for (const kind of [
    'playback.skip',
    'playback.previous',
    'playback.stop',
    'playback.seek',
  ]) {
    assert.equal(query.get({ ...base, kind })?.['decision'], 'allowed', kind);
  }
});
