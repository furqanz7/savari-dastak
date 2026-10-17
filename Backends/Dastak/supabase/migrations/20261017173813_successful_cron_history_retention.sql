-- Retain three days of completed successes. Never remove failures/unfinished runs.
-- One bounded hourly maintenance job; existing business schedules remain unchanged.
-- Rollback: SELECT cron.unschedule('dastak-successful-cron-history-retention');
-- Unscheduling stops future expiry; it does not restore already expired history.
DO $migration$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dastak-successful-cron-history-retention') THEN
    RAISE EXCEPTION 'History retention name already exists; inspect before changing it';
  END IF;
  PERFORM cron.schedule(
    'dastak-successful-cron-history-retention',
    '15 * * * *',
    $retention$
      SET LOCAL lock_timeout = '1s';
      SET LOCAL statement_timeout = '5s';
      WITH expired AS MATERIALIZED (
        SELECT runid FROM cron.job_run_details
        WHERE status = 'succeeded' AND end_time IS NOT NULL
          AND end_time < now() - interval '3 days'
        ORDER BY runid
        LIMIT 3000
      ), removed AS (
        DELETE FROM cron.job_run_details AS h
        USING expired AS e
        WHERE h.runid = e.runid AND h.status = 'succeeded'
          AND h.end_time IS NOT NULL AND h.end_time < now() - interval '3 days'
        RETURNING h.runid
      )
      SELECT count(*) AS expired_successes_removed FROM removed;
    $retention$
  );
END;
$migration$;
