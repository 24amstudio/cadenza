-- Host supplies the observed current position, or NULL when it is unknown.
-- Empty results mean an empty queue and a total remaining time of zero.
-- These are nominal durations; no unobserved AutoMix overlap is subtracted.
WITH active AS (
  SELECT entry_id, requested_by, state, sort_key,
    CASE
      WHEN state = 'current' AND :position_ms IS NULL THEN NULL
      WHEN duration_ms IS NULL THEN NULL
      WHEN state = 'current' THEN max(0, duration_ms - :position_ms)
      ELSE duration_ms
    END AS remaining_ms
  FROM queue_entries
  WHERE state IN ('current', 'pending')
), totals AS (
  SELECT CASE
    WHEN count(*) != count(remaining_ms) THEN NULL
    WHEN total(remaining_ms) > 9007199254740991 THEN NULL
    ELSE CAST(total(remaining_ms) AS INTEGER)
  END AS total_remaining_ms
  FROM active
)
SELECT item.entry_id, item.requested_by, item.remaining_ms,
  CASE WHEN item.state = 'current' THEN 0 ELSE (
    SELECT CASE
      WHEN count(*) != count(preceding.remaining_ms) THEN NULL
      WHEN total(preceding.remaining_ms) > 9007199254740991 THEN NULL
      ELSE CAST(total(preceding.remaining_ms) AS INTEGER)
    END
    FROM active AS preceding
    WHERE preceding.state = 'current'
      OR (preceding.state = 'pending' AND preceding.sort_key < item.sort_key)
  ) END AS estimated_wait_ms,
  totals.total_remaining_ms
FROM active AS item CROSS JOIN totals
ORDER BY CASE item.state WHEN 'current' THEN 0 ELSE 1 END, item.sort_key;
