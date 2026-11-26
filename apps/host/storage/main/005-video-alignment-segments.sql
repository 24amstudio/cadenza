PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

ALTER TABLE video_lyric_alignments ADD COLUMN studio_song_id TEXT;
ALTER TABLE video_lyric_alignments ADD COLUMN segments_json TEXT;

PRAGMA user_version=6;
COMMIT;
