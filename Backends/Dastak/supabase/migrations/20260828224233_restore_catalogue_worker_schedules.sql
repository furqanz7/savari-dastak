do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname='dastak-catalogue-asset-worker';
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
  perform cron.schedule(
    'dastak-catalogue-asset-worker',
    '* * * * *',
    $job$
      select net.http_post(
        url := (
          select pg_catalog.rtrim(secret.decrypted_secret, '/')
          from vault.decrypted_secrets secret
          where secret.name = 'dastak_project_url'
        ) || '/functions/v1/process-catalogue-assets',
        headers := pg_catalog.jsonb_build_object(
          'Content-Type','application/json',
          'x-dastak-internal-secret',(
            select secret.decrypted_secret
            from vault.decrypted_secrets secret
            where secret.name='dastak_notification_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 55000
      );
    $job$
  );

  select jobid into v_jobid from cron.job where jobname='dastak-catalogue-source-worker';
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
  perform cron.schedule(
    'dastak-catalogue-source-worker',
    '* * * * *',
    $job$
      select net.http_post(
        url := (
          select pg_catalog.rtrim(secret.decrypted_secret, '/')
          from vault.decrypted_secrets secret
          where secret.name='dastak_project_url'
        ) || '/functions/v1/process-catalogue-sources',
        headers := pg_catalog.jsonb_build_object(
          'Content-Type','application/json',
          'x-dastak-internal-secret',(
            select secret.decrypted_secret
            from vault.decrypted_secrets secret
            where secret.name='dastak_notification_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 55000
      );
    $job$
  );
end $$;;
