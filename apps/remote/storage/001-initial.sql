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

PRAGMA user_version = 1;
COMMIT;
