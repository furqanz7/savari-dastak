create or replace function private.queue_dastak_order_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status
     or old.payment_state is distinct from new.payment_state then
    insert into private.dastak_order_notification_queue (
      order_id, account_id, status, payment_state
    ) values (
      new.id, new.customer_account_id, new.status, new.payment_state
    );
  end if;
  return new;
end;
$$;

revoke all on function private.queue_dastak_order_notification() from public, anon, authenticated;

drop trigger if exists merchant_orders_queue_dastak_notification
  on private.merchant_orders;
create trigger merchant_orders_queue_dastak_notification
after insert or update of status, payment_state on private.merchant_orders
for each row execute function private.queue_dastak_order_notification();
