-- Bind actor_id from the authenticated connection, never from the JSON body.
-- Run in the mutation's transaction and recheck before dispatch to Music.app.
-- now_host_ms must come from Host's monotonic clock.
WITH
  actor AS (
    SELECT remote_id FROM paired_remotes
    WHERE remote_id = :actor_id AND revoked_at_ms IS NULL
  ),
  policy AS (SELECT * FROM host_state WHERE singleton = 1),
  target AS (SELECT * FROM queue_entries WHERE entry_id = :entry_id),
  anchor AS (SELECT * FROM queue_entries WHERE entry_id = :before_entry_id),
  crossed AS (
    SELECT 1 FROM queue_entries AS other, target
    WHERE other.state = 'pending'
      AND other.requested_by IS NOT :actor_id
      AND (
        (:before_entry_id IS NULL AND other.sort_key > target.sort_key)
        OR (
          (SELECT sort_key FROM anchor) > target.sort_key
          AND other.sort_key > target.sort_key
          AND other.sort_key < (SELECT sort_key FROM anchor)
        )
        OR (
          (SELECT sort_key FROM anchor) < target.sort_key
          AND other.sort_key >= (SELECT sort_key FROM anchor)
          AND other.sort_key < target.sort_key
        )
      )
  )
SELECT CASE
  WHEN NOT EXISTS (SELECT 1 FROM actor) THEN 'revoked'
  WHEN (SELECT runtime_epoch FROM policy) IS NULL THEN 'music_unavailable'
  WHEN :host_epoch IS NOT (SELECT runtime_epoch FROM policy) THEN 'expired'
  WHEN typeof(:now_host_ms) NOT IN ('integer', 'real')
    OR typeof(:expires_at_host_ms) NOT IN ('integer', 'real') THEN 'invalid_deadline'
  WHEN :now_host_ms != CAST(:now_host_ms AS INTEGER)
    OR :expires_at_host_ms != CAST(:expires_at_host_ms AS INTEGER) THEN 'invalid_deadline'
  WHEN :now_host_ms NOT BETWEEN 0 AND 9007199254740991
    OR :expires_at_host_ms NOT BETWEEN 0 AND 9007199254740991 THEN 'invalid_deadline'
  WHEN typeof(:expected_revision) NOT IN ('integer', 'real')
    OR :expected_revision != CAST(:expected_revision AS INTEGER)
    OR :expected_revision NOT BETWEEN 0 AND 9007199254740991 THEN 'invalid_command'
  WHEN :expires_at_host_ms <= :now_host_ms THEN 'expired'
  WHEN :expires_at_host_ms > :now_host_ms + 1000 THEN 'invalid_deadline'
  WHEN :expected_revision != (SELECT queue_revision FROM policy) THEN 'stale_revision'
  WHEN :kind IS NULL OR :kind NOT IN (
    'queue.enqueue', 'queue.remove', 'queue.move', 'playback.pause',
    'playback.resume', 'playback.skip', 'playback.previous',
    'playback.stop', 'playback.seek', 'playback.volume', 'queue.play_now', 'queue.play_next'
  ) THEN 'invalid_command'
  WHEN :kind IN ('queue.enqueue', 'queue.play_next', 'playback.volume') THEN 'allowed'
  WHEN :kind = 'queue.play_now' AND :entry_id IS NULL THEN 'allowed'
  WHEN :kind IN ('playback.pause', 'playback.resume') AND :entry_id IS NULL THEN 'allowed'
  WHEN NOT EXISTS (SELECT 1 FROM target) THEN 'missing_request'
  WHEN :kind IN ('queue.remove', 'queue.move')
    AND (SELECT state FROM target) != 'pending' THEN 'invalid_state'
  WHEN :kind LIKE 'playback.%'
    AND (SELECT state FROM target) != 'current' THEN 'stale_occurrence'
  WHEN :kind = 'queue.play_now' AND (SELECT state FROM target) != 'current' THEN 'stale_occurrence'
  WHEN :kind IN ('playback.pause', 'playback.resume') THEN 'allowed'
  WHEN :kind = 'queue.move' AND :before_entry_id IS NOT NULL AND (
    NOT EXISTS (SELECT 1 FROM anchor WHERE state = 'pending')
    OR :before_entry_id = :entry_id
  ) THEN 'invalid_anchor'
  WHEN (SELECT requested_by FROM target) IS NULL THEN 'forbidden'
  WHEN (SELECT allow_cross_remote_edits FROM policy) = 1 THEN 'allowed'
  WHEN (SELECT requested_by FROM target) != :actor_id THEN 'forbidden'
  WHEN :kind = 'queue.move' AND EXISTS (SELECT 1 FROM crossed) THEN 'forbidden'
  ELSE 'allowed'
END AS decision;
