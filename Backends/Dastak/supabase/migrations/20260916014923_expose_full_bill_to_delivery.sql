-- Delivery partners need the same immutable customer bill used for collection
-- and doorstep verification. Keep this projection read-only and sourced from
-- the paid order price snapshot; merchant projections remain product-only.
alter function dastak_v1_api.rider_mission_json(uuid, uuid)
  rename to rider_mission_json_pre_full_bill;

create function dastak_v1_api.rider_mission_json(
  p_rider_id uuid,
  p_mission_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_price dastak_v1.order_price_snapshots%rowtype;
begin
  v_result := dastak_v1_api.rider_mission_json_pre_full_bill(p_rider_id, p_mission_id);
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
    and mission.assigned_rider_id = p_rider_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'delivery mission not found';
  end if;

  select snapshot.* into v_price
  from dastak_v1.order_price_snapshots snapshot
  where snapshot.order_id = v_mission.order_id
    and snapshot.snapshot_kind = 'PAID'
  order by snapshot.created_at desc, snapshot.id desc
  limit 1;

  return v_result || pg_catalog.jsonb_build_object(
    'price', case when v_price.id is null then null else pg_catalog.jsonb_build_object(
      'snapshotKind', v_price.snapshot_kind,
      'subtotalPaise', v_price.subtotal_paise,
      'deliveryFeePaise', v_price.delivery_fee_paise,
      'platformFeePaise', v_price.platform_fee_paise,
      'discountPaise', v_price.discount_paise,
      'taxPaise', v_price.tax_paise,
      'totalPaise', v_price.total_paise,
      'currencyCode', v_price.currency_code
    ) end
  );
end;
$$;

revoke all on function dastak_v1_api.rider_mission_json_pre_full_bill(uuid, uuid) from public, anon, authenticated;
grant execute on function dastak_v1_api.rider_mission_json_pre_full_bill(uuid, uuid) to service_role;
revoke all on function dastak_v1_api.rider_mission_json(uuid, uuid) from public, anon, authenticated;
grant execute on function dastak_v1_api.rider_mission_json(uuid, uuid) to service_role;
