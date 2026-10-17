-- Aggregate-only retention sizing. No deletion, maintenance, or configuration changes.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
SELECT jsonb_build_object(
  'observed_at', now(),
  'database_bytes', pg_database_size(current_database()),
  'cron_history_bytes', pg_total_relation_size('cron.job_run_details'),
  'total_rows', count(*),
  'succeeded_rows', count(*) FILTER (WHERE status = 'succeeded'),
  'failed_rows', count(*) FILTER (WHERE status = 'failed'),
  'unfinished_rows', count(*) FILTER (WHERE end_time IS NULL),
  'succeeded_ended_over_1_day', count(*) FILTER (
    WHERE status = 'succeeded' AND end_time < now() - interval '1 day'),
  'succeeded_ended_over_3_days', count(*) FILTER (
    WHERE status = 'succeeded' AND end_time < now() - interval '3 days'),
  'succeeded_ended_over_7_days', count(*) FILTER (
    WHERE status = 'succeeded' AND end_time < now() - interval '7 days'),
  'succeeded_ended_over_14_days', count(*) FILTER (
    WHERE status = 'succeeded' AND end_time < now() - interval '14 days'),
  'failed_ended_over_30_days', count(*) FILTER (
    WHERE status = 'failed' AND end_time < now() - interval '30 days'),
  'oldest_completed', min(end_time),
  'newest_completed', max(end_time)
) AS retention_estimate
FROM cron.job_run_details;
ROLLBACK;
