-- Deliver short-lived order and rider offers promptly without increasing the
-- frequency of account deletion processing or invariant monitors. The worker
-- must support notificationsOnly before this migration is deployed.
do $$
declare
  v_command text;
begin
  select job.command into v_command
  from cron.job job
  where job.jobname = 'dastak-v1-outbox-worker' and job.active;

  -- Local environments without the vaulted runtime keep notifications off.
  if v_command is null then return; end if;
  if pg_catalog.strpos(v_command, '/functions/v1/process-v1-outbox') = 0 then
    raise exception 'Existing notification worker endpoint could not be resolved';
  end if;
  perform cron.schedule(
    'dastak-v1-notification-fast-lane',
    '10 seconds',
    pg_catalog.replace(v_command,
      '/functions/v1/process-v1-outbox',
      '/functions/v1/process-v1-outbox?notificationsOnly=true')
  );
end;
$$;
