-- Post-maintenance aggregate/metadata checks only. Never select command/response payloads.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SELECT jsonb_build_object(
  'observed_at',now(),'database_bytes',pg_database_size(current_database()),
  'history_bytes',pg_total_relation_size('cron.job_run_details'),
  'read_only',current_setting('default_transaction_read_only'),
  'history_status',(SELECT jsonb_object_agg(status,n) FROM
    (SELECT status,count(*) n FROM cron.job_run_details GROUP BY status) grouped),
  'schedule_count',(SELECT count(*) FROM cron.job),
  'business_schedule_hash',(SELECT md5(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text) FROM cron.job j
    WHERE jobname<>'dastak-successful-cron-history-retention'),
  'retention_job',(SELECT jsonb_build_object('job_id',jobid,'name',jobname,'schedule',schedule,
    'active',active,'role',username,'command_sha256',encode(sha256(convert_to(command,'UTF8')),'hex'))
    FROM cron.job WHERE jobname='dastak-successful-cron-history-retention'),
  'business_job_health',(SELECT jsonb_agg(jsonb_build_object('job_id',j.jobid,'name',j.jobname,
    'recent_runs',h.runs,'recent_failures',h.failures,'last_success',h.last_success) ORDER BY j.jobid)
    FROM cron.job j LEFT JOIN LATERAL (SELECT count(*) runs,count(*) FILTER(WHERE status='failed') failures,
      max(end_time) FILTER(WHERE status='succeeded') last_success FROM cron.job_run_details h
      WHERE h.jobid=j.jobid AND h.start_time>now()-interval '5 minutes') h ON true
    WHERE j.jobname<>'dastak-successful-cron-history-retention'),
  'immutable_audit_triggers',(SELECT jsonb_agg(jsonb_build_object('table',c.relname,'trigger',t.tgname,
    'enabled',t.tgenabled,'definition_fingerprint',md5(pg_get_triggerdef(t.oid))))
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='dastak_v1' AND c.relname IN ('invariant_incident_history','invariant_monitor_runs') AND NOT t.tgisinternal),
  'history_rls',(SELECT relrowsecurity FROM pg_class WHERE oid='cron.job_run_details'::regclass),
  'retention_migration_recorded',EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261017173813'),
  'retention_correction_recorded',EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261017180844'),
  'wal_bytes',(SELECT sum(size) FROM pg_ls_waldir())
) AS cleanup_acceptance;
ROLLBACK;
