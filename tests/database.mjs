import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

/** @param {'host' | 'remote'} application @param {string} [path] */
export function openDatabase(application, path = ':memory:') {
  const database = new DatabaseSync(path);
  database.exec(
    readFileSync(
      new URL(
        `../apps/${application}/storage/001-initial.sql`,
        import.meta.url,
      ),
      'utf8',
    ),
  );

  return database;
}

/** @param {DatabaseSync} database */
export function pairRemotes(database) {
  const insert = database.prepare(
    'INSERT INTO paired_remotes(remote_id, display_name, credential_reference, paired_at_ms) VALUES (?, ?, ?, ?)',
  );

  insert.run('remote-a', 'Tablet A', 'keychain-a', 100);
  insert.run('remote-b', 'Tablet B', 'keychain-b', 100);
  database.exec("UPDATE host_state SET runtime_epoch = 'boot-one'");
}

/** @param {DatabaseSync} database @param {string} entry @param {string | null} owner @param {number} order @param {'pending' | 'current' | 'completed' | 'canceled'} [state] */
export function queueEntry(database, entry, owner, order, state = 'pending') {
  database
    .prepare(
      'INSERT INTO queue_entries(entry_id, requested_by, source, song_id, title, artist, duration_ms, sort_key, state, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    )
    .run(
      entry,
      owner,
      'catalog',
      '100',
      'Example song',
      'Example artist',
      180000,
      order,
      state,
      100,
    );
}
