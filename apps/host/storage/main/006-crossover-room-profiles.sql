PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

-- The acoustic delay measured for one room. The key is the Host's output device and the Remote's browser. The offset
-- is in microseconds, and a value outside ±50 ms is refused, so a bad measurement cannot move the sub far.
CREATE TABLE crossover_room_profiles (
  profile_key TEXT PRIMARY KEY CHECK(length(profile_key) BETWEEN 1 AND 400),
  acoustic_offset_us INTEGER NOT NULL CHECK(typeof(acoustic_offset_us) = 'integer' AND acoustic_offset_us BETWEEN -50000 AND 50000),
  measured_at_ms INTEGER NOT NULL CHECK(typeof(measured_at_ms) = 'integer' AND measured_at_ms >= 0)
);

PRAGMA user_version=7;
COMMIT;
