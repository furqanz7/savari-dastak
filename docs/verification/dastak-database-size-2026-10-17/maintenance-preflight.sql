-- Read-only capability metadata for planning. No maintenance is performed.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '10s';
SELECT jsonb_build_object(
  'observed_at', now(),
  'server_version', current_setting('server_version'),
  'database_bytes', pg_database_size(current_database()),
  'default_transaction_read_only', current_setting('default_transaction_read_only'),
  'query_role', current_user,
  'query_role_flags', (SELECT jsonb_build_object('superuser', rolsuper,
    'bypass_rls', rolbypassrls) FROM pg_roles WHERE rolname = current_user),
  'has_maintain_privilege', has_table_privilege(current_user,
    'cron.job_run_details', 'MAINTAIN'),
  'pg_maintain_membership', pg_has_role(current_user, 'pg_maintain', 'USAGE'),
  'cron_extension_version', (SELECT extversion FROM pg_extension WHERE extname = 'pg_cron'),
  'cron_settings', (SELECT jsonb_object_agg(name, setting)
    FROM pg_settings WHERE name IN ('cron.log_run', 'cron.timezone')),
  'history_table', (SELECT jsonb_build_object(
      'owner_role', pg_get_userbyid(c.relowner),
      'owner_role_membership', pg_has_role(current_user, c.relowner, 'USAGE'),
      'row_security_enabled', c.relrowsecurity,
      'can_select', has_table_privilege(current_user, c.oid, 'SELECT'),
      'can_delete', has_table_privilege(current_user, c.oid, 'DELETE'),
      'can_insert', has_table_privilege(current_user, c.oid, 'INSERT'),
      'total_bytes', pg_total_relation_size(c.oid),
      'relation_pages', c.relpages,
      'estimated_rows', c.reltuples)
    FROM pg_class AS c WHERE c.oid = 'cron.job_run_details'::regclass),
  'referencing_foreign_keys', (SELECT coalesce(jsonb_agg(jsonb_build_object(
    'table', conrelid::regclass::text, 'constraint', conname)), '[]'::jsonb)
    FROM pg_constraint WHERE contype = 'f' AND confrelid = 'cron.job_run_details'::regclass),
  'history_triggers', (SELECT coalesce(jsonb_agg(jsonb_build_object(
    'name', tgname, 'enabled', tgenabled)), '[]'::jsonb)
    FROM pg_trigger WHERE tgrelid = 'cron.job_run_details'::regclass),
  'policies', (SELECT coalesce(jsonb_agg(jsonb_build_object(
    'name', policyname, 'command', cmd, 'roles', roles, 'qual', qual,
    'with_check', with_check)), '[]'::jsonb)
    FROM pg_policies WHERE schemaname = 'cron' AND tablename = 'job_run_details')
) AS maintenance_preflight;
ROLLBACK;
