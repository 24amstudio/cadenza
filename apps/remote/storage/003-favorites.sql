CREATE TABLE favorites (
  source TEXT NOT NULL CHECK(source IN ('catalog','library')),
  song_id TEXT NOT NULL,
  song_json TEXT NOT NULL CHECK(length(song_json) <= 16384),
  saved_at_ms INTEGER NOT NULL CHECK(saved_at_ms >= 0),
  PRIMARY KEY(source, song_id)
);
PRAGMA user_version=3;
