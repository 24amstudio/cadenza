-- Fresh database migration. No SQLite STRICT or RETURNING dependency.
-- The native caller must roll back the transaction if a statement fails.
PRAGMA foreign_keys = ON;
PRAGMA auto_vacuum = INCREMENTAL;
BEGIN IMMEDIATE;

CREATE TABLE paired_hosts (
  host_id TEXT PRIMARY KEY NOT NULL,
  display_name TEXT NOT NULL CHECK(length(display_name) BETWEEN 1 AND 80),
  credential_reference TEXT NOT NULL UNIQUE,
  last_credit_sequence INTEGER NOT NULL DEFAULT 0 CHECK(typeof(last_credit_sequence) = 'integer' AND last_credit_sequence BETWEEN 0 AND 9007199254740991)
);

CREATE TABLE song_statistics (
  host_id TEXT NOT NULL REFERENCES paired_hosts(host_id),
  source TEXT NOT NULL CHECK(source IN ('catalog', 'library')),
  song_id TEXT NOT NULL,
  play_count INTEGER NOT NULL DEFAULT 0 CHECK(typeof(play_count) = 'integer' AND play_count BETWEEN 0 AND 9007199254740991),
  played_ms INTEGER NOT NULL DEFAULT 0 CHECK(typeof(played_ms) = 'integer' AND played_ms BETWEEN 0 AND 9007199254740991),
  PRIMARY KEY(host_id, source, song_id)
);

CREATE TABLE playback_credits (
  host_id TEXT NOT NULL REFERENCES paired_hosts(host_id),
  sequence INTEGER NOT NULL CHECK(typeof(sequence) = 'integer' AND sequence BETWEEN 1 AND 9007199254740991),
  event_id TEXT NOT NULL UNIQUE,
  occurrence_id TEXT NOT NULL,
  source TEXT NOT NULL CHECK(source IN ('catalog', 'library')),
  song_id TEXT NOT NULL,
  play_count_delta INTEGER NOT NULL CHECK(play_count_delta IN (0, 1)),
  played_ms_delta INTEGER NOT NULL CHECK(typeof(played_ms_delta) = 'integer' AND played_ms_delta BETWEEN 0 AND 9007199254740991),
  PRIMARY KEY(host_id, sequence),
  CHECK(play_count_delta = 0 OR played_ms_delta > 0)
);

CREATE TABLE counted_occurrences (
  host_id TEXT NOT NULL REFERENCES paired_hosts(host_id),
  occurrence_id TEXT NOT NULL,
  source TEXT NOT NULL CHECK(source IN ('catalog', 'library')),
  song_id TEXT NOT NULL,
  PRIMARY KEY(host_id, occurrence_id)
);

CREATE TRIGGER credit_ignores_replay
BEFORE INSERT ON playback_credits
WHEN NEW.sequence <= (SELECT last_credit_sequence FROM paired_hosts WHERE host_id = NEW.host_id)
BEGIN
  SELECT RAISE(IGNORE);
END;

CREATE TRIGGER credit_requires_contiguous_sequence
BEFORE INSERT ON playback_credits
WHEN NEW.sequence > (SELECT last_credit_sequence + 1 FROM paired_hosts WHERE host_id = NEW.host_id)
BEGIN
  SELECT RAISE(ABORT, 'credit_sequence_gap');
END;

CREATE TRIGGER credit_requires_valid_occurrence
BEFORE INSERT ON playback_credits
WHEN NEW.sequence > (SELECT last_credit_sequence FROM paired_hosts WHERE host_id = NEW.host_id)
  AND (
    (NEW.play_count_delta = 1 AND EXISTS (
      SELECT 1 FROM counted_occurrences
      WHERE host_id = NEW.host_id AND occurrence_id = NEW.occurrence_id
    ))
    OR (NEW.play_count_delta = 0 AND NOT EXISTS (
      SELECT 1 FROM counted_occurrences
      WHERE host_id = NEW.host_id AND occurrence_id = NEW.occurrence_id
        AND source = NEW.source AND song_id = NEW.song_id
    ))
  )
BEGIN
  SELECT RAISE(ABORT, 'invalid_playback_occurrence');
END;

CREATE TRIGGER credit_updates_statistics
AFTER INSERT ON playback_credits
BEGIN
  INSERT OR IGNORE INTO counted_occurrences(host_id, occurrence_id, source, song_id)
  VALUES (NEW.host_id, NEW.occurrence_id, NEW.source, NEW.song_id);

  INSERT OR IGNORE INTO song_statistics(host_id, source, song_id)
  VALUES (NEW.host_id, NEW.source, NEW.song_id);

  UPDATE song_statistics
  SET play_count = play_count + NEW.play_count_delta,
      played_ms = played_ms + NEW.played_ms_delta
  WHERE host_id = NEW.host_id AND source = NEW.source AND song_id = NEW.song_id;

  UPDATE paired_hosts SET last_credit_sequence = NEW.sequence WHERE host_id = NEW.host_id;
END;

CREATE INDEX most_played_songs ON song_statistics(host_id, play_count DESC, played_ms DESC);



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

CREATE TABLE remote_log_outbox (
  log_id INTEGER PRIMARY KEY AUTOINCREMENT,
  level TEXT NOT NULL CHECK(level IN ('debug','info','warning','error')),
  action TEXT NOT NULL CHECK(length(action) BETWEEN 1 AND 120),
  message TEXT NOT NULL CHECK(length(message) BETWEEN 1 AND 2000),
  created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0)
);
CREATE INDEX remote_log_outbox_order ON remote_log_outbox(log_id);



CREATE TABLE favorites (
  source TEXT NOT NULL CHECK(source IN ('catalog','library')),
  song_id TEXT NOT NULL,
  song_json TEXT NOT NULL CHECK(length(song_json) <= 16384),
  saved_at_ms INTEGER NOT NULL CHECK(saved_at_ms >= 0),
  PRIMARY KEY(source, song_id)
);


PRAGMA user_version=1;
COMMIT;
