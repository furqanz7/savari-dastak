-- Bounded, read-only aggregates. Never return job commands, responses,
-- incident snapshots, customer identifiers or order contents.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
WITH cron_history AS (
  SELECT jobid, status, count(*) AS runs, min(start_time) AS first_run,
    max(start_time) AS last_run,
    count(*) FILTER (WHERE end_time < now() - interval '7 days') AS ended_over_7_days,
    count(*) FILTER (WHERE end_time < now() - interval '30 days') AS ended_over_30_days,
    count(*) FILTER (WHERE start_time >= now() - interval '1 day') AS runs_last_day
  FROM cron.job_run_details GROUP BY jobid, status
), incident_history AS (
  SELECT action, count(*) AS events, min(occurred_at) AS first_event,
    max(occurred_at) AS last_event,
    count(*) FILTER (WHERE occurred_at >= now() - interval '1 day') AS events_last_day
  FROM dastak_v1.invariant_incident_history GROUP BY action
), current_incidents AS (
  SELECT invariant_key, status, count(*) AS incidents,
    max(occurrence_count) AS highest_repeat_count,
    min(first_detected_at) AS first_detected, max(last_detected_at) AS last_detected
  FROM dastak_v1.invariant_incidents GROUP BY invariant_key, status
)
SELECT jsonb_build_object(
  'cron_history', (SELECT jsonb_agg(to_jsonb(c) ORDER BY runs DESC) FROM cron_history AS c),
  'incident_history', (SELECT jsonb_agg(to_jsonb(h) ORDER BY events DESC) FROM incident_history AS h),
  'current_incidents', (SELECT jsonb_agg(to_jsonb(i) ORDER BY invariant_key, status) FROM current_incidents AS i),
  'immutability_triggers', (SELECT jsonb_agg(jsonb_build_object('table', c.relname, 'trigger', t.tgname, 'enabled', t.tgenabled))
    FROM pg_trigger AS t JOIN pg_class AS c ON c.oid=t.tgrelid
    JOIN pg_namespace AS n ON n.oid=c.relnamespace
    WHERE n.nspname='dastak_v1' AND c.relname IN ('invariant_incident_history','invariant_monitor_runs')
      AND NOT t.tgisinternal)
) AS history_audit;
ROLLBACK;
