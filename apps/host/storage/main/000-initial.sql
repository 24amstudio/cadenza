-- Fresh database migration. Apply once when user_version is 0.
-- The native caller must roll back the transaction if a statement fails.
PRAGMA foreign_keys = ON;
PRAGMA auto_vacuum = INCREMENTAL;
BEGIN IMMEDIATE;

CREATE TABLE paired_remotes (
  remote_id TEXT PRIMARY KEY NOT NULL,
  display_name TEXT NOT NULL CHECK(length(display_name) BETWEEN 1 AND 80),
  credential_reference TEXT NOT NULL UNIQUE,
  paired_at_ms INTEGER NOT NULL CHECK(typeof(paired_at_ms) = 'integer' AND paired_at_ms >= 0),
  revoked_at_ms INTEGER CHECK(revoked_at_ms IS NULL OR (typeof(revoked_at_ms) = 'integer' AND revoked_at_ms >= paired_at_ms))
);

CREATE TABLE host_state (
  singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
  runtime_epoch TEXT,
  queue_revision INTEGER NOT NULL DEFAULT 0 CHECK(typeof(queue_revision) = 'integer' AND queue_revision BETWEEN 0 AND 9007199254740991),
  allow_cross_remote_edits INTEGER NOT NULL DEFAULT 0 CHECK(allow_cross_remote_edits IN (0, 1))
);
INSERT INTO host_state(singleton) VALUES (1);

CREATE TABLE queue_entries (
  entry_id TEXT PRIMARY KEY NOT NULL,
  requested_by TEXT REFERENCES paired_remotes(remote_id),
  source TEXT NOT NULL CHECK(source IN ('catalog', 'library')),
  song_id TEXT NOT NULL CHECK(length(song_id) BETWEEN 1 AND 64),
  title TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 500),
  artist TEXT NOT NULL CHECK(length(artist) <= 500),
  duration_ms INTEGER CHECK(duration_ms IS NULL OR (typeof(duration_ms) = 'integer' AND duration_ms BETWEEN 0 AND 9007199254740991)),
  sort_key INTEGER NOT NULL CHECK(typeof(sort_key) = 'integer'),
  state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending', 'current', 'completed', 'canceled')),
  created_at_ms INTEGER NOT NULL CHECK(typeof(created_at_ms) = 'integer' AND created_at_ms >= 0)
);
CREATE UNIQUE INDEX queue_active_order ON queue_entries(sort_key) WHERE state IN ('pending', 'current');
CREATE UNIQUE INDEX queue_single_current ON queue_entries(state) WHERE state = 'current';
CREATE INDEX queue_owner ON queue_entries(requested_by, state);

CREATE TRIGGER queue_owner_is_immutable
BEFORE UPDATE OF requested_by ON queue_entries
WHEN NEW.requested_by IS NOT OLD.requested_by
BEGIN
  SELECT RAISE(ABORT, 'request_owner_is_immutable');
END;

CREATE TRIGGER queue_requester_must_be_active
BEFORE INSERT ON queue_entries
WHEN NEW.requested_by IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM paired_remotes WHERE remote_id = NEW.requested_by AND revoked_at_ms IS NULL
)
BEGIN
  SELECT RAISE(ABORT, 'requester_is_not_active');
END;

CREATE TABLE command_receipts (
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id),
  command_id TEXT NOT NULL,
  payload_sha256 TEXT NOT NULL CHECK(length(payload_sha256) = 64 AND payload_sha256 NOT GLOB '*[^0-9a-f]*'),
  outcome TEXT NOT NULL CHECK(outcome IN ('applied', 'rejected', 'expired', 'unconfirmed')),
  revision INTEGER NOT NULL CHECK(typeof(revision) = 'integer' AND revision BETWEEN 0 AND 9007199254740991),
  created_at_ms INTEGER NOT NULL CHECK(typeof(created_at_ms) = 'integer' AND created_at_ms >= 0),
  PRIMARY KEY(remote_id, command_id)
);

CREATE TABLE playback_credit_outbox (
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id),
  sequence INTEGER NOT NULL CHECK(typeof(sequence) = 'integer' AND sequence BETWEEN 1 AND 9007199254740991),
  event_id TEXT NOT NULL UNIQUE,
  occurrence_id TEXT NOT NULL,
  source TEXT NOT NULL CHECK(source IN ('catalog', 'library')),
  song_id TEXT NOT NULL,
  play_count_delta INTEGER NOT NULL CHECK(play_count_delta IN (0, 1)),
  played_ms_delta INTEGER NOT NULL CHECK(typeof(played_ms_delta) = 'integer' AND played_ms_delta BETWEEN 0 AND 9007199254740991),
  acknowledged INTEGER NOT NULL DEFAULT 0 CHECK(acknowledged IN (0, 1)),
  PRIMARY KEY(remote_id, sequence),
  CHECK(play_count_delta = 0 OR played_ms_delta > 0)
);
CREATE INDEX credit_pending_delivery ON playback_credit_outbox(remote_id, sequence) WHERE acknowledged = 0;
CREATE UNIQUE INDEX credit_counts_occurrence_once ON playback_credit_outbox(remote_id, occurrence_id) WHERE play_count_delta = 1;




ALTER TABLE paired_remotes ADD COLUMN next_credit_sequence INTEGER NOT NULL DEFAULT 1 CHECK(next_credit_sequence BETWEEN 1 AND 9007199254740991);
UPDATE paired_remotes SET next_credit_sequence=coalesce((
  SELECT max(sequence)+1 FROM playback_credit_outbox WHERE remote_id=paired_remotes.remote_id
),1);
ALTER TABLE queue_entries ADD COLUMN album TEXT NOT NULL DEFAULT '';
ALTER TABLE queue_entries ADD COLUMN artwork_url TEXT;
ALTER TABLE queue_entries ADD COLUMN song_url TEXT;
ALTER TABLE queue_entries ADD COLUMN native_token TEXT;
ALTER TABLE queue_entries ADD COLUMN native_confirmed INTEGER NOT NULL DEFAULT 1 CHECK(native_confirmed IN (0,1));
ALTER TABLE host_state ADD COLUMN current_occurrence_id TEXT;
ALTER TABLE host_state ADD COLUMN current_native_id TEXT;
ALTER TABLE host_state ADD COLUMN observation_gap INTEGER NOT NULL DEFAULT 0 CHECK(observation_gap IN (0, 1));
ALTER TABLE command_receipts ADD COLUMN error_code TEXT;
ALTER TABLE command_receipts ADD COLUMN response_json TEXT;

CREATE TABLE command_intents (
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id),
  command_id TEXT NOT NULL,
  payload_sha256 TEXT NOT NULL,
  command_json TEXT NOT NULL,
  plan_json TEXT,
  phase TEXT NOT NULL CHECK(phase IN ('prepared', 'dispatched', 'complete')),
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY(remote_id, command_id)
);

CREATE TABLE playback_sessions (
  occurrence_id TEXT PRIMARY KEY NOT NULL,
  entry_id TEXT REFERENCES queue_entries(entry_id),
  requested_by TEXT REFERENCES paired_remotes(remote_id),
  source TEXT NOT NULL CHECK(source IN ('catalog', 'library')),
  song_id TEXT NOT NULL,
  counted INTEGER NOT NULL DEFAULT 0 CHECK(counted IN (0, 1))
);

CREATE INDEX incomplete_commands ON command_intents(phase) WHERE phase != 'complete';


CREATE TABLE IF NOT EXISTS cache_entries (
    cache_key TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK(kind IN ('lyrics', 'artwork', 'animated_artwork', 'provider')),
    payload TEXT,
    file_path TEXT,
    byte_count INTEGER NOT NULL CHECK(byte_count >= 0),
    accessed_at_ms INTEGER NOT NULL,
    CHECK((payload IS NOT NULL) != (file_path IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS cache_entries_accessed_idx ON cache_entries(accessed_at_ms);


PRAGMA user_version=1;
COMMIT;
