-- Ensure every new V1 retail order carries the complete customer bill in its
-- immutable price snapshot. Existing snapshots remain historical records.
create or replace function dastak_v1.apply_v1_order_fees()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery constant bigint := 3500; -- INR 35.00 baseline delivery charge
  v_platform bigint;
begin
  if new.snapshot_kind in ('SUBMITTED', 'FULLY_SECURED', 'PAID')
     and new.subtotal_paise > 0
     and new.delivery_fee_paise = 0
     and new.platform_fee_paise = 0 then
    v_platform := floor(((new.subtotal_paise + v_delivery)::numeric * 200 + 5000) / 10000)::bigint;
    new.delivery_fee_paise := v_delivery;
    new.platform_fee_paise := v_platform;
    new.total_paise := new.subtotal_paise + new.delivery_fee_paise + new.platform_fee_paise
      - new.discount_paise + new.tax_paise;
    new.calculation_details := coalesce(new.calculation_details, '{}'::jsonb) || jsonb_build_object(
      'deliveryFeeAuthority', 'DASTAK_V1_BASELINE',
      'deliveryFeePaise', v_delivery,
      'platformFeeAuthority', 'DASTAK_V1_LOCKED_200_BPS',
      'platformFeePaise', v_platform
    );
  end if;
  return new;
end;
$$;

drop trigger if exists order_price_snapshots_apply_v1_fees on dastak_v1.order_price_snapshots;
create trigger order_price_snapshots_apply_v1_fees
before insert on dastak_v1.order_price_snapshots
for each row execute function dastak_v1.apply_v1_order_fees();
