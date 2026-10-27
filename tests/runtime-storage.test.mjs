import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { openDatabase, pairRemotes, queueEntry } from './database.mjs';

/** @param {'host' | 'remote'} application */
function migration(application) {
  return readFileSync(
    new URL(
      '../apps/' + application + '/storage/002-runtime.sql',
      import.meta.url,
    ),
    'utf8',
  );
}

test('Host runtime migration preserves ownership and advances credit allocation past existing delivery data', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  queueEntry(database, 'saved-request', 'remote-a', 1024);
  database.exec(
    "INSERT INTO playback_credit_outbox VALUES ('remote-a',7,'event','occurrence','catalog','100',1,500,0)",
  );
  database.exec(migration('host'));
  assert.equal(
    database.prepare('PRAGMA user_version').get()?.['user_version'],
    2,
  );
  assert.equal(
    database
      .prepare(
        "SELECT requested_by FROM queue_entries WHERE entry_id='saved-request'",
      )
      .get()?.['requested_by'],
    'remote-a',
  );
  assert.equal(
    database
      .prepare(
        "SELECT next_credit_sequence FROM paired_remotes WHERE remote_id='remote-a'",
      )
      .get()?.['next_credit_sequence'],
    8,
  );
  assert.throws(
    () =>
      database.exec(
        "UPDATE queue_entries SET requested_by='remote-b' WHERE entry_id='saved-request'",
      ),
    /request_owner_is_immutable/,
  );
  database.exec(
    "UPDATE queue_entries SET native_confirmed=0 WHERE entry_id='saved-request'",
  );
  database.exec(
    "INSERT INTO command_intents VALUES ('remote-a','command','digest','{}','{}','prepared',1000)",
  );
  assert.throws(
    () => database.exec("UPDATE command_intents SET phase='silently_done'"),
    /CHECK/,
  );
});

test('Remote runtime migration retains analytics and stores unresolved commands independently of event cleanup', (t) => {
  const database = openDatabase('remote');
  t.after(() => database.close());
  database.exec(
    "INSERT INTO paired_hosts(host_id,display_name,credential_reference) VALUES ('host','Mac','key-ref')",
  );
  database.exec(
    "INSERT INTO playback_credits VALUES ('host',1,'event','occurrence','catalog','100',1,2500)",
  );
  database.exec('BEGIN IMMEDIATE');
  database.exec(migration('remote'));
  database.exec('COMMIT');
  database.exec(
    "UPDATE paired_hosts SET remote_id='remote-a',address='192.168.1.2',fingerprint='public-pin' WHERE host_id='host'",
  );
  database.exec(
    "INSERT INTO pending_commands VALUES ('host','remote-a','command','{\"type\":\"command\"}','enqueue:100',1000)",
  );
  database.exec('DELETE FROM playback_credits');
  assert.equal(
    database.prepare('SELECT play_count FROM song_statistics').get()?.[
      'play_count'
    ],
    1,
  );
  assert.equal(
    database.prepare('SELECT played_ms FROM song_statistics').get()?.[
      'played_ms'
    ],
    2500,
  );
  assert.equal(
    database.prepare('SELECT last_credit_sequence FROM paired_hosts').get()?.[
      'last_credit_sequence'
    ],
    1,
  );
  assert.equal(
    database.prepare('SELECT pending_key FROM pending_commands').get()?.[
      'pending_key'
    ],
    'enqueue:100',
  );
  assert.equal(
    database.prepare('PRAGMA user_version').get()?.['user_version'],
    2,
  );
});

test('Host automatic maintenance preserves live requests, unresolved commands, and unacknowledged playback metadata', (t) => {
  const database = openDatabase('host');

  t.after(() => database.close());
  pairRemotes(database);
  database.exec(migration('host'));
  queueEntry(database, 'pending', 'remote-a', 1024);
  queueEntry(database, 'current', 'remote-a', 0, 'current');
  queueEntry(database, 'held', 'remote-b', 2048, 'completed');
  queueEntry(database, 'finished', 'remote-a', 3072, 'completed');
  queueEntry(database, 'cancelled', 'remote-a', 4096, 'canceled');
  database.exec(`
    UPDATE host_state SET current_occurrence_id='current-occurrence';
    INSERT INTO playback_sessions VALUES ('current-occurrence','current','remote-a','catalog','100',1);
    INSERT INTO playback_sessions VALUES ('held-occurrence','held','remote-b','catalog','100',1);
    INSERT INTO playback_sessions VALUES ('finished-occurrence','finished','remote-a','catalog','100',1);
    INSERT INTO playback_credit_outbox VALUES ('remote-b',1,'held-event','held-occurrence','catalog','100',1,500,0);
    INSERT INTO playback_credit_outbox VALUES ('remote-a',1,'finished-event','finished-occurrence','catalog','100',1,500,1);
    INSERT INTO command_intents VALUES ('remote-a','unknown','digest','{}',NULL,'dispatched',0);
    INSERT INTO command_intents VALUES ('remote-a','complete','digest','{}',NULL,'complete',0);
  `);

  const receipt = database.prepare(
    'INSERT INTO command_receipts(remote_id,command_id,payload_sha256,outcome,revision,created_at_ms) VALUES (?,?,?,?,?,?)',
  );

  receipt.run('remote-a', 'unknown', '0'.repeat(64), 'unconfirmed', 0, 0);
  receipt.run('remote-a', 'complete', '0'.repeat(64), 'applied', 0, 0);

  const maintenance = readFileSync(
    new URL('../apps/host/storage/maintenance.sql', import.meta.url),
    'utf8',
  );

  database.exec(maintenance);
  assert.deepEqual(
    database
      .prepare('SELECT entry_id FROM queue_entries ORDER BY entry_id')
      .all()
      .map((row) => row['entry_id']),
    ['current', 'held', 'pending'],
  );
  assert.equal(
    database.prepare('SELECT command_id FROM command_receipts').get()?.[
      'command_id'
    ],
    'unknown',
  );
  assert.equal(
    database.prepare('SELECT command_id FROM command_intents').get()?.[
      'command_id'
    ],
    'unknown',
  );
  assert.equal(
    database.prepare('SELECT event_id FROM playback_credit_outbox').get()?.[
      'event_id'
    ],
    'held-event',
  );
  assert.deepEqual(
    database
      .prepare(
        'SELECT occurrence_id FROM playback_sessions ORDER BY occurrence_id',
      )
      .all()
      .map((row) => row['occurrence_id']),
    ['current-occurrence', 'held-occurrence'],
  );
});
