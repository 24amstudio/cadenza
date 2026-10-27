-- Additive migration from version 1. Native callers back up before migration.
BEGIN IMMEDIATE;
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
PRAGMA user_version=2;
COMMIT;
