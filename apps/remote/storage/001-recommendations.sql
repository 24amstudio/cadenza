CREATE TABLE IF NOT EXISTS recommendation_events (
  event_id TEXT PRIMARY KEY NOT NULL,
  recommendation_id TEXT,
  source TEXT NOT NULL CHECK(source IN ('catalog','library')),
  song_id TEXT NOT NULL,
  outcome TEXT NOT NULL CHECK(outcome IN ('qualified_play','early_skip','late_skip','replay','favorite','manual_replacement','queue_removal','interruption')),
  position_ms INTEGER,
  duration_ms INTEGER,
  replacement_json TEXT,
  occurred_at_ms INTEGER NOT NULL CHECK(occurred_at_ms >= 0)
);
CREATE INDEX IF NOT EXISTS recommendation_events_time ON recommendation_events(occurred_at_ms);
CREATE TABLE IF NOT EXISTS recommendation_passports (
  sequence INTEGER PRIMARY KEY NOT NULL CHECK(sequence > 0),
  payload_base64 TEXT NOT NULL CHECK(length(payload_base64) <= 131072),
  public_key_base64 TEXT NOT NULL CHECK(length(public_key_base64) <= 1024),
  signature_base64 TEXT NOT NULL CHECK(length(signature_base64) <= 1024),
  created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0)
);
CREATE TABLE IF NOT EXISTS recommendation_outcomes (
  recommendation_id TEXT PRIMARY KEY NOT NULL,
  outcome TEXT,
  plan_id TEXT,
  candidate_json TEXT,
  expires_at_ms INTEGER,
  acknowledged INTEGER NOT NULL DEFAULT 0 CHECK(acknowledged IN (0,1))
);
