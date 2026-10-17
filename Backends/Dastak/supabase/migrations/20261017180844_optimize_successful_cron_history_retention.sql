-- Preserve the applied activation migration. Refine only our new maintenance job.
-- Scalar, uncorrelated cutoff subqueries become initplans: compute the stable
-- three-day timestamp once per phase, instead of doing timezone/interval work
-- for every history row. Scope, cap, schedule, ownership and time budgets stay identical.
DO $migration$
DECLARE
  retention_id bigint;
  previous_command text;
BEGIN
  SELECT jobid, command INTO retention_id, previous_command
  FROM cron.job WHERE jobname='dastak-successful-cron-history-retention';
  IF retention_id IS NULL OR encode(sha256(convert_to(previous_command,'UTF8')),'hex')
    <> '4e79677e51692bb8c96a91d36e61a0842a2082925ad87d24d6076a517456946c' THEN
    RAISE EXCEPTION 'Unexpected history retention definition; inspect before changing it';
  END IF;
  PERFORM cron.alter_job(retention_id, command := $retention$
      SET LOCAL lock_timeout = '1s';
      SET LOCAL statement_timeout = '5s';
      WITH expired AS MATERIALIZED (
        SELECT runid FROM cron.job_run_details
        WHERE status = 'succeeded' AND end_time IS NOT NULL
          AND end_time < (SELECT now() - interval '3 days')
        ORDER BY runid
        LIMIT 3000
      ), removed AS (
        DELETE FROM cron.job_run_details AS h
        USING expired AS e
        WHERE h.runid = e.runid AND h.status = 'succeeded'
          AND h.end_time IS NOT NULL AND h.end_time < (SELECT now() - interval '3 days')
        RETURNING h.runid
      )
      SELECT count(*) AS expired_successes_removed FROM removed;
    $retention$);
END;
$migration$;
