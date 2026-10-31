PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

CREATE TABLE recommendation_profiles (
  remote_id TEXT PRIMARY KEY NOT NULL REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  passport_sequence INTEGER NOT NULL CHECK(passport_sequence > 0 AND passport_sequence <= 9007199254740991),
  expires_at_ms INTEGER NOT NULL CHECK(expires_at_ms >= 0),
  model_version INTEGER NOT NULL CHECK(model_version > 0),
  profile_json TEXT NOT NULL CHECK(length(profile_json) <= 65536),
  updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= 0)
);
ALTER TABLE host_state ADD COLUMN cree_enabled INTEGER NOT NULL DEFAULT 1 CHECK(cree_enabled IN (0,1));
ALTER TABLE host_state ADD COLUMN recommendation_mode TEXT NOT NULL DEFAULT 'auto'
  CHECK(recommendation_mode IN ('auto','shadow','planning','paused'));
ALTER TABLE host_state ADD COLUMN recommendation_phase TEXT NOT NULL DEFAULT 'learning'
  CHECK(recommendation_phase IN ('learning','ready','planning','fallback'));
ALTER TABLE host_state ADD COLUMN recommendation_phase_reason TEXT NOT NULL DEFAULT 'Waiting for a valid profile.'
  CHECK(length(recommendation_phase_reason) <= 240);

CREATE TABLE recommendation_keys (
  remote_id TEXT PRIMARY KEY NOT NULL REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  public_key_base64 TEXT NOT NULL CHECK(length(public_key_base64) <= 1024),
  created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0)
);

CREATE TABLE recommendation_transitions (
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  source_key TEXT NOT NULL CHECK(length(source_key) BETWEEN 1 AND 300),
  target_key TEXT NOT NULL CHECK(length(target_key) BETWEEN 1 AND 300),
  context_key TEXT NOT NULL DEFAULT '',
  weight REAL NOT NULL CHECK(weight >= 0 AND weight <= 1),
  confidence REAL NOT NULL CHECK(confidence >= 0 AND confidence <= 1),
  source TEXT NOT NULL CHECK(source IN ('remote','host','music','derived')),
  freshness_ms INTEGER NOT NULL CHECK(freshness_ms >= 0),
  PRIMARY KEY(remote_id, source_key, target_key, context_key)
);
CREATE INDEX recommendation_transitions_source ON recommendation_transitions(remote_id, source_key, weight DESC);

CREATE TABLE recommendation_plans (
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  plan_id TEXT NOT NULL,
  recommendation_id TEXT NOT NULL,
  passport_sequence INTEGER NOT NULL,
  model_version INTEGER NOT NULL,
  expected_revision INTEGER NOT NULL,
  operation_json TEXT NOT NULL CHECK(length(operation_json) <= 16384),
  phase TEXT NOT NULL CHECK(phase IN ('prepared','dispatched','confirmed','rejected','unconfirmed','expired')),
  receipt_json TEXT,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY(remote_id, plan_id),
  UNIQUE(remote_id, recommendation_id)
);
CREATE INDEX recommendation_plans_pending ON recommendation_plans(remote_id, phase, created_at_ms);

CREATE TABLE recommendation_feedback (
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  recommendation_id TEXT NOT NULL,
  outcome TEXT NOT NULL CHECK(outcome IN ('qualified_play','early_skip','late_skip','replay','favorite','manual_replacement','queue_removal','interruption')),
  position_ms INTEGER,
  duration_ms INTEGER,
  replacement_json TEXT,
  occurred_at_ms INTEGER NOT NULL,
  PRIMARY KEY(remote_id, recommendation_id, outcome, occurred_at_ms)
);
CREATE INDEX recommendation_feedback_time ON recommendation_feedback(remote_id, occurred_at_ms);

CREATE TABLE recommendation_shadow_observations (
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  observation_id TEXT NOT NULL,
  apple_key TEXT,
  cree_key TEXT,
  selected_key TEXT,
  provenance_confidence REAL NOT NULL CHECK(provenance_confidence >= 0 AND provenance_confidence <= 1),
  outcome TEXT,
  observed_at_ms INTEGER NOT NULL,
  PRIMARY KEY(remote_id, observation_id)
);

PRAGMA user_version=2;
COMMIT;
