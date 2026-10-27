-- Additive profile and display-cache migration. Analytics tables remain intact.
ALTER TABLE paired_hosts ADD COLUMN address TEXT NOT NULL DEFAULT '';
ALTER TABLE paired_hosts ADD COLUMN port INTEGER NOT NULL DEFAULT 43127 CHECK(port BETWEEN 1024 AND 65535);
ALTER TABLE paired_hosts ADD COLUMN fingerprint TEXT NOT NULL DEFAULT '';
ALTER TABLE paired_hosts ADD COLUMN remote_id TEXT NOT NULL DEFAULT '';
ALTER TABLE paired_hosts ADD COLUMN certificate_der_base64 TEXT NOT NULL DEFAULT '';

CREATE TABLE song_metadata (
  host_id TEXT NOT NULL REFERENCES paired_hosts(host_id),
  source TEXT NOT NULL,
  song_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  PRIMARY KEY(host_id,source,song_id)
);

CREATE TABLE pending_commands (
  host_id TEXT NOT NULL REFERENCES paired_hosts(host_id),
  remote_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  body_json TEXT NOT NULL,
  pending_key TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
  PRIMARY KEY(host_id,remote_id,command_id)
);

CREATE TABLE host_snapshots (
  host_id TEXT PRIMARY KEY REFERENCES paired_hosts(host_id),
  body_json TEXT NOT NULL,
  saved_at_ms INTEGER NOT NULL CHECK(saved_at_ms >= 0)
);

-- Settings and encrypted credential payloads share SQLite's checked transactions.
CREATE TABLE settings (
  key TEXT PRIMARY KEY NOT NULL CHECK(length(key) BETWEEN 1 AND 256),
  value TEXT NOT NULL CHECK(length(value) <= 16384)
);

PRAGMA user_version=2;
