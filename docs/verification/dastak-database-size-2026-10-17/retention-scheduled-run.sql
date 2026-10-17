-- Read the new maintenance job's execution metadata, never command/response text.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
WITH latest AS MATERIALIZED (
  SELECT h.runid,h.status,h.start_time,h.end_time
  FROM cron.job_run_details h JOIN cron.job j ON j.jobid=h.jobid
  WHERE j.jobname='dastak-successful-cron-history-retention'
  ORDER BY h.runid DESC LIMIT 1
)
SELECT jsonb_build_object('observed_at',now(),
  'latest_run',(SELECT jsonb_build_object('run_id',runid,'status',status,
    'started_at',start_time,'ended_at',end_time,
    'duration_ms',extract(epoch FROM end_time-start_time)*1000) FROM latest),
  'expired_before_run_remaining',(SELECT count(*) FROM cron.job_run_details
    WHERE status='succeeded' AND end_time<(SELECT start_time-interval '3 days' FROM latest)),
  'failed_history_rows',(SELECT count(*) FROM cron.job_run_details WHERE status='failed'),
  'database_bytes',pg_database_size(current_database()),
  'history_bytes',pg_total_relation_size('cron.job_run_details')
) AS scheduled_retention_acceptance;
ROLLBACK;
