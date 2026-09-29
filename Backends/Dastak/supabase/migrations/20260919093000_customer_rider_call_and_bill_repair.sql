-- Expose controlled contact details for an assigned order and reassert the
-- authoritative V1 fee trigger. Customer may call after assignment; rider
-- contact remains a UI/backend arrival gate (within 50 metres).

create or replace function dastak_v1_api.delivery_tracking_json(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  m dastak_v1.delivery_missions%rowtype;
  a private.delivery_partner_availability%rowtype;
  rider_name text;
  rider_phone text;
begin
  select * into m from dastak_v1.delivery_missions
  where order_id = p_order_id and assigned_rider_id is not null
    and status in ('ASSIGNED','EN_ROUTE_TO_PICKUPS','PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP','OUT_FOR_DELIVERY','ARRIVED','DELIVERY_RECOVERY')
  order by created_at desc limit 1;
  if not found then return null; end if;
  select display_name, phone_number into rider_name, rider_phone
  from public.accounts where id = m.assigned_rider_id;
  select * into a from private.delivery_partner_availability
  where account_id = m.assigned_rider_id and tracking_mission_id = m.id
    and tracking_recorded_at >= m.assigned_at;
  return pg_catalog.jsonb_build_object(
    'missionId',m.id,'phase',m.status,
    'riderName',coalesce(nullif(rider_name,''),'Delivery partner'),
    'riderPhoneNumber',case when rider_phone ~ '^\\+[1-9][0-9]{7,14}$' then rider_phone else null end,
    'transportType',m.assigned_transport_type,
    'location',case when a.tracking_location is null then null else pg_catalog.jsonb_build_object(
      'latitude',extensions.st_y(a.tracking_location),'longitude',extensions.st_x(a.tracking_location)) end,
    'recordedAt',a.tracking_recorded_at,'receivedAt',a.tracking_received_at,
    'accuracyMeters',a.tracking_accuracy_meters,'sequence',a.tracking_sequence,
    'liveUntil',least(a.tracking_recorded_at,a.tracking_received_at) + interval '30 seconds',
    'serverTime',pg_catalog.now());
end;
$$;

create or replace function dastak_v1.apply_authoritative_delivery_fee()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_branch_id uuid;
  v_distance_meters bigint;
  v_delivery_fee bigint;
  v_platform_fee bigint;
begin
  if new.snapshot_kind not in ('SUBMITTED','FULLY_SECURED','PAID') then return new; end if;
  select restaurant_branch_id into v_branch_id from dastak_v1.orders where id = new.order_id;
  if v_branch_id is null then return new; end if;
  v_distance_meters := dastak_v1_api.pickup_route_distance_meters(new.order_id, array[v_branch_id]);
  if v_distance_meters is null then raise exception using errcode='55000', message='delivery distance unavailable'; end if;
  v_delivery_fee := dastak_v1_api.calculate_delivery_fee_paise(v_distance_meters);
  v_platform_fee := dastak_v1_api.calculate_platform_fee(new.subtotal_paise + v_delivery_fee);
  new.delivery_fee_paise := v_delivery_fee;
  new.platform_fee_paise := v_platform_fee;
  new.total_paise := new.subtotal_paise + v_delivery_fee + v_platform_fee + new.tax_paise - new.discount_paise;
  new.calculation_details := coalesce(new.calculation_details,'{}'::jsonb) || pg_catalog.jsonb_build_object(
    'deliveryDistanceMeters',v_distance_meters,
    'deliveryFeeAuthority','DASTAK_STARTED_KILOMETRE_BANDS',
    'platformFeeAuthority','DASTAK_LOCKED_200_BPS');
  return new;
end;
$$;

drop trigger if exists order_price_snapshots_apply_authoritative_delivery_fee on dastak_v1.order_price_snapshots;
create trigger order_price_snapshots_apply_authoritative_delivery_fee
before insert on dastak_v1.order_price_snapshots
for each row execute function dastak_v1.apply_authoritative_delivery_fee();
