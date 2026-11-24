PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

CREATE TABLE remote_taste_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_id TEXT NOT NULL REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  signal TEXT NOT NULL CHECK(signal IN ('play_now','play_next','enqueue','promotion','autoplay_play','completion','early_skip')),
  artist_key TEXT NOT NULL CHECK(length(artist_key) BETWEEN 1 AND 256),
  track_key TEXT NOT NULL CHECK(length(track_key) BETWEEN 1 AND 256),
  weight_tenths INTEGER NOT NULL CHECK(typeof(weight_tenths) = 'integer' AND weight_tenths BETWEEN -100 AND 100),
  bucket TEXT NOT NULL CHECK(bucket IN ('morning','afternoon','evening','late_night')),
  occurred_at_ms INTEGER NOT NULL CHECK(typeof(occurred_at_ms) = 'integer' AND occurred_at_ms >= 0)
);

CREATE INDEX remote_taste_events_by_remote ON remote_taste_events(remote_id, occurred_at_ms);

PRAGMA user_version=3;
COMMIT;
