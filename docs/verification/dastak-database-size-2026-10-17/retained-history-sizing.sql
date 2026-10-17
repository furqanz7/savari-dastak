-- Aggregate-only refinement of retained data, not a maintenance command.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
WITH retained AS (
  SELECT count(*) AS rows,
    coalesce(sum(pg_column_size(h)::bigint),0) AS tuple_bytes,
    coalesce(max(pg_column_size(h)),0) AS largest_tuple_bytes
  FROM cron.job_run_details AS h
  WHERE status IS DISTINCT FROM 'succeeded' OR end_time IS NULL
    OR end_time >= transaction_timestamp() - interval '3 days'
)
SELECT jsonb_build_object('observed_at',now(),'retained',to_jsonb(retained),
  'history_total_bytes',pg_total_relation_size(c.oid),
  'history_index_bytes',pg_indexes_size(c.oid),
  'history_toast_total_bytes',CASE WHEN c.reltoastrelid=0 THEN 0
    ELSE pg_total_relation_size(c.reltoastrelid) END,
  'relation_options',c.reloptions,
  'wal_setting_max',current_setting('max_wal_size'),
  'wal_setting_min',current_setting('min_wal_size'),
  'wal_compression',current_setting('wal_compression')) AS retained_sizing
FROM retained CROSS JOIN pg_class AS c
WHERE c.oid='cron.job_run_details'::regclass;
ROLLBACK;
