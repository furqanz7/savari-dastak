begin;
update dastak_v1.notification_routes
set enabled=false,title='Operations override',version=version+1
where audience='RIDER' and notification_type='rider.mission_offer';
\ir ../supabase/migrations/20260907230629_restore_customer_delivery_notification_routes.sql
do $$ begin
  if not exists(select 1 from dastak_v1.notification_routes
    where audience='RIDER' and notification_type='rider.mission_offer'
    and title='Operations override' and not enabled) then
    raise exception 'Repair overwrote a route override';
  end if;
end $$;

-- Transactional fixture: no HTTP, no vaulted secret access, no live events.
select cron.schedule('dastak-v1-outbox-worker','* * * * *',
 $$select '/functions/v1/process-v1-outbox'$$);
\ir ../supabase/migrations/20260907232655_accelerate_delivery_order_notifications.sql
\ir ../supabase/migrations/20260907232655_accelerate_delivery_order_notifications.sql
do $$ begin
  if not exists(select 1 from cron.job where jobname='dastak-v1-notification-fast-lane'
    and schedule='10 seconds' and active
    and command like '%/functions/v1/process-v1-outbox?notificationsOnly=true%') then
    raise exception 'Fast notification schedule is incorrect';
  end if;
  if not exists(select 1 from cron.job where jobname='dastak-v1-outbox-worker'
    and schedule='* * * * *') then
    raise exception 'Maintenance cadence changed';
  end if;
  if (select count(*) from cron.job where jobname='dastak-v1-notification-fast-lane') <> 1 then
    raise exception 'Duplicate fast workers';
  end if;
end $$;
rollback;
select 'PASS: route overrides preserved; fast schedule correct and idempotent; maintenance unchanged; all fixtures rolled back';
