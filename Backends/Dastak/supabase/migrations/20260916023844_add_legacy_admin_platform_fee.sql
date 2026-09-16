-- Persist the legacy order's platform fee so Admin can show the same whole
-- bill without exposing it through the merchant projection.
alter table private.merchant_orders
  add column if not exists platform_fee_paise bigint not null default 0
    check (platform_fee_paise >= 0);

alter table private.merchant_orders drop constraint if exists merchant_orders_check;
alter table private.merchant_orders add constraint merchant_orders_check
  check (total_paise = item_subtotal_paise + delivery_fee_paise + platform_fee_paise);

create or replace function private.set_legacy_order_platform_fee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.platform_fee_paise = 0 and new.total_paise = new.item_subtotal_paise + new.delivery_fee_paise then
    new.platform_fee_paise := round((new.item_subtotal_paise + new.delivery_fee_paise) * 200 / 10000.0)::bigint;
    new.total_paise := new.item_subtotal_paise + new.delivery_fee_paise + new.platform_fee_paise;
  end if;
  return new;
end;
$$;

drop trigger if exists merchant_orders_platform_fee on private.merchant_orders;
create trigger merchant_orders_platform_fee
before insert on private.merchant_orders
for each row execute function private.set_legacy_order_platform_fee();

comment on column private.merchant_orders.platform_fee_paise is
  'Persisted customer-facing platform fee. Legacy historical rows retain their recorded zero fee; new rows use the 2% launch rate.';
