import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { openDatabase, pairRemotes, queueEntry } from './database.mjs';

test('Host preserves separate song requests, immutable owners, and one current entry', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);
  queueEntry(database, 'request-one', 'remote-a', 10, 'current');
  queueEntry(database, 'request-two', 'remote-b', 20);
  assert.equal(
    database.prepare('SELECT count(*) AS total FROM queue_entries').get()?.[
      'total'
    ],
    2,
  );
  assert.throws(
    () =>
      database
        .prepare('UPDATE queue_entries SET requested_by = ? WHERE entry_id = ?')
        .run('remote-b', 'request-one'),
    /request_owner_is_immutable/,
  );
  assert.throws(
    () =>
      database
        .prepare(
          "UPDATE queue_entries SET state = 'current' WHERE entry_id = ?",
        )
        .run('request-two'),
    /UNIQUE/,
  );
  assert.throws(
    () =>
      database
        .prepare('UPDATE queue_entries SET duration_ms = -1 WHERE entry_id = ?')
        .run('request-two'),
    /CHECK/,
  );
  database.exec(
    "UPDATE paired_remotes SET revoked_at_ms = 200 WHERE remote_id = 'remote-a'",
  );
  assert.throws(
    () => queueEntry(database, 'request-three', 'remote-a', 30),
    /requester_is_not_active/,
  );
  assert.equal(
    database.prepare('SELECT allow_cross_remote_edits FROM host_state').get()?.[
      'allow_cross_remote_edits'
    ],
    0,
  );
});

test('command receipts cannot silently overwrite a prior outcome or accept a missing Remote', (t) => {
  const database = openDatabase('host');
  t.after(() => database.close());
  pairRemotes(database);

  const insert = database.prepare(
    'INSERT INTO command_receipts(remote_id,command_id,payload_sha256,outcome,revision,created_at_ms) VALUES (?, ?, ?, ?, ?, ?)',
  );

  insert.run('remote-a', 'command-one', 'a'.repeat(64), 'applied', 1, 1000);
  assert.throws(
    () =>
      insert.run('remote-a', 'command-one', 'b'.repeat(64), 'applied', 2, 1001),
    /UNIQUE/,
  );
  assert.throws(
    () =>
      insert.run(
        'missing-remote',
        'command-two',
        'a'.repeat(64),
        'applied',
        1,
        1000,
      ),
    /FOREIGN KEY/,
  );
  assert.equal(
    database.prepare('SELECT revision FROM command_receipts').get()?.[
      'revision'
    ],
    1,
  );
});

test('Remote analytics are ordered, exactly once, and survive raw-event compaction', (t) => {
  const database = openDatabase('remote');
  t.after(() => database.close());
  database
    .prepare(
      'INSERT INTO paired_hosts(host_id, display_name, credential_reference) VALUES (?, ?, ?)',
    )
    .run('host', 'Mac', 'keystore-reference');

  const insert = database.prepare(
    'INSERT INTO playback_credits VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  );

  insert.run('host', 1, 'event-one', 'play-one', 'catalog', '100', 1, 1000);
  insert.run('host', 1, 'event-one', 'play-one', 'catalog', '100', 1, 1000);
  insert.run('host', 2, 'event-two', 'play-one', 'catalog', '100', 0, 2500);
  assert.throws(
    () =>
      insert.run(
        'host',
        4,
        'event-four',
        'play-one',
        'catalog',
        '100',
        0,
        4000,
      ),
    /credit_sequence_gap/,
  );
  assert.throws(
    () =>
      insert.run(
        'host',
        3,
        'bad-recount',
        'play-one',
        'catalog',
        '100',
        1,
        1000,
      ),
    /invalid_playback_occurrence/,
  );
  assert.equal(
    database.prepare('SELECT played_ms FROM song_statistics').get()?.[
      'played_ms'
    ],
    3500,
  );
  database.exec('DELETE FROM playback_credits');
  insert.run('host', 1, 'event-one', 'play-one', 'catalog', '100', 1, 1000);
  insert.run('host', 3, 'event-three', 'play-two', 'catalog', '100', 1, 500);

  const statistics = database
    .prepare('SELECT play_count, played_ms FROM song_statistics')
    .get();

  assert.equal(statistics?.['play_count'], 2);
  assert.equal(statistics?.['played_ms'], 4000);
  assert.equal(
    database.prepare('SELECT last_credit_sequence FROM paired_hosts').get()?.[
      'last_credit_sequence'
    ],
    3,
  );
});

test('invalid credits roll back their sequence and aggregate changes', (t) => {
  const database = openDatabase('remote');
  t.after(() => database.close());
  database.exec(
    "INSERT INTO paired_hosts(host_id, display_name, credential_reference) VALUES ('host', 'Mac', 'key')",
  );

  const insert = database.prepare(
    'INSERT INTO playback_credits VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  );

  assert.throws(
    () =>
      insert.run(
        'host',
        1,
        'bad-negative',
        'play-one',
        'catalog',
        '100',
        1,
        -1,
      ),
    /CHECK/,
  );
  assert.equal(
    database.prepare('SELECT last_credit_sequence FROM paired_hosts').get()?.[
      'last_credit_sequence'
    ],
    0,
  );
  assert.equal(
    database.prepare('SELECT count(*) AS total FROM song_statistics').get()?.[
      'total'
    ],
    0,
  );
  insert.run('host', 1, 'valid-start', 'play-one', 'catalog', '100', 1, 1);
  assert.throws(
    () =>
      insert.run(
        'host',
        2,
        'different-song',
        'play-one',
        'catalog',
        '200',
        0,
        1000,
      ),
    /invalid_playback_occurrence/,
  );
});

test('SQLite analytics persist across connection close and reopen', () => {
  const directory = mkdtempSync(join(tmpdir(), 'cadenza-storage-'));
  const path = join(directory, 'remote.sqlite');
  let database = openDatabase('remote', path);

  try {
    database.exec(
      "INSERT INTO paired_hosts(host_id, display_name, credential_reference) VALUES ('host', 'Mac', 'key')",
    );
    database.exec(
      "INSERT INTO playback_credits VALUES ('host', 1, 'event-one', 'play-one', 'catalog', '100', 1, 1200)",
    );
    database.close();
    database = new DatabaseSync(path);
    assert.equal(
      database.prepare('PRAGMA user_version').get()?.['user_version'],
      1,
    );
    assert.equal(
      database.prepare('SELECT played_ms FROM song_statistics').get()?.[
        'played_ms'
      ],
      1200,
    );
    assert.equal(
      database.prepare('SELECT last_credit_sequence FROM paired_hosts').get()?.[
        'last_credit_sequence'
      ],
      1,
    );
  } finally {
    database.close();
    rmSync(path);
    rmdirSync(directory);
  }
});
