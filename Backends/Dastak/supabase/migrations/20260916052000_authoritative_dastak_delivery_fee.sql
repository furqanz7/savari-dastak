-- Authoritative Dastak restaurant delivery pricing.
create or replace function dastak_v1_api.calculate_delivery_fee_paise(p_distance_meters bigint)
returns bigint
language plpgsql
immutable
security invoker
set search_path = ''
as $$
begin
  if p_distance_meters is null or p_distance_meters < 0 then
    raise exception using errcode='22023', message='invalid delivery distance';
  end if;
  if p_distance_meters <= 1000 then return 1500; end if;
  if p_distance_meters <= 2000 then return 2000; end if;
  return 2000 + 500 * pg_catalog.ceil((p_distance_meters - 2000)::numeric / 1000)::bigint;
end;
$$;

create or replace function dastak_v1.apply_authoritative_delivery_fee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_id uuid;
  v_distance_meters bigint;
  v_delivery_fee bigint;
  v_platform_fee bigint;
begin
  if new.snapshot_kind not in ('SUBMITTED','FULLY_SECURED','PAID') then return new; end if;
  select restaurant_branch_id into v_branch_id from dastak_v1.orders where id=new.order_id;
  if v_branch_id is null then return new; end if;
  v_distance_meters := dastak_v1_api.pickup_route_distance_meters(new.order_id, array[v_branch_id]);
  if v_distance_meters is null then
    raise exception using errcode='55000', message='delivery distance unavailable';
  end if;
  v_delivery_fee := dastak_v1_api.calculate_delivery_fee_paise(v_distance_meters);
  v_platform_fee := dastak_v1_api.calculate_platform_fee(new.subtotal_paise + v_delivery_fee);
  new.delivery_fee_paise := v_delivery_fee;
  new.platform_fee_paise := v_platform_fee;
  new.total_paise := new.subtotal_paise + v_delivery_fee + v_platform_fee + new.tax_paise - new.discount_paise;
  new.calculation_details := coalesce(new.calculation_details,'{}'::jsonb) || jsonb_build_object(
    'deliveryDistanceMeters',v_distance_meters,
    'deliveryFeeAuthority','DASTAK_STARTED_KILOMETRE_BANDS',
    'platformFeeAuthority','DASTAK_LOCKED_200_BPS'
  );
  return new;
end;
$$;

drop trigger if exists order_price_snapshots_apply_authoritative_delivery_fee on dastak_v1.order_price_snapshots;
create trigger order_price_snapshots_apply_authoritative_delivery_fee
before insert on dastak_v1.order_price_snapshots
for each row execute function dastak_v1.apply_authoritative_delivery_fee();
