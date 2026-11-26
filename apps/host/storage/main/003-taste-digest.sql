PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

CREATE TABLE remote_taste_digests (
  remote_id TEXT PRIMARY KEY REFERENCES paired_remotes(remote_id) ON DELETE CASCADE,
  digest_json TEXT NOT NULL CHECK(json_valid(digest_json) AND length(digest_json) <= 65536),
  updated_at_ms INTEGER NOT NULL CHECK(typeof(updated_at_ms) = 'integer' AND updated_at_ms >= 0)
);

PRAGMA user_version=4;
COMMIT;
