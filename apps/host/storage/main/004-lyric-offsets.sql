PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

-- The karaoke timing a person set with the nudge, per track. It is kept across launches and updates.
CREATE TABLE video_lyric_alignments (
  track_key TEXT PRIMARY KEY CHECK(length(track_key) BETWEEN 1 AND 200),
  user_offset_ms INTEGER NOT NULL CHECK(typeof(user_offset_ms) = 'integer' AND user_offset_ms BETWEEN -5000 AND 5000),
  updated_at_ms INTEGER NOT NULL CHECK(typeof(updated_at_ms) = 'integer' AND updated_at_ms >= 0)
);

PRAGMA user_version=5;
COMMIT;
