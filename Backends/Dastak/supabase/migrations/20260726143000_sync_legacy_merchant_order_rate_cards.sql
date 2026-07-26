alter table private.merchant_order_rate_cards
  alter column delivery_fee_per_started_km_paise set default 0,
  alter column courier_payout_per_started_km_paise set default 0;

create function private.synchronize_legacy_merchant_order_rate_card_terms()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.delivery_fee_paise is distinct from new.base_delivery_fee_paise
      or new.courier_payout_paise
        is distinct from new.base_courier_payout_paise
    then
      new.base_delivery_fee_paise := new.delivery_fee_paise;
      new.delivery_fee_per_started_km_paise := 0;
      new.base_courier_payout_paise := new.courier_payout_paise;
      new.courier_payout_per_started_km_paise := 0;
    end if;
  else
    if new.delivery_fee_paise is distinct from old.delivery_fee_paise
      and new.base_delivery_fee_paise
        is not distinct from old.base_delivery_fee_paise
    then
      new.base_delivery_fee_paise := new.delivery_fee_paise;
      new.delivery_fee_per_started_km_paise := 0;
    end if;

    if new.courier_payout_paise is distinct from old.courier_payout_paise
      and new.base_courier_payout_paise
        is not distinct from old.base_courier_payout_paise
    then
      new.base_courier_payout_paise := new.courier_payout_paise;
      new.courier_payout_per_started_km_paise := 0;
    end if;
  end if;

  return new;
end;
$$;

create trigger merchant_order_rate_cards_sync_legacy_terms
before insert or update on private.merchant_order_rate_cards
for each row
execute function private.synchronize_legacy_merchant_order_rate_card_terms();

revoke execute on function
  private.synchronize_legacy_merchant_order_rate_card_terms()
from public, anon, authenticated;

grant execute on function
  private.synchronize_legacy_merchant_order_rate_card_terms()
to service_role;
