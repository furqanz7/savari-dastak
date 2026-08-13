alter table private.dastak_order_notification_queue set schema public;

create or replace function private.queue_dastak_order_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status
     or old.payment_state is distinct from new.payment_state then
    insert into public.dastak_order_notification_queue (
      order_id, account_id, status, payment_state
    ) values (new.id, new.customer_account_id, new.status, new.payment_state);
  end if;
  return new;
end;
$$;

revoke all on public.dastak_order_notification_queue from anon, authenticated;
grant select, update on public.dastak_order_notification_queue to service_role;
revoke all on function private.queue_dastak_order_notification() from public, anon, authenticated;
