BEGIN IMMEDIATE;
DELETE FROM command_receipts
  WHERE created_at_ms < strftime('%s','now')*1000-604800000 AND outcome!='unconfirmed';
DELETE FROM playback_credit_outbox WHERE acknowledged=1;
DELETE FROM command_intents
  WHERE phase='complete' AND created_at_ms < strftime('%s','now')*1000-604800000;
DELETE FROM playback_sessions
  WHERE occurrence_id IS NOT (SELECT current_occurrence_id FROM host_state)
    AND NOT EXISTS (
      SELECT 1 FROM playback_credit_outbox o
      WHERE o.occurrence_id=playback_sessions.occurrence_id AND o.acknowledged=0
    );
DELETE FROM queue_entries
  WHERE state IN ('completed','canceled')
    AND created_at_ms < strftime('%s','now')*1000-604800000
    AND NOT EXISTS (SELECT 1 FROM playback_sessions s WHERE s.entry_id=queue_entries.entry_id);
COMMIT;
PRAGMA optimize;
PRAGMA wal_checkpoint(PASSIVE);
PRAGMA incremental_vacuum(32);
