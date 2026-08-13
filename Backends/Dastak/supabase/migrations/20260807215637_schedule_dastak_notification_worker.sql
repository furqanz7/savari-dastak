create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'dastak-order-notification-worker';
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
end;
$$;

select cron.schedule(
  'dastak-order-notification-worker',
  '* * * * *',
  $$
    select net.http_post(
      url := 'https://zmtsolkfxlrxepshnjdf.supabase.co/functions/v1/process-order-notification-queue',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-dastak-internal-secret',
          (select decrypted_secret from vault.decrypted_secrets where name = 'dastak_notification_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);
