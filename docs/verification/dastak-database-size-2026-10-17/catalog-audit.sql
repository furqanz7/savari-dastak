-- Only column/index metadata and cron schedule names; never read cron commands.
SELECT jsonb_build_object(
  'columns', (SELECT jsonb_agg(jsonb_build_object('schema', table_schema, 'table', table_name,
    'column', column_name, 'type', data_type) ORDER BY table_schema, table_name, ordinal_position)
    FROM information_schema.columns
    WHERE (table_schema = 'cron' AND table_name IN ('job_run_details', 'job'))
       OR (table_schema = 'dastak_v1' AND table_name IN ('invariant_incident_history', 'invariant_monitor_runs', 'invariant_incidents'))),
  'indexes', (SELECT jsonb_agg(jsonb_build_object('schema', schemaname, 'table', tablename, 'definition', indexdef))
    FROM pg_indexes
    WHERE (schemaname = 'cron' AND tablename = 'job_run_details')
       OR (schemaname = 'dastak_v1' AND tablename IN ('invariant_incident_history', 'invariant_monitor_runs', 'invariant_incidents'))),
  'schedules', (SELECT jsonb_agg(jsonb_build_object('job_id', jobid, 'name', jobname, 'schedule', schedule, 'active', active) ORDER BY jobid)
    FROM cron.job)
) AS catalog_audit;
