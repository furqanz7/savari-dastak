create table if not exists private.dastak_order_notification_queue (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references private.merchant_orders(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  status text not null,
  payment_state text not null,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0)
);

alter table private.dastak_order_notification_queue enable row level security;
revoke all on private.dastak_order_notification_queue from anon, authenticated;
create index if not exists dastak_notification_queue_pending_idx
  on private.dastak_order_notification_queue (processed_at, created_at)
  where processed_at is null;

create or replace function public.queue_dastak_order_notification()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
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

drop trigger if exists merchant_orders_queue_dastak_notification
  on private.merchant_orders;
create trigger merchant_orders_queue_dastak_notification
after insert or update of status, payment_state on private.merchant_orders
for each row execute function public.queue_dastak_order_notification();

revoke all on function public.queue_dastak_order_notification() from public, anon, authenticated;
