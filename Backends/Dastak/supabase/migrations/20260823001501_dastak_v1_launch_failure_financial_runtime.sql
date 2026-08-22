-- Dastak V1 Step 5 runtime commands and projections.

drop index dastak_v1.delivery_missions_one_active_order_uidx;
create unique index delivery_missions_one_active_order_uidx
  on dastak_v1.delivery_missions (order_id)
  where status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED');

create or replace function dastak_v1.is_valid_order_line_transition(
  p_from dastak_v1.order_line_status,
  p_to dastak_v1.order_line_status
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_from
    when 'ORDERED' then p_to = 'RESERVED'
    when 'RESERVED' then p_to = 'FULFILLING'
    when 'FULFILLING' then p_to in ('FULFILLED', 'RECOVERY', 'REFUNDED')
    when 'RECOVERY' then p_to in ('FULFILLING', 'FULFILLED', 'REFUNDED')
    else false
  end;
$$;

create or replace function dastak_v1.guard_delivery_mission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recovery_reroute boolean := coalesce(
    pg_catalog.current_setting('dastak_v1.recovery_reroute', true), ''
  ) = 'true';
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.transport_snapshot is distinct from old.transport_snapshot
    or new.pickup_count is distinct from old.pickup_count
    or new.search_started_at is distinct from old.search_started_at
    or new.created_at is distinct from old.created_at then
    raise exception 'delivery mission identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'delivery mission version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'SEARCHING_RIDER' and new.status in ('ASSIGNED', 'CANCELLED'))
    or (old.status = 'ASSIGNED' and new.status in (
      'EN_ROUTE_TO_PICKUPS', 'REASSIGNING', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'EN_ROUTE_TO_PICKUPS' and new.status in (
      'PICKUP_IN_PROGRESS', 'REASSIGNING', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'PICKUP_IN_PROGRESS' and new.status in (
      'ALL_PACKAGES_PICKED_UP', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'PICKUP_IN_PROGRESS' and new.status = 'REASSIGNING'
      and v_recovery_reroute and old.first_package_picked_up_at is null)
    or (old.status = 'ALL_PACKAGES_PICKED_UP' and new.status in (
      'OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'OUT_FOR_DELIVERY' and new.status in ('ARRIVED', 'DELIVERY_RECOVERY'))
    or (old.status = 'ARRIVED' and new.status in ('DELIVERED', 'DELIVERY_RECOVERY'))
    or (old.status = 'REASSIGNING' and new.status = 'SEARCHING_RIDER')
    or (old.status = 'DELIVERY_RECOVERY' and new.status in (
      'PICKUP_IN_PROGRESS', 'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY',
      'ARRIVED', 'DELIVERED', 'RECOVERED_RETURNED'
    ))
  ) then
    raise exception 'invalid delivery mission transition: % -> %', old.status, new.status;
  end if;
  if old.first_package_picked_up_at is not null
    and new.first_package_picked_up_at is distinct from old.first_package_picked_up_at then
    raise exception 'first pickup timestamp cannot change';
  end if;
  if old.all_packages_picked_up_at is not null
    and new.all_packages_picked_up_at is distinct from old.all_packages_picked_up_at then
    raise exception 'all-packages pickup timestamp cannot change';
  end if;
  if old.out_for_delivery_at is not null
    and new.out_for_delivery_at is distinct from old.out_for_delivery_at then
    raise exception 'out-for-delivery timestamp cannot change';
  end if;
  if old.arrived_customer_at is not null
    and new.arrived_customer_at is distinct from old.arrived_customer_at then
    raise exception 'customer-arrival timestamp cannot change';
  end if;
  if old.delivered_at is not null
    and new.delivered_at is distinct from old.delivered_at then
    raise exception 'mission delivery timestamp cannot change';
  end if;
  if new.status = 'OUT_FOR_DELIVERY' and (
    old.status not in ('ALL_PACKAGES_PICKED_UP', 'DELIVERY_RECOVERY')
    or new.all_packages_picked_up_at is null
    or new.out_for_delivery_at is null
  ) then
    raise exception 'OUT_FOR_DELIVERY requires every pickup and an authoritative timestamp';
  end if;
  if new.status = 'ARRIVED' and (
    old.status not in ('OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY')
    or new.arrived_customer_at is null
  ) then
    raise exception 'ARRIVED requires the final-delivery stage';
  end if;
  if new.status = 'DELIVERED' and (
    old.status not in ('ARRIVED', 'DELIVERY_RECOVERY')
    or new.delivered_at is null
  ) then
    raise exception 'DELIVERED requires verified or authorized final handoff';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1_api.required_setting_integer(
  p_setting_key text,
  p_branch_id uuid default null,
  p_organization_id uuid default null,
  p_service_zone_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_value jsonb;
  v_result integer;
begin
  v_value := dastak_v1_api.effective_setting_json(
    p_setting_key, p_branch_id, p_organization_id, p_service_zone_id
  );
  if v_value is null or pg_catalog.jsonb_typeof(v_value) <> 'number' then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = p_setting_key || ' is missing or invalid.';
  end if;
  begin
    v_result := (v_value #>> '{}')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = p_setting_key || ' is outside its supported range.';
  end;
  return v_result;
end;
$$;

create or replace function dastak_v1.guard_package()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_handoff_id uuid;
  v_return_verification_id uuid;
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.package_number is distinct from old.package_number
    or new.declared_by is distinct from old.declared_by
    or new.declared_at is distinct from old.declared_at
    or new.created_at is distinct from old.created_at then
    raise exception 'package declaration identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'package version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'DECLARED' and new.status = 'READY')
    or (old.status = 'READY' and new.status = 'PICKED_UP')
    or (old.status = 'PICKED_UP' and new.status in ('IN_TRANSIT', 'RECOVERY'))
    or (old.status = 'IN_TRANSIT' and new.status in ('DELIVERED', 'RECOVERY'))
    or (old.status = 'DELIVERED' and new.status = 'RETURN_PENDING')
    or (old.status = 'RETURN_PENDING' and new.status in ('RETURNED', 'RECOVERY'))
    or (old.status = 'RECOVERY' and new.status in ('IN_TRANSIT', 'DELIVERED', 'RETURNED'))
  ) then
    raise exception 'invalid package transition: % -> %', old.status, new.status;
  end if;
  if old.status = 'DECLARED' and new.status = 'READY' and (
    new.ready_at is null
    or new.current_custody_owner_type <> 'MERCHANT_BRANCH'
    or new.current_custody_owner_id is distinct from old.current_custody_owner_id
  ) then
    raise exception 'Ready packages remain in declared merchant custody';
  end if;
  if old.status = 'READY' and new.status = 'PICKED_UP' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.pickup_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'MERCHANT_BRANCH'
      or new.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_id is null or new.picked_up_at is null
      or not exists (
        select 1
        from dastak_v1.verification_handoffs handoff
        join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
        where handoff.id = v_handoff_id
          and handoff.fulfilment_id = new.fulfilment_id
          and handoff.handoff_type = 'MERCHANT_TO_RIDER'
          and handoff.status = 'CONSUMED'
          and handoff.consumed_by = new.current_custody_owner_id
          and mission.assigned_rider_id = new.current_custody_owner_id
      ) then
      raise exception 'package pickup requires consumed verification by the assigned rider';
    end if;
  elsif old.status = 'PICKED_UP' and new.status = 'IN_TRANSIT' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.final_delivery_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_type is distinct from old.current_custody_owner_type
      or new.current_custody_owner_id is distinct from old.current_custody_owner_id
      or not exists (
        select 1
        from dastak_v1.verification_handoffs handoff
        join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
        where handoff.id = v_handoff_id and handoff.order_id = new.order_id
          and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
          and handoff.status = 'ACTIVE'
          and mission.status = 'ALL_PACKAGES_PICKED_UP'
          and mission.assigned_rider_id = old.current_custody_owner_id
      ) then
      raise exception 'final delivery requires an active parent-order handoff and Rider custody';
    end if;
  elsif old.status = 'IN_TRANSIT' and new.status = 'DELIVERED' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.final_delivery_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_type <> 'CUSTOMER'
      or new.delivered_at is null
      or not exists (
        select 1
        from dastak_v1.verification_handoffs handoff
        join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
        join dastak_v1.orders customer_order on customer_order.id = handoff.order_id
        where handoff.id = v_handoff_id and handoff.order_id = new.order_id
          and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
          and handoff.status in ('CONSUMED', 'OVERRIDDEN')
          and mission.assigned_rider_id = old.current_custody_owner_id
          and customer_order.customer_id = new.current_custody_owner_id
      ) then
      raise exception 'package delivery requires verified Customer custody transfer';
    end if;
  elsif old.status = 'RECOVERY' and new.status = 'RETURNED' then
    begin
      v_return_verification_id := nullif(
        pg_catalog.current_setting('dastak_v1.return_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_return_verification_id := null;
    end;
    if v_return_verification_id is null
      or old.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_type <> 'MERCHANT_RETURN'
      or not exists (
        select 1
        from dastak_v1.return_verifications verification
        join dastak_v1.return_stops stop on stop.id = verification.return_stop_id
        join dastak_v1.return_packages return_package
          on return_package.return_id = verification.return_id
         and return_package.source_delivery_package_id = new.id
         and return_package.destination_branch_id = stop.branch_id
        join dastak_v1.return_missions return_mission
          on return_mission.id = verification.return_mission_id
        where verification.id = v_return_verification_id
          and verification.handoff_type = 'RETURN_RIDER_TO_MERCHANT'
          and verification.status = 'CONSUMED'
          and return_mission.assigned_rider_id = old.current_custody_owner_id
          and new.current_custody_owner_id = stop.branch_id
      ) then
      raise exception 'recovery return requires consumed merchant receipt verification';
    end if;
  elsif new.current_custody_owner_type is distinct from old.current_custody_owner_type
    or new.current_custody_owner_id is distinct from old.current_custody_owner_id then
    raise exception 'package custody may change only through a verified handoff';
  end if;
  if old.ready_at is not null and new.ready_at is distinct from old.ready_at then
    raise exception 'package Ready timestamp cannot change';
  end if;
  if old.picked_up_at is not null
    and new.picked_up_at is distinct from old.picked_up_at then
    raise exception 'package pickup timestamp cannot change';
  end if;
  if old.delivered_at is not null
    and new.delivered_at is distinct from old.delivered_at then
    raise exception 'package delivery timestamp cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1_api.recovery_branch_eligibility(
  p_recovery_case_id uuid,
  p_branch_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case dastak_v1.recovery_cases%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_source dastak_v1.fulfilments%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_operating dastak_v1.branch_operational_states%rowtype;
  v_address jsonb;
  v_customer_location extensions.geometry(Point, 4326);
  v_distance numeric;
  v_radius integer;
  v_held integer;
  v_reasons text[] := '{}'::text[];
begin
  select recovery.* into v_case
  from dastak_v1.recovery_cases recovery where recovery.id = p_recovery_case_id;
  select line.* into v_line from dastak_v1.order_lines line
  where line.id = v_case.order_line_id;
  select fulfilment.* into v_source from dastak_v1.fulfilments fulfilment
  where fulfilment.id = v_case.source_fulfilment_id;
  select branch.* into v_branch from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id;
  select organization.* into v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;
  select state.* into v_operating
  from dastak_v1.branch_operational_states state where state.branch_id = v_branch.id;
  select snapshot.delivery_address into v_address
  from dastak_v1.order_context_snapshots snapshot where snapshot.order_id = v_case.order_id;
  if pg_catalog.jsonb_typeof(v_address -> 'latitude') = 'number'
    and pg_catalog.jsonb_typeof(v_address -> 'longitude') = 'number' then
    v_customer_location := extensions.st_setsrid(extensions.st_makepoint(
      (v_address ->> 'longitude')::double precision,
      (v_address ->> 'latitude')::double precision
    ), 4326);
  end if;
  if v_case.case_type <> 'EXACT_SKU'
    or v_case.status <> 'SEARCHING_EXACT_SKU' then
    v_reasons := pg_catalog.array_append(v_reasons, 'RECOVERY_NOT_SEARCHING');
  end if;
  if v_branch.id is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_NOT_FOUND');
  elsif v_branch.id = v_source.branch_id then
    v_reasons := pg_catalog.array_append(v_reasons, 'ORIGINAL_BRANCH_EXCLUDED');
  end if;
  if v_organization.status is distinct from 'ACTIVE'
    or v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    v_reasons := pg_catalog.array_append(v_reasons, 'ORGANIZATION_NOT_ELIGIBLE');
  end if;
  if v_branch.status is distinct from 'ACTIVE'
    or v_operating.branch_id is null or not v_operating.is_open
    or not v_operating.accepting_orders then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_NOT_OPERATING');
  end if;
  if not exists (
    select 1 from dastak_v1.merchant_sku_selections selection
    where selection.branch_id = v_branch.id
      and selection.sku_id = v_line.sku_id and selection.state = 'SELECTED'
  ) then
    v_reasons := pg_catalog.array_append(v_reasons, 'EXACT_SKU_NOT_SELECTED');
  end if;
  select count(*) into v_held from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = v_branch.id and slot.status = 'HELD';
  if v_held >= coalesce(v_branch.capacity_limit, 0) then
    v_reasons := pg_catalog.array_append(v_reasons, 'AT_CAPACITY');
  end if;
  v_radius := dastak_v1_api.required_setting_integer(
    'recovery.radius_meters', v_branch.id, v_branch.organization_id,
    v_branch.service_zone_id
  );
  if v_customer_location is null or v_branch.location is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'LOCATION_MISSING');
  else
    v_distance := extensions.st_distance(
      v_branch.location::extensions.geography,
      v_customer_location::extensions.geography
    );
    if v_distance > v_radius then
      v_reasons := pg_catalog.array_append(v_reasons, 'OUTSIDE_RECOVERY_RADIUS');
    end if;
  end if;
  return pg_catalog.jsonb_build_object(
    'eligible', pg_catalog.cardinality(v_reasons) = 0,
    'reasons', v_reasons,
    'distanceMeters', v_distance,
    'radiusMeters', v_radius,
    'exactSkuId', v_line.sku_id,
    'requestedQuantity', v_line.quantity
  );
end;
$$;

create function dastak_v1_api.cancel_pre_custody_mission_for_recovery(
  p_order_id uuid,
  p_now timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
begin
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.order_id = p_order_id
    and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
  order by mission.created_at desc limit 1 for update;
  if not found then return null; end if;
  if v_mission.first_package_picked_up_at is not null or exists (
    select 1 from dastak_v1.packages package
    where package.order_id = p_order_id
      and package.current_custody_owner_type = 'RIDER'
  ) then
    raise exception using errcode = '55000',
      message = 'DELIVERY_RECOVERY_REQUIRED';
  end if;
  perform pg_catalog.set_config('dastak_v1.recovery_reroute', 'true', true);
  if v_mission.status in ('ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS') then
    update dastak_v1.delivery_missions mission
    set status = 'REASSIGNING', assigned_rider_id = null,
        assigned_transport_type = null, assigned_at = null,
        version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
    update dastak_v1.delivery_missions mission
    set status = 'SEARCHING_RIDER', version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
  elsif v_mission.status <> 'SEARCHING_RIDER' then
    raise exception using errcode = '55000', message = 'RECOVERY_REROUTE_UNSAFE';
  end if;
  update dastak_v1.delivery_offers offer
  set status = case when offer.status = 'OFFERED' then 'CLOSED' else offer.status end,
      responded_at = case when offer.status = 'OFFERED'
        then coalesce(offer.responded_at, p_now) else offer.responded_at end,
      closed_reason = case when offer.status = 'OFFERED'
        then 'EXACT_SKU_RECOVERY_REROUTE' else offer.closed_reason end,
      version = case when offer.status = 'OFFERED'
        then offer.version + 1 else offer.version end
  where offer.mission_id = v_mission.id and offer.status = 'OFFERED';
  update dastak_v1.delivery_missions mission
  set status = 'CANCELLED', cancelled_at = p_now,
      cancellation_reason = 'EXACT_SKU_RECOVERY_REROUTE',
      version = mission.version + 1
  where mission.id = v_mission.id returning * into v_mission;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_mission.id::text || ':RECOVERY_REROUTE:' || v_mission.version::text,
    'DELIVERY_MISSION', v_mission.id, v_mission.version,
    'RIDER_MISSION_RECOVERY_REROUTED',
    pg_catalog.jsonb_build_object('orderId', p_order_id, 'missionId', v_mission.id)
  );
  return v_mission.id;
end;
$$;

create function dastak_v1_api.seed_merchant_settlement_entry(
  p_order_id uuid,
  p_fulfilment_id uuid,
  p_order_line_id uuid,
  p_entry_suffix text default 'ORIGINAL'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_setting jsonb;
  v_commission_bps integer;
  v_amount bigint;
  v_status dastak_v1.settlement_calculation_status;
  v_id uuid;
begin
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment where fulfilment.id = p_fulfilment_id;
  select line.* into v_line
  from dastak_v1.order_lines line where line.id = p_order_line_id;
  if v_fulfilment.order_id is distinct from p_order_id
    or v_line.order_id is distinct from p_order_id
    or not exists (
      select 1 from dastak_v1.fulfilment_lines fulfilment_line
      where fulfilment_line.fulfilment_id = p_fulfilment_id
        and fulfilment_line.order_line_id = p_order_line_id
        and fulfilment_line.confirmed_quantity = v_line.quantity
    ) then
    raise exception 'invalid merchant settlement source';
  end if;
  v_setting := dastak_v1_api.effective_setting_json(
    'settlement.merchant_commission_bps',
    v_fulfilment.branch_id, v_fulfilment.organization_id, null
  );
  begin
    v_commission_bps := case when pg_catalog.jsonb_typeof(v_setting) = 'number'
      then (v_setting #>> '{}')::integer else null end;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_commission_bps := null;
  end;
  if v_commission_bps between 0 and 10000 then
    v_amount := pg_catalog.floor(
      v_line.line_total_paise::numeric * (10000 - v_commission_bps)::numeric / 10000
    )::bigint;
    v_status := 'CALCULATED';
  else
    v_amount := null;
    v_status := 'SYSTEM_CONFIGURATION_REQUIRED';
  end if;
  insert into dastak_v1.settlement_entries (
    entry_key, subject_type, subject_id, order_id, fulfilment_id,
    order_line_id, entry_type, status, calculation_status,
    gross_amount_paise, amount_paise, calculation_snapshot
  ) values (
    p_order_id::text || ':MERCHANT:' || p_fulfilment_id::text || ':'
      || p_order_line_id::text || ':' || p_entry_suffix,
    'MERCHANT_ORGANIZATION', v_fulfilment.organization_id, p_order_id,
    p_fulfilment_id, p_order_line_id, 'EARNING', 'PENDING', v_status,
    v_line.line_total_paise, v_amount,
    pg_catalog.jsonb_build_object(
      'grossAmountPaise', v_line.line_total_paise,
      'commissionBps', v_commission_bps,
      'configurationRequired', v_status = 'SYSTEM_CONFIGURATION_REQUIRED'
    )
  ) on conflict (entry_key) do nothing returning id into v_id;
  if v_id is null then
    select entry.id into v_id from dastak_v1.settlement_entries entry
    where entry.entry_key = p_order_id::text || ':MERCHANT:'
      || p_fulfilment_id::text || ':' || p_order_line_id::text || ':' || p_entry_suffix;
  end if;
  return v_id;
end;
$$;

create function dastak_v1.seed_settlements_after_payment_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source record;
begin
  if new.outcome <> 'SUCCEEDED' then return new; end if;
  for v_source in
    select fulfilment.id as fulfilment_id, fulfilment_line.order_line_id
    from dastak_v1.fulfilments fulfilment
    join dastak_v1.fulfilment_lines fulfilment_line
      on fulfilment_line.fulfilment_id = fulfilment.id
    where fulfilment.order_id = new.order_id
      and fulfilment.status <> 'RELEASED'
    order by fulfilment.id, fulfilment_line.order_line_id
  loop
    perform dastak_v1_api.seed_merchant_settlement_entry(
      new.order_id, v_source.fulfilment_id, v_source.order_line_id, 'ORIGINAL'
    );
  end loop;
  return new;
end;
$$;

create trigger payment_provider_events_seed_settlements
after insert on dastak_v1.payment_provider_events
for each row when (new.outcome = 'SUCCEEDED')
execute function dastak_v1.seed_settlements_after_payment_event();

create function dastak_v1_api.create_approved_refund(
  p_actor_id uuid,
  p_order_id uuid,
  p_order_line_id uuid,
  p_recovery_case_id uuid,
  p_customer_issue_id uuid,
  p_return_id uuid,
  p_amount_paise bigint,
  p_fault_source dastak_v1.refund_fault_source,
  p_reason text,
  p_approval_kind text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment dastak_v1.payments%rowtype;
  v_existing_total bigint;
  v_refund_id uuid := gen_random_uuid();
  v_entry dastak_v1.settlement_entries%rowtype;
begin
  select payment.* into v_payment
  from dastak_v1.payments payment where payment.order_id = p_order_id for update;
  if not found or v_payment.status <> 'SUCCEEDED'
    or v_payment.provider_payment_reference is null then
    raise exception using errcode = '55000', message = 'PAID_ORDER_REQUIRED';
  end if;
  if p_amount_paise is null or p_amount_paise <= 0 then
    raise exception using errcode = '22023', message = 'invalid refund amount';
  end if;
  select coalesce(sum(refund.amount_paise), 0) into v_existing_total
  from dastak_v1.refunds refund
  where refund.order_id = p_order_id and refund.status <> 'FAILED';
  if v_existing_total + p_amount_paise > v_payment.amount_paise then
    raise exception using errcode = '23514', message = 'REFUND_EXCEEDS_PAYMENT';
  end if;
  insert into dastak_v1.refunds (
    id, order_id, payment_id, order_line_id, recovery_case_id,
    customer_issue_id, return_id, status, fault_source, amount_paise,
    reason, approval_kind, created_by, approved_by, approved_at,
    provider_payment_reference, provider_receipt
  ) values (
    v_refund_id, p_order_id, v_payment.id, p_order_line_id,
    p_recovery_case_id, p_customer_issue_id, p_return_id,
    'APPROVED', p_fault_source, p_amount_paise, pg_catalog.btrim(p_reason),
    p_approval_kind, p_actor_id, case when p_approval_kind = 'AUTHORIZED_OPERATIONS'
      then p_actor_id else null end, pg_catalog.clock_timestamp(),
    v_payment.provider_payment_reference,
    'd1r-' || pg_catalog.replace(v_refund_id::text, '-', '')
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_refund_id::text || ':REFUND_CREATED:1', 'REFUND', v_refund_id, 1,
    'REFUND_CREATED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', p_order_id, 'refundId', v_refund_id,
      'amountPaise', p_amount_paise, 'currency', 'INR',
      'destination', 'ORIGINAL_PAYMENT_METHOD', 'status', 'APPROVED'
    )
  );
  if p_fault_source = 'MERCHANT' and p_order_line_id is not null then
    select entry.* into v_entry
    from dastak_v1.settlement_entries entry
    where entry.order_id = p_order_id
      and entry.order_line_id = p_order_line_id
      and entry.subject_type = 'MERCHANT_ORGANIZATION'
      and entry.entry_type = 'EARNING'
    order by entry.created_at limit 1;
    if found and (v_entry.amount_paise is null or v_entry.amount_paise > 0) then
      insert into dastak_v1.settlement_entries (
        entry_key, subject_type, subject_id, order_id, fulfilment_id,
        order_line_id, refund_id, entry_type, status, calculation_status,
        gross_amount_paise, amount_paise, calculation_snapshot
      ) values (
        p_order_id::text || ':REFUND_ADJUSTMENT:' || v_refund_id::text,
        v_entry.subject_type, v_entry.subject_id, p_order_id,
        v_entry.fulfilment_id, p_order_line_id, v_refund_id,
        'REFUND_ADJUSTMENT', 'PENDING',
        case when v_entry.amount_paise is null
          then 'SYSTEM_CONFIGURATION_REQUIRED'::dastak_v1.settlement_calculation_status
          else 'CALCULATED'::dastak_v1.settlement_calculation_status end,
        p_amount_paise,
        case when v_entry.amount_paise is null then null
          else -least(v_entry.amount_paise, p_amount_paise) end,
        pg_catalog.jsonb_build_object(
          'reason', 'MERCHANT_CAUSED_REFUND',
          'originalEarningEntryId', v_entry.id,
          'historicalSettlementPreserved', true
        )
      );
    end if;
  end if;
  return v_refund_id;
end;
$$;

create function dastak_v1_api.report_exact_sku_failure(
  p_actor_id uuid,
  p_fulfilment_id uuid,
  p_order_line_id uuid,
  p_reason text,
  p_expected_fulfilment_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'reportExactSkuFailure';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_case dastak_v1.recovery_cases%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_has_remaining boolean;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_fulfilment_id is null or p_order_line_id is null
    or p_expected_fulfilment_version is null
    or nullif(pg_catalog.btrim(p_reason), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid exact-SKU failure';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'fulfilmentId', p_fulfilment_id, 'orderLineId', p_order_line_id,
    'reason', pg_catalog.btrim(p_reason),
    'expectedVersion', p_expected_fulfilment_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment where fulfilment.id = p_fulfilment_id for update;
  if not found or not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_fulfilment.organization_id, 'merchant.fulfilment.manage',
    v_fulfilment.branch_id
  ) then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;
  select customer_order.* into v_order from dastak_v1.orders customer_order
  where customer_order.id = v_fulfilment.order_id for update;
  select line.* into v_line from dastak_v1.order_lines line
  where line.id = p_order_line_id for update;
  if v_fulfilment.version <> p_expected_fulfilment_version then
    raise exception using errcode = '40001', message = 'STALE_FULFILMENT_VERSION';
  end if;
  if v_order.status <> 'PREPARING' or v_fulfilment.status <> 'PREPARING'
    or v_fulfilment.package_count is not null
    or v_line.order_id <> v_order.id or v_line.line_type <> 'RETAIL_SKU'
    or v_line.status <> 'FULFILLING'
    or not exists (
      select 1 from dastak_v1.fulfilment_lines fulfilment_line
      where fulfilment_line.fulfilment_id = v_fulfilment.id
        and fulfilment_line.order_line_id = v_line.id
        and fulfilment_line.confirmed_quantity = v_line.quantity
    ) then
    raise exception using errcode = '55000', message = 'EXACT_SKU_RECOVERY_NOT_ALLOWED';
  end if;
  perform dastak_v1_api.cancel_pre_custody_mission_for_recovery(v_order.id, v_now);
  insert into dastak_v1.recovery_cases (
    case_type, order_id, order_line_id, source_fulfilment_id,
    status, fault_source, reason, opened_by, opened_at
  ) values (
    'EXACT_SKU', v_order.id, v_line.id, v_fulfilment.id,
    'SEARCHING_EXACT_SKU', 'MERCHANT', pg_catalog.btrim(p_reason),
    p_actor_id, v_now
  ) returning * into v_case;
  update dastak_v1.order_lines line
  set status = 'RECOVERY', version = line.version + 1
  where line.id = v_line.id;
  update dastak_v1.inventory_holds hold
  set status = 'RELEASED', released_at = v_now,
      release_reason = 'EXACT_SKU_EXCEPTION', version = hold.version + 1
  where hold.fulfilment_id = v_fulfilment.id
    and hold.order_line_id = v_line.id and hold.status = 'HELD';
  select exists (
    select 1
    from dastak_v1.fulfilment_lines fulfilment_line
    join dastak_v1.order_lines line on line.id = fulfilment_line.order_line_id
    where fulfilment_line.fulfilment_id = v_fulfilment.id
      and line.id <> v_line.id and line.status = 'FULFILLING'
  ) into v_has_remaining;
  if not v_has_remaining then
    perform pg_catalog.set_config('dastak_v1.exact_recovery_release', 'true', true);
    update dastak_v1.fulfilments fulfilment
    set status = 'RELEASED', released_at = v_now,
        release_reason = 'EXACT_SKU_RECOVERY', version = fulfilment.version + 1
    where fulfilment.id = v_fulfilment.id returning * into v_fulfilment;
    update dastak_v1.retail_capacity_slots slot
    set status = 'RELEASED', released_at = v_now,
        release_reason = 'EXACT_SKU_RECOVERY', version = slot.version + 1
    where slot.fulfilment_id = v_fulfilment.id and slot.status = 'HELD';
  end if;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_case.id::text || ':RECOVERY_STARTED:1', 'RECOVERY_CASE', v_case.id, 1,
    'RECOVERY_STARTED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id, 'recoveryCaseId', v_case.id,
      'orderLineId', v_line.id, 'skuId', v_line.sku_id,
      'quantity', v_line.quantity, 'exactSkuOnly', true
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'EXACT_SKU_RECOVERY_STARTED', 'recovery_case', v_case.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id, 'orderLineId', v_line.id,
      'sourceFulfilmentId', v_fulfilment.id, 'reason', pg_catalog.btrim(p_reason)
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'recoveryCaseId', v_case.id, 'orderId', v_order.id,
    'orderLineId', v_line.id, 'status', v_case.status,
    'exactSkuId', v_line.sku_id, 'quantity', v_line.quantity,
    'customerPaymentChanged', false
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_case.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_report_exact_sku_failure(
  p_fulfilment_id uuid,
  p_order_line_id uuid,
  p_reason text,
  p_expected_fulfilment_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.report_exact_sku_failure(
    auth.uid(), p_fulfilment_id, p_order_line_id, p_reason,
    p_expected_fulfilment_version, p_idempotency_key
  );
$$;

create function dastak_v1_api.create_exact_sku_recovery_offer(
  p_actor_id uuid,
  p_recovery_case_id uuid,
  p_branch_id uuid,
  p_expected_case_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'createExactSkuRecoveryOffer';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_case dastak_v1.recovery_cases%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_eligibility jsonb;
  v_timeout integer;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_offer dastak_v1.recovery_opportunities%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.recovery.manage');
  if p_recovery_case_id is null or p_branch_id is null
    or p_expected_case_version is null or p_expected_case_version < 1
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid recovery offer';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'recoveryCaseId', p_recovery_case_id, 'branchId', p_branch_id,
    'expectedVersion', p_expected_case_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select recovery.* into v_case from dastak_v1.recovery_cases recovery
  where recovery.id = p_recovery_case_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'recovery not found'; end if;
  if v_case.version <> p_expected_case_version then
    raise exception using errcode = '40001', message = 'STALE_RECOVERY_VERSION';
  end if;
  if v_case.case_type <> 'EXACT_SKU' or v_case.status <> 'SEARCHING_EXACT_SKU' then
    raise exception using errcode = '55000', message = 'RECOVERY_NOT_SEARCHING';
  end if;
  select line.* into v_line from dastak_v1.order_lines line
  where line.id = v_case.order_line_id;
  select branch.* into v_branch from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id;
  v_eligibility := dastak_v1_api.recovery_branch_eligibility(
    v_case.id, p_branch_id
  );
  if not coalesce((v_eligibility ->> 'eligible')::boolean, false) then
    raise exception using errcode = '55000', message = 'RECOVERY_BRANCH_INELIGIBLE',
      detail = (v_eligibility -> 'reasons')::text;
  end if;
  v_timeout := dastak_v1_api.required_setting_integer(
    'recovery.offer_timeout_seconds', v_branch.id,
    v_branch.organization_id, v_branch.service_zone_id
  );
  insert into dastak_v1.recovery_opportunities (
    recovery_case_id, order_id, order_line_id, sku_id,
    organization_id, branch_id, requested_quantity,
    status, started_at, expires_at
  ) values (
    v_case.id, v_case.order_id, v_line.id, v_line.sku_id,
    v_branch.organization_id, v_branch.id, v_line.quantity,
    'OFFERED', v_now, v_now + pg_catalog.make_interval(secs => v_timeout)
  ) returning * into v_offer;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_offer.id::text || ':RECOVERY_OFFERED:1', 'RECOVERY_OPPORTUNITY',
    v_offer.id, 1, 'RECOVERY_OPPORTUNITY_OFFERED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_case.order_id, 'recoveryCaseId', v_case.id,
      'recoveryOpportunityId', v_offer.id, 'branchId', v_branch.id,
      'skuId', v_line.sku_id, 'quantity', v_line.quantity,
      'expiresAt', v_offer.expires_at
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'recoveryCaseId', v_case.id, 'recoveryOpportunityId', v_offer.id,
    'status', v_offer.status, 'expiresAt', v_offer.expires_at,
    'exactSkuId', v_line.sku_id, 'quantity', v_line.quantity,
    'branchId', v_branch.id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_offer.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_create_exact_sku_recovery_offer(
  p_recovery_case_id uuid,
  p_branch_id uuid,
  p_expected_case_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.create_exact_sku_recovery_offer(
    auth.uid(), p_recovery_case_id, p_branch_id,
    p_expected_case_version, p_idempotency_key
  );
$$;

create function dastak_v1_api.respond_exact_sku_recovery_offer(
  p_actor_id uuid,
  p_recovery_opportunity_id uuid,
  p_response text,
  p_promised_prep_minutes integer,
  p_expected_opportunity_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'respondExactSkuRecoveryOffer';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_offer dastak_v1.recovery_opportunities%rowtype;
  v_case dastak_v1.recovery_cases%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_eligibility jsonb;
  v_options jsonb;
  v_held integer;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_recovery_opportunity_id is null or p_response not in ('ACCEPT', 'UNAVAILABLE')
    or p_expected_opportunity_version is null
    or (p_response = 'ACCEPT' and (p_promised_prep_minutes is null
      or p_promised_prep_minutes <= 0))
    or (p_response = 'UNAVAILABLE' and p_promised_prep_minutes is not null)
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid recovery response';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'recoveryOpportunityId', p_recovery_opportunity_id,
    'response', p_response, 'promisedPrepMinutes', p_promised_prep_minutes,
    'expectedVersion', p_expected_opportunity_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select opportunity.* into v_offer
  from dastak_v1.recovery_opportunities opportunity
  where opportunity.id = p_recovery_opportunity_id for update;
  if not found or not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_offer.organization_id, 'merchant.fulfilment.manage',
    v_offer.branch_id
  ) then
    raise exception using errcode = 'P0002', message = 'recovery opportunity not found';
  end if;
  select recovery.* into v_case from dastak_v1.recovery_cases recovery
  where recovery.id = v_offer.recovery_case_id for update;
  select line.* into v_line from dastak_v1.order_lines line
  where line.id = v_offer.order_line_id for update;
  select branch.* into v_branch from dastak_v1.merchant_branches branch
  where branch.id = v_offer.branch_id for update;
  if v_offer.version <> p_expected_opportunity_version then
    raise exception using errcode = '40001', message = 'STALE_RECOVERY_OPPORTUNITY_VERSION';
  end if;
  if v_offer.status <> 'OFFERED' or v_offer.expires_at <= v_now
    or v_case.status <> 'SEARCHING_EXACT_SKU' or v_line.status <> 'RECOVERY' then
    raise exception using errcode = '55000', message = 'RECOVERY_OPPORTUNITY_CLOSED';
  end if;
  if p_response = 'UNAVAILABLE' then
    update dastak_v1.recovery_opportunities opportunity
    set status = 'DECLINED', responded_by = p_actor_id, responded_at = v_now,
        version = opportunity.version + 1
    where opportunity.id = v_offer.id returning * into v_offer;
    v_response := pg_catalog.jsonb_build_object(
      'recoveryOpportunityId', v_offer.id, 'recoveryCaseId', v_case.id,
      'status', v_offer.status
    );
  else
    v_eligibility := dastak_v1_api.recovery_branch_eligibility(v_case.id, v_branch.id);
    if not coalesce((v_eligibility ->> 'eligible')::boolean, false) then
      raise exception using errcode = '55000', message = 'RECOVERY_BRANCH_INELIGIBLE',
        detail = (v_eligibility -> 'reasons')::text;
    end if;
    v_options := dastak_v1_api.effective_setting_json(
      'retail.prep_time_options_minutes', v_branch.id,
      v_branch.organization_id, v_branch.service_zone_id
    );
    if pg_catalog.jsonb_typeof(v_options) <> 'array' or not exists (
      select 1 from pg_catalog.jsonb_array_elements_text(v_options) option
      where option::integer = p_promised_prep_minutes
    ) then
      raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
        detail = 'Recovery preparation choice is not explicitly configured.';
    end if;
    perform 1 from dastak_v1.retail_capacity_slots slot
    where slot.branch_id = v_branch.id order by slot.id for update;
    select count(*) into v_held from dastak_v1.retail_capacity_slots slot
    where slot.branch_id = v_branch.id and slot.status = 'HELD';
    if v_held >= v_branch.capacity_limit then
      raise exception using errcode = '55000', message = 'MERCHANT_CAPACITY_UNAVAILABLE';
    end if;
    update dastak_v1.recovery_opportunities opportunity
    set status = 'SELECTED', promised_prep_minutes = p_promised_prep_minutes,
        responded_by = p_actor_id, responded_at = v_now,
        version = opportunity.version + 1
    where opportunity.id = v_offer.id returning * into v_offer;
    insert into dastak_v1.fulfilments (
      order_id, organization_id, branch_id, source_opportunity_id,
      source_recovery_opportunity_id, fulfilment_type, status,
      promised_prep_minutes, committed_at, prep_started_at,
      estimated_ready_at
    ) values (
      v_case.order_id, v_offer.organization_id, v_offer.branch_id, null,
      v_offer.id, 'RECOVERY', 'PREPARING', p_promised_prep_minutes,
      v_now, v_now,
      v_now + pg_catalog.make_interval(mins => p_promised_prep_minutes)
    ) returning * into v_fulfilment;
    insert into dastak_v1.fulfilment_lines (
      fulfilment_id, order_line_id, confirmed_quantity
    ) values (v_fulfilment.id, v_line.id, v_line.quantity);
    insert into dastak_v1.inventory_holds (
      fulfilment_id, order_line_id, branch_id, held_quantity,
      status, held_at
    ) values (
      v_fulfilment.id, v_line.id, v_offer.branch_id, v_line.quantity,
      'HELD', v_now
    );
    insert into dastak_v1.retail_capacity_slots (
      branch_id, fulfilment_id, status, held_at
    ) values (v_offer.branch_id, v_fulfilment.id, 'HELD', v_now);
    update dastak_v1.order_lines line
    set status = 'FULFILLING', version = line.version + 1
    where line.id = v_line.id;
    update dastak_v1.recovery_cases recovery
    set status = 'RECOVERED', replacement_fulfilment_id = v_fulfilment.id,
        resolution = 'Exact SKU and full quantity physically confirmed by replacement branch.',
        resolved_by = p_actor_id, resolved_at = v_now,
        version = recovery.version + 1
    where recovery.id = v_case.id returning * into v_case;
    update dastak_v1.recovery_opportunities opportunity
    set status = 'CLOSED', responded_at = coalesce(opportunity.responded_at, v_now),
        closed_reason = 'ANOTHER_RECOVERY_BRANCH_SELECTED',
        version = opportunity.version + 1
    where opportunity.recovery_case_id = v_case.id
      and opportunity.id <> v_offer.id and opportunity.status = 'OFFERED';
    perform dastak_v1_api.seed_merchant_settlement_entry(
      v_case.order_id, v_fulfilment.id, v_line.id, 'RECOVERY'
    );
    perform dastak_v1_api.create_exact_recovery_settlement_debit(
      v_case.id, v_fulfilment.id
    );
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_case.id::text || ':RECOVERY_SUCCEEDED:' || v_case.version::text,
      'RECOVERY_CASE', v_case.id, v_case.version,
      'RECOVERY_SUCCEEDED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_case.order_id, 'orderLineId', v_line.id,
        'replacementFulfilmentId', v_fulfilment.id,
        'exactSkuId', v_line.sku_id, 'quantity', v_line.quantity,
        'additionalCustomerPaymentPaise', 0
      )
    );
    v_response := pg_catalog.jsonb_build_object(
      'recoveryOpportunityId', v_offer.id, 'recoveryCaseId', v_case.id,
      'status', v_case.status, 'replacementFulfilmentId', v_fulfilment.id,
      'exactSkuId', v_line.sku_id, 'quantity', v_line.quantity,
      'additionalCustomerPaymentPaise', 0
    );
  end if;
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_offer.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_respond_exact_sku_recovery_offer(
  p_recovery_opportunity_id uuid,
  p_response text,
  p_promised_prep_minutes integer,
  p_expected_opportunity_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.respond_exact_sku_recovery_offer(
    auth.uid(), p_recovery_opportunity_id, p_response,
    p_promised_prep_minutes, p_expected_opportunity_version,
    p_idempotency_key
  );
$$;

create function dastak_v1_api.fail_exact_sku_recovery(
  p_actor_id uuid,
  p_recovery_case_id uuid,
  p_reason text,
  p_expected_case_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'failExactSkuRecovery';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_case dastak_v1.recovery_cases%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_remaining integer;
  v_amount bigint;
  v_refund_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.recovery.manage');
  if p_recovery_case_id is null or p_expected_case_version is null
    or nullif(pg_catalog.btrim(p_reason), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid recovery failure';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'recoveryCaseId', p_recovery_case_id, 'reason', pg_catalog.btrim(p_reason),
    'expectedVersion', p_expected_case_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select recovery.* into v_case from dastak_v1.recovery_cases recovery
  where recovery.id = p_recovery_case_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'recovery not found'; end if;
  select customer_order.* into v_order from dastak_v1.orders customer_order
  where customer_order.id = v_case.order_id for update;
  select line.* into v_line from dastak_v1.order_lines line
  where line.id = v_case.order_line_id for update;
  select payment.* into v_payment from dastak_v1.payments payment
  where payment.order_id = v_order.id for update;
  if v_case.version <> p_expected_case_version then
    raise exception using errcode = '40001', message = 'STALE_RECOVERY_VERSION';
  end if;
  if v_case.case_type <> 'EXACT_SKU' or v_case.status <> 'SEARCHING_EXACT_SKU'
    or v_line.status <> 'RECOVERY' then
    raise exception using errcode = '55000', message = 'RECOVERY_NOT_SEARCHING';
  end if;
  update dastak_v1.recovery_opportunities opportunity
  set status = case
        when opportunity.expires_at <= v_now
          then 'EXPIRED'::dastak_v1.recovery_opportunity_status
        else 'CLOSED'::dastak_v1.recovery_opportunity_status
      end,
      responded_at = coalesce(opportunity.responded_at, v_now),
      closed_reason = 'RECOVERY_FAILED', version = opportunity.version + 1
  where opportunity.recovery_case_id = v_case.id and opportunity.status = 'OFFERED';
  update dastak_v1.order_lines line
  set status = 'REFUNDED', version = line.version + 1
  where line.id = v_line.id;
  select count(*) into v_remaining from dastak_v1.order_lines line
  where line.order_id = v_order.id and line.id <> v_line.id
    and line.status <> 'REFUNDED';
  v_amount := case when v_remaining = 0 then v_payment.amount_paise else
    v_line.line_total_paise
      + pg_catalog.ceil(v_line.line_total_paise::numeric * v_line.tax_rate_bps / 10000)::bigint
  end;
  v_refund_id := dastak_v1_api.create_approved_refund(
    p_actor_id, v_order.id, v_line.id, v_case.id, null, null,
    v_amount, 'MERCHANT', pg_catalog.btrim(p_reason), 'AUTOMATIC_POLICY'
  );
  update dastak_v1.recovery_cases recovery
  set status = 'RECOVERY_FAILED', resolution = pg_catalog.btrim(p_reason),
      resolved_by = p_actor_id, resolved_at = v_now,
      version = recovery.version + 1
  where recovery.id = v_case.id returning * into v_case;
  if v_remaining = 0 then
    update dastak_v1.orders customer_order
    set status = 'DASTAK_FULFILMENT_FAILURE', version = customer_order.version + 1
    where customer_order.id = v_order.id returning * into v_order;
    insert into dastak_v1.order_state_journal (
      order_id, from_status, to_status, order_version,
      command_name, actor_id, reason, metadata
    ) values (
      v_order.id, 'PREPARING', 'DASTAK_FULFILMENT_FAILURE', v_order.version,
      v_command, p_actor_id, pg_catalog.btrim(p_reason),
      pg_catalog.jsonb_build_object('recoveryCaseId', v_case.id, 'refundId', v_refund_id)
    );
  end if;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_case.id::text || ':RECOVERY_FAILED:' || v_case.version::text,
    'RECOVERY_CASE', v_case.id, v_case.version,
    'RECOVERY_FAILED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id, 'orderLineId', v_line.id,
      'refundId', v_refund_id, 'refundAmountPaise', v_amount,
      'remainingDeliverableLineCount', v_remaining,
      'orderStatus', v_order.status
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'recoveryCaseId', v_case.id, 'status', v_case.status,
    'orderId', v_order.id, 'orderStatus', v_order.status,
    'orderLineId', v_line.id, 'lineStatus', 'REFUNDED',
    'refundId', v_refund_id, 'refundAmountPaise', v_amount,
    'remainingDeliverableLineCount', v_remaining
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_case.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_fail_exact_sku_recovery(
  p_recovery_case_id uuid,
  p_reason text,
  p_expected_case_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.fail_exact_sku_recovery(
    auth.uid(), p_recovery_case_id, p_reason,
    p_expected_case_version, p_idempotency_key
  );
$$;

create function dastak_v1_api.report_customer_issue(
  p_actor_id uuid,
  p_order_id uuid,
  p_order_line_id uuid,
  p_category text,
  p_description text,
  p_object_path text,
  p_content_type text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'reportCustomerIssue';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_category dastak_v1.customer_issue_category;
  v_issue dastak_v1.customer_issues%rowtype;
  v_evidence_id uuid;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  begin v_category := p_category::dastak_v1.customer_issue_category;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid issue category';
  end;
  if p_order_id is null
    or nullif(pg_catalog.btrim(p_description), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_description)) not between 3 and 1000
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200
    or (p_object_path is null) <> (p_content_type is null)
    or (p_content_type is not null
      and p_content_type not in ('image/jpeg', 'image/png', 'image/heic')) then
    raise exception using errcode = '22023', message = 'invalid customer issue';
  end if;
  if p_object_path is not null and (
    pg_catalog.split_part(p_object_path, '/', 1) <> 'customer-issue'
    or pg_catalog.split_part(p_object_path, '/', 2) <> p_actor_id::text
    or pg_catalog.array_length(pg_catalog.string_to_array(p_object_path, '/'), 1) <> 3
  ) then
    raise exception using errcode = '22023', message = 'invalid issue evidence path';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'orderId', p_order_id, 'orderLineId', p_order_line_id,
    'category', v_category, 'description', pg_catalog.btrim(p_description),
    'objectPath', p_object_path, 'contentType', p_content_type
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select customer_order.* into v_order from dastak_v1.orders customer_order
  where customer_order.id = p_order_id and customer_order.customer_id = p_actor_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'order not found'; end if;
  if v_order.paid_at is null or v_order.status in (
    'UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT'
  ) then
    raise exception using errcode = '55000', message = 'PAID_ORDER_REQUIRED';
  end if;
  if p_order_line_id is not null and not exists (
    select 1 from dastak_v1.order_lines line
    where line.id = p_order_line_id and line.order_id = v_order.id
  ) then
    raise exception using errcode = 'P0002', message = 'order line not found';
  end if;
  insert into dastak_v1.customer_issues (
    order_id, customer_id, order_line_id, category, description
  ) values (
    v_order.id, p_actor_id, p_order_line_id, v_category,
    pg_catalog.btrim(p_description)
  ) returning * into v_issue;
  if p_object_path is not null then
    insert into dastak_v1.customer_issue_evidence (
      issue_id, order_id, order_line_id, object_path,
      content_type, captured_by
    ) values (
      v_issue.id, v_order.id, p_order_line_id, p_object_path,
      p_content_type, p_actor_id
    ) returning id into v_evidence_id;
  end if;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_issue.id::text || ':CUSTOMER_ISSUE_REPORTED:1',
    'CUSTOMER_ISSUE', v_issue.id, 1, 'CUSTOMER_ISSUE_REPORTED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id, 'issueId', v_issue.id,
      'orderLineId', p_order_line_id, 'category', v_category,
      'evidenceId', v_evidence_id
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'issueId', v_issue.id, 'orderId', v_order.id,
    'orderLineId', p_order_line_id, 'category', v_category,
    'status', v_issue.status, 'reportedAt', v_issue.reported_at,
    'evidenceId', v_evidence_id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_issue.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_report_customer_issue(
  p_order_id uuid,
  p_order_line_id uuid,
  p_category text,
  p_description text,
  p_object_path text,
  p_content_type text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.report_customer_issue(
    auth.uid(), p_order_id, p_order_line_id, p_category,
    p_description, p_object_path, p_content_type, p_idempotency_key
  );
$$;

create function dastak_v1_api.decide_customer_issue(
  p_actor_id uuid,
  p_issue_id uuid,
  p_decision text,
  p_refund_amount_paise bigint,
  p_fault_source text,
  p_return_package_count integer,
  p_reason text,
  p_expected_issue_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'decideCustomerIssue';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_issue dastak_v1.customer_issues%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_fault dastak_v1.refund_fault_source;
  v_window integer;
  v_limit integer;
  v_return dastak_v1.returns%rowtype;
  v_mission dastak_v1.return_missions%rowtype;
  v_stop dastak_v1.return_stops%rowtype;
  v_verification_id uuid;
  v_refund_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.returns.approve');
  if p_issue_id is null or p_decision not in (
    'REJECT', 'RESOLVE_NO_REFUND', 'REFUND_WITHOUT_RETURN', 'PHYSICAL_RETURN'
  ) or p_expected_issue_version is null
    or nullif(pg_catalog.btrim(p_reason), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid issue decision';
  end if;
  if p_decision in ('REFUND_WITHOUT_RETURN', 'PHYSICAL_RETURN') then
    begin v_fault := p_fault_source::dastak_v1.refund_fault_source;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'invalid refund fault source';
    end;
    if p_refund_amount_paise is null or p_refund_amount_paise <= 0
      or (p_decision = 'PHYSICAL_RETURN'
        and (p_return_package_count is null or p_return_package_count < 1))
      or (p_decision = 'REFUND_WITHOUT_RETURN' and p_return_package_count is not null) then
      raise exception using errcode = '22023', message = 'invalid return/refund decision';
    end if;
  elsif p_refund_amount_paise is not null or p_fault_source is not null
    or p_return_package_count is not null then
    raise exception using errcode = '22023', message = 'unexpected refund decision values';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'issueId', p_issue_id, 'decision', p_decision,
    'refundAmountPaise', p_refund_amount_paise, 'faultSource', p_fault_source,
    'returnPackageCount', p_return_package_count,
    'reason', pg_catalog.btrim(p_reason), 'expectedVersion', p_expected_issue_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select issue.* into v_issue from dastak_v1.customer_issues issue
  where issue.id = p_issue_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'issue not found'; end if;
  select customer_order.* into v_order from dastak_v1.orders customer_order
  where customer_order.id = v_issue.order_id for update;
  if v_issue.version <> p_expected_issue_version
    or v_issue.status not in ('OPEN', 'UNDER_REVIEW') then
    raise exception using errcode = '40001', message = 'STALE_ISSUE_VERSION';
  end if;
  if p_decision in ('REFUND_WITHOUT_RETURN', 'PHYSICAL_RETURN') then
    perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.refunds.approve');
    if v_order.status <> 'DELIVERED' or v_order.delivered_at is null then
      raise exception using errcode = '55000', message = 'DELIVERED_ORDER_REQUIRED';
    end if;
    v_window := dastak_v1_api.required_setting_integer('returns.reporting_window_seconds');
    if v_issue.reported_at > v_order.delivered_at + pg_catalog.make_interval(secs => v_window) then
      raise exception using errcode = '55000', message = 'RETURN_REPORTING_WINDOW_EXPIRED';
    end if;
    v_limit := dastak_v1_api.required_setting_integer('refunds.approval_limit_paise');
    if p_refund_amount_paise > v_limit then
      raise exception using errcode = '42501', message = 'REFUND_APPROVAL_LIMIT_EXCEEDED';
    end if;
    if v_issue.order_line_id is not null then
      select line.* into v_line from dastak_v1.order_lines line
      where line.id = v_issue.order_line_id;
      if p_refund_amount_paise > v_line.line_total_paise
        + pg_catalog.ceil(v_line.line_total_paise::numeric * v_line.tax_rate_bps / 10000)::bigint then
        raise exception using errcode = '23514', message = 'REFUND_EXCEEDS_AFFECTED_LINE';
      end if;
      select fulfilment.* into v_fulfilment
      from dastak_v1.fulfilments fulfilment
      join dastak_v1.fulfilment_lines fulfilment_line
        on fulfilment_line.fulfilment_id = fulfilment.id
      where fulfilment_line.order_line_id = v_line.id
        and fulfilment.status = 'COMPLETED'
      order by (fulfilment.fulfilment_type = 'RECOVERY') desc,
        fulfilment.committed_at desc limit 1;
    end if;
    if v_issue.category not in ('DELIVERY_PROBLEM', 'OTHER') and not exists (
      select 1 from dastak_v1.customer_issue_evidence evidence
      where evidence.issue_id = v_issue.id
    ) then
      raise exception using errcode = '55000', message = 'ISSUE_EVIDENCE_REQUIRED';
    end if;
  end if;
  if p_decision = 'REJECT' then
    update dastak_v1.customer_issues issue
    set status = 'REJECTED', reviewed_by = p_actor_id, reviewed_at = v_now,
        resolution = pg_catalog.btrim(p_reason), resolved_at = v_now,
        version = issue.version + 1
    where issue.id = v_issue.id returning * into v_issue;
  elsif p_decision = 'RESOLVE_NO_REFUND' then
    update dastak_v1.customer_issues issue
    set status = 'RESOLVED', reviewed_by = p_actor_id, reviewed_at = v_now,
        resolution = pg_catalog.btrim(p_reason), resolved_at = v_now,
        version = issue.version + 1
    where issue.id = v_issue.id returning * into v_issue;
  else
    if v_issue.order_line_id is null or v_line.id is null or v_fulfilment.id is null then
      raise exception using errcode = '55000', message = 'AFFECTED_RETAIL_LINE_REQUIRED';
    end if;
    insert into dastak_v1.returns (
      order_id, source, customer_issue_id, status, physical_return_required,
      approved_refund_amount_paise, refund_fault_source, reason,
      requested_by, requested_at
    ) values (
      v_order.id, 'CUSTOMER_ISSUE', v_issue.id, 'REQUESTED',
      p_decision = 'PHYSICAL_RETURN', p_refund_amount_paise, v_fault,
      pg_catalog.btrim(p_reason), v_issue.customer_id, v_issue.reported_at
    ) returning * into v_return;
    insert into dastak_v1.return_lines (
      return_id, order_line_id, quantity, reason
    ) values (v_return.id, v_line.id, v_line.quantity, pg_catalog.btrim(p_reason));
    update dastak_v1.returns customer_return
    set status = 'APPROVED', decided_by = p_actor_id, decided_at = v_now,
        version = customer_return.version + 1
    where customer_return.id = v_return.id returning * into v_return;
    if p_decision = 'REFUND_WITHOUT_RETURN' then
      update dastak_v1.returns customer_return
      set status = 'RESOLUTION_WITHOUT_PHYSICAL_RETURN',
          version = customer_return.version + 1
      where customer_return.id = v_return.id returning * into v_return;
      v_refund_id := dastak_v1_api.create_approved_refund(
        p_actor_id, v_order.id, v_line.id, null, v_issue.id, v_return.id,
        p_refund_amount_paise, v_fault, pg_catalog.btrim(p_reason),
        'AUTHORIZED_OPERATIONS'
      );
      update dastak_v1.returns customer_return
      set status = 'COMPLETED', completed_at = v_now,
          version = customer_return.version + 1
      where customer_return.id = v_return.id returning * into v_return;
      update dastak_v1.customer_issues issue
      set status = 'RESOLVED', reviewed_by = p_actor_id, reviewed_at = v_now,
          resolution = pg_catalog.btrim(p_reason), resolved_at = v_now,
          version = issue.version + 1
      where issue.id = v_issue.id returning * into v_issue;
    else
      update dastak_v1.returns customer_return
      set status = 'RETURN_REQUIRED', version = customer_return.version + 1
      where customer_return.id = v_return.id returning * into v_return;
      for v_counter in 1..p_return_package_count loop
        insert into dastak_v1.return_packages (
          return_id, order_id, package_number, destination_branch_id,
          status, current_custody_owner_type, current_custody_owner_id,
          created_by
        ) values (
          v_return.id, v_order.id, v_counter, v_fulfilment.branch_id,
          'CUSTOMER_READY', 'CUSTOMER', v_issue.customer_id, p_actor_id
        );
      end loop;
      insert into dastak_v1.return_missions (
        return_id, order_id, status
      ) values (v_return.id, v_order.id, 'RIDER_SEARCH') returning * into v_mission;
      insert into dastak_v1.return_stops (
        return_mission_id, return_id, branch_id, stop_sequence,
        status, package_count
      ) values (
        v_mission.id, v_return.id, v_fulfilment.branch_id, 1,
        'PENDING', p_return_package_count
      ) returning * into v_stop;
      v_verification_id := gen_random_uuid();
      insert into dastak_v1.return_verifications (
        id, return_id, return_mission_id, handoff_type, status,
        code_digest
      ) values (
        v_verification_id, v_return.id, v_mission.id,
        'CUSTOMER_TO_RETURN_RIDER', 'INACTIVE',
        private.dastak_v1_handoff_digest(private.dastak_v1_handoff_code(
          v_verification_id, 'CUSTOMER_TO_RETURN_RIDER', 1
        ))
      );
      v_verification_id := gen_random_uuid();
      insert into dastak_v1.return_verifications (
        id, return_id, return_mission_id, return_stop_id,
        handoff_type, status, code_digest
      ) values (
        v_verification_id, v_return.id, v_mission.id, v_stop.id,
        'RETURN_RIDER_TO_MERCHANT', 'INACTIVE',
        private.dastak_v1_handoff_digest(private.dastak_v1_handoff_code(
          v_verification_id, 'RETURN_RIDER_TO_MERCHANT', 1
        ))
      );
      update dastak_v1.returns customer_return
      set status = 'RIDER_SEARCH', version = customer_return.version + 1
      where customer_return.id = v_return.id returning * into v_return;
      update dastak_v1.customer_issues issue
      set status = 'UNDER_REVIEW', reviewed_by = p_actor_id, reviewed_at = v_now,
          version = issue.version + 1
      where issue.id = v_issue.id returning * into v_issue;
    end if;
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_return.id::text || ':RETURN_APPROVED:' || v_return.version::text,
      'RETURN', v_return.id, v_return.version, 'RETURN_APPROVED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id, 'issueId', v_issue.id, 'returnId', v_return.id,
        'physicalReturnRequired', v_return.physical_return_required,
        'refundId', v_refund_id,
        'refundAmountPaise', p_refund_amount_paise
      )
    );
  end if;
  v_response := pg_catalog.jsonb_build_object(
    'issueId', v_issue.id, 'issueStatus', v_issue.status,
    'returnId', v_return.id, 'returnStatus', v_return.status,
    'returnMissionId', v_mission.id, 'refundId', v_refund_id,
    'decision', p_decision
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_issue.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_decide_customer_issue(
  p_issue_id uuid,
  p_decision text,
  p_refund_amount_paise bigint,
  p_fault_source text,
  p_return_package_count integer,
  p_reason text,
  p_expected_issue_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.decide_customer_issue(
    auth.uid(), p_issue_id, p_decision, p_refund_amount_paise,
    p_fault_source, p_return_package_count, p_reason,
    p_expected_issue_version, p_idempotency_key
  );
$$;

create function dastak_v1_api.assign_return_rider(
  p_actor_id uuid,
  p_return_mission_id uuid,
  p_rider_id uuid,
  p_expected_mission_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'assignReturnRider';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.return_missions%rowtype;
  v_return dastak_v1.returns%rowtype;
  v_delivery_method text;
  v_transport_type dastak_v1.transport_type;
  v_transport jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.recovery.manage');
  if p_return_mission_id is null or p_rider_id is null
    or p_expected_mission_version is null or p_expected_mission_version < 1
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid return assignment';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'returnMissionId', p_return_mission_id, 'riderId', p_rider_id,
    'expectedVersion', p_expected_mission_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-rider-active:' || p_rider_id::text, 0)
  );
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select mission.* into v_mission from dastak_v1.return_missions mission
  where mission.id = p_return_mission_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'return mission not found'; end if;
  select customer_return.* into v_return from dastak_v1.returns customer_return
  where customer_return.id = v_mission.return_id for update;
  if v_mission.version <> p_expected_mission_version
    or v_mission.status <> 'RIDER_SEARCH' or v_return.status <> 'RIDER_SEARCH' then
    raise exception using errcode = '40001', message = 'STALE_RETURN_MISSION_VERSION';
  end if;
  select profile.delivery_method into v_delivery_method
  from private.delivery_partner_profiles profile
  join private.account_memberships membership
    on membership.account_id = profile.account_id
   and membership.role = 'dastak_partner'
   and membership.approved_at is not null
   and (membership.suspended_until is null or membership.suspended_until <= v_now)
  join private.delivery_partner_availability availability
    on availability.account_id = profile.account_id
   and availability.status = 'online' and availability.available_until > v_now
  where profile.account_id = p_rider_id;
  v_transport_type := dastak_v1.rider_transport_type(v_delivery_method);
  v_transport := dastak_v1_api.order_transport_snapshot(v_mission.order_id);
  if v_transport_type is null or not (
    v_transport -> 'eligibleTransportTypes'
  ) @> pg_catalog.to_jsonb(array[v_transport_type::text]) then
    raise exception using errcode = '55000', message = 'RETURN_RIDER_TRANSPORT_INCAPABLE';
  end if;
  if exists (
    select 1 from dastak_v1.delivery_missions delivery_mission
    where delivery_mission.assigned_rider_id = p_rider_id
      and delivery_mission.status in (
        'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
        'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
        'DELIVERY_RECOVERY'
      )
      and delivery_mission.id is distinct from v_mission.source_delivery_mission_id
  ) or exists (
    select 1 from dastak_v1.return_missions other
    where other.assigned_rider_id = p_rider_id
      and other.status not in ('COMPLETED', 'CANCELLED')
      and other.id <> v_mission.id
  ) then
    raise exception using errcode = '23505', message = 'RIDER_ALREADY_HAS_ACTIVE_MISSION';
  end if;
  update dastak_v1.return_missions mission
  set status = 'ASSIGNED', assigned_rider_id = p_rider_id,
      assigned_transport_type = v_transport_type, assigned_at = v_now,
      version = mission.version + 1
  where mission.id = v_mission.id returning * into v_mission;
  update dastak_v1.return_verifications verification
  set status = 'ACTIVE', activated_at = v_now,
      version = verification.version + 1
  where verification.return_mission_id = v_mission.id
    and verification.handoff_type = 'CUSTOMER_TO_RETURN_RIDER'
    and verification.status = 'INACTIVE';
  update dastak_v1.returns customer_return
  set status = 'CUSTOMER_PICKUP', version = customer_return.version + 1
  where customer_return.id = v_return.id returning * into v_return;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_mission.id::text || ':RETURN_RIDER_ASSIGNED:' || v_mission.version::text,
    'RETURN_MISSION', v_mission.id, v_mission.version,
    'RETURN_RIDER_ASSIGNED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_mission.order_id, 'returnId', v_return.id,
      'returnMissionId', v_mission.id, 'riderId', p_rider_id,
      'transportType', v_transport_type
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'returnId', v_return.id, 'returnStatus', v_return.status,
    'returnMissionId', v_mission.id, 'missionStatus', v_mission.status,
    'riderId', p_rider_id, 'transportType', v_transport_type
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_mission.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_assign_return_rider(
  p_return_mission_id uuid,
  p_rider_id uuid,
  p_expected_mission_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.assign_return_rider(
    auth.uid(), p_return_mission_id, p_rider_id,
    p_expected_mission_version, p_idempotency_key
  );
$$;

create function dastak_v1_api.advance_return_mission(
  p_actor_id uuid,
  p_return_mission_id uuid,
  p_action text,
  p_return_stop_id uuid,
  p_object_path text,
  p_verification_code text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'advanceReturnMission';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.return_missions%rowtype;
  v_return dastak_v1.returns%rowtype;
  v_stop dastak_v1.return_stops%rowtype;
  v_verification dastak_v1.return_verifications%rowtype;
  v_issue dastak_v1.customer_issues%rowtype;
  v_delivery_case dastak_v1.recovery_cases%rowtype;
  v_delivery_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_from_order_status dastak_v1.order_status;
  v_evidence_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_attempt_limit integer;
  v_remaining integer;
  v_refund_id uuid;
  v_response jsonb;
begin
  if auth.uid() is not null then
    perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  end if;
  if p_return_mission_id is null or p_action not in (
    'ARRIVE_CUSTOMER', 'ADD_RETURN_EVIDENCE', 'VERIFY_RETURN_PICKUP',
    'ARRIVE_RETURN_STOP', 'VERIFY_RETURN_RECEIPT'
  ) or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or (p_action = 'ADD_RETURN_EVIDENCE' and (
      p_object_path is null or pg_catalog.split_part(p_object_path, '/', 1) <> 'return-pickup'
      or pg_catalog.split_part(p_object_path, '/', 2) <> p_actor_id::text
      or pg_catalog.array_length(pg_catalog.string_to_array(p_object_path, '/'), 1) <> 3
    ))
    or (p_action in ('VERIFY_RETURN_PICKUP', 'VERIFY_RETURN_RECEIPT')
      and (p_verification_code is null or p_verification_code !~ '^[0-9]{6}$'))
    or (p_action in ('ARRIVE_RETURN_STOP', 'VERIFY_RETURN_RECEIPT')
      and p_return_stop_id is null) then
    raise exception using errcode = '22023', message = 'invalid return mission action';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'returnMissionId', p_return_mission_id, 'action', p_action,
    'returnStopId', p_return_stop_id, 'objectPath', p_object_path,
    'verificationCode', p_verification_code
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select mission.* into v_mission from dastak_v1.return_missions mission
  where mission.id = p_return_mission_id for update;
  if not found or v_mission.assigned_rider_id is distinct from p_actor_id then
    raise exception using errcode = 'P0002', message = 'return mission not found';
  end if;
  select customer_return.* into v_return from dastak_v1.returns customer_return
  where customer_return.id = v_mission.return_id for update;
  perform 1 from dastak_v1.return_packages package
  where package.return_id = v_return.id order by package.id for update;
  if p_action = 'ARRIVE_CUSTOMER' then
    if v_mission.status <> 'ASSIGNED' or v_return.status <> 'CUSTOMER_PICKUP' then
      raise exception using errcode = '55000', message = 'RETURN_CUSTOMER_ARRIVAL_NOT_ALLOWED';
    end if;
    update dastak_v1.return_missions mission
    set status = 'AT_CUSTOMER', arrived_customer_at = v_now,
        version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
  elsif p_action = 'ADD_RETURN_EVIDENCE' then
    if v_mission.status <> 'AT_CUSTOMER' or exists (
      select 1 from dastak_v1.return_evidence evidence
      where evidence.object_path = p_object_path
    ) then
      raise exception using errcode = '55000', message = 'RETURN_EVIDENCE_NOT_ALLOWED';
    end if;
    insert into dastak_v1.return_evidence (
      return_id, return_mission_id, evidence_type, object_path,
      content_type, captured_by
    ) values (
      v_return.id, v_mission.id, 'RETURN_PICKUP_PHOTO', p_object_path,
      case
        when pg_catalog.lower(p_object_path) ~ '\\.png$' then 'image/png'
        when pg_catalog.lower(p_object_path) ~ '\\.heic$' then 'image/heic'
        else 'image/jpeg'
      end, p_actor_id
    ) returning id into v_evidence_id;
    insert into dastak_v1.return_evidence_packages (
      evidence_id, return_package_id, return_id
    ) select v_evidence_id, package.id, v_return.id
    from dastak_v1.return_packages package where package.return_id = v_return.id;
  elsif p_action = 'VERIFY_RETURN_PICKUP' then
    select verification.* into v_verification
    from dastak_v1.return_verifications verification
    where verification.return_mission_id = v_mission.id
      and verification.handoff_type = 'CUSTOMER_TO_RETURN_RIDER' for update;
    if v_mission.status <> 'AT_CUSTOMER' or v_return.status <> 'CUSTOMER_PICKUP'
      or v_verification.status <> 'ACTIVE' then
      raise exception using errcode = '55000', message = 'RETURN_PICKUP_VERIFICATION_INACTIVE';
    end if;
    if not exists (
      select 1 from dastak_v1.return_evidence evidence
      where evidence.return_mission_id = v_mission.id
        and (
          select count(*) from dastak_v1.return_evidence_packages link
          where link.evidence_id = evidence.id
        ) = (
          select count(*) from dastak_v1.return_packages package
          where package.return_id = v_return.id
        )
    ) then
      raise exception using errcode = '55000', message = 'RETURN_PICKUP_EVIDENCE_REQUIRED';
    end if;
    if v_verification.code_digest is distinct from
      private.dastak_v1_handoff_digest(p_verification_code) then
      v_attempt_limit := dastak_v1_api.delivery_verification_attempt_limit();
      update dastak_v1.return_verifications verification
      set failed_attempts = verification.failed_attempts + 1,
          status = case when verification.failed_attempts + 1 >= v_attempt_limit
            then 'BLOCKED' else verification.status end,
          blocked_at = case when verification.failed_attempts + 1 >= v_attempt_limit
            then v_now else null end,
          version = verification.version + 1
      where verification.id = v_verification.id
      returning * into v_verification;
      insert into dastak_v1.audit_events (
        actor_id, action, resource_type, resource_id, metadata
      ) values (
        p_actor_id, 'RETURN_PICKUP_CODE_REJECTED',
        'return_verification', v_verification.id,
        pg_catalog.jsonb_build_object(
          'returnId', v_return.id, 'returnMissionId', v_mission.id,
          'failedAttempts', v_verification.failed_attempts,
          'blocked', v_verification.status = 'BLOCKED'
        )
      );
      v_response := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', case when v_verification.status = 'BLOCKED'
            then 'return_pickup_code_blocked' else 'return_pickup_code_invalid' end,
          'message', case when v_verification.status = 'BLOCKED'
            then 'Normal verification is blocked. Report the problem to Operations.'
            else 'The return pickup code is incorrect.' end
        )
      );
      insert into dastak_v1.idempotency_records (
        actor_id, command_name, idempotency_key, request_hash,
        response_body, response_status, resource_id
      ) values (
        p_actor_id, v_command, p_idempotency_key, v_hash,
        v_response, 409, v_mission.id
      );
      return v_response;
    end if;
    update dastak_v1.return_verifications verification
    set status = 'CONSUMED', consumed_at = v_now, consumed_by = p_actor_id,
        version = verification.version + 1
    where verification.id = v_verification.id returning * into v_verification;
    perform pg_catalog.set_config(
      'dastak_v1.return_verification_id', v_verification.id::text, true
    );
    update dastak_v1.return_packages package
    set status = 'RETURN_RIDER_CUSTODY',
        current_custody_owner_type = 'RETURN_RIDER',
        current_custody_owner_id = p_actor_id,
        picked_up_at = v_now, version = package.version + 1
    where package.return_id = v_return.id and package.status = 'CUSTOMER_READY';
    insert into dastak_v1.return_custody_events (
      return_id, return_mission_id, return_package_id, verification_id,
      from_owner_type, from_owner_id, to_owner_type, to_owner_id,
      transferred_by, transferred_at
    ) select
      v_return.id, v_mission.id, package.id, v_verification.id,
      'CUSTOMER', v_return.requested_by, 'RETURN_RIDER', p_actor_id,
      p_actor_id, v_now
    from dastak_v1.return_packages package where package.return_id = v_return.id;
    update dastak_v1.return_verifications verification
    set status = 'ACTIVE', activated_at = v_now,
        version = verification.version + 1
    where verification.return_mission_id = v_mission.id
      and verification.handoff_type = 'RETURN_RIDER_TO_MERCHANT'
      and verification.status = 'INACTIVE';
    update dastak_v1.return_missions mission
    set status = 'RETURNING_TO_MERCHANTS', pickup_completed_at = v_now,
        version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
    update dastak_v1.returns customer_return
    set status = 'IN_RIDER_CUSTODY', version = customer_return.version + 1
    where customer_return.id = v_return.id returning * into v_return;
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_return.id::text || ':RETURN_PICKUP_VERIFIED:' || v_return.version::text,
      'RETURN', v_return.id, v_return.version,
      'RETURN_PICKUP_VERIFIED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_return.order_id, 'returnId', v_return.id,
        'returnMissionId', v_mission.id,
        'packageCount', (select count(*) from dastak_v1.return_packages package
          where package.return_id = v_return.id)
      )
    );
  elsif p_action = 'ARRIVE_RETURN_STOP' then
    select stop.* into v_stop from dastak_v1.return_stops stop
    where stop.id = p_return_stop_id and stop.return_mission_id = v_mission.id for update;
    if not found or v_mission.status <> 'RETURNING_TO_MERCHANTS'
      or v_stop.status <> 'PENDING' then
      raise exception using errcode = '55000', message = 'RETURN_STOP_ARRIVAL_NOT_ALLOWED';
    end if;
    update dastak_v1.return_stops stop
    set status = 'ARRIVED', arrived_at = v_now, version = stop.version + 1
    where stop.id = v_stop.id returning * into v_stop;
  elsif p_action = 'VERIFY_RETURN_RECEIPT' then
    select stop.* into v_stop from dastak_v1.return_stops stop
    where stop.id = p_return_stop_id and stop.return_mission_id = v_mission.id for update;
    select verification.* into v_verification
    from dastak_v1.return_verifications verification
    where verification.return_stop_id = v_stop.id
      and verification.handoff_type = 'RETURN_RIDER_TO_MERCHANT' for update;
    if v_mission.status <> 'RETURNING_TO_MERCHANTS'
      or v_stop.status <> 'ARRIVED' or v_verification.status <> 'ACTIVE' then
      raise exception using errcode = '55000', message = 'RETURN_RECEIPT_VERIFICATION_INACTIVE';
    end if;
    if v_verification.code_digest is distinct from
      private.dastak_v1_handoff_digest(p_verification_code) then
      v_attempt_limit := dastak_v1_api.delivery_verification_attempt_limit();
      update dastak_v1.return_verifications verification
      set failed_attempts = verification.failed_attempts + 1,
          status = case when verification.failed_attempts + 1 >= v_attempt_limit
            then 'BLOCKED' else verification.status end,
          blocked_at = case when verification.failed_attempts + 1 >= v_attempt_limit
            then v_now else null end,
          version = verification.version + 1
      where verification.id = v_verification.id
      returning * into v_verification;
      insert into dastak_v1.audit_events (
        actor_id, action, resource_type, resource_id, metadata
      ) values (
        p_actor_id, 'RETURN_RECEIPT_CODE_REJECTED',
        'return_verification', v_verification.id,
        pg_catalog.jsonb_build_object(
          'returnId', v_return.id, 'returnMissionId', v_mission.id,
          'returnStopId', v_stop.id,
          'failedAttempts', v_verification.failed_attempts,
          'blocked', v_verification.status = 'BLOCKED'
        )
      );
      v_response := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', case when v_verification.status = 'BLOCKED'
            then 'return_receipt_code_blocked' else 'return_receipt_code_invalid' end,
          'message', case when v_verification.status = 'BLOCKED'
            then 'Normal verification is blocked. Report the problem to Operations.'
            else 'The merchant receipt code is incorrect.' end
        )
      );
      insert into dastak_v1.idempotency_records (
        actor_id, command_name, idempotency_key, request_hash,
        response_body, response_status, resource_id
      ) values (
        p_actor_id, v_command, p_idempotency_key, v_hash,
        v_response, 409, v_mission.id
      );
      return v_response;
    end if;
    update dastak_v1.return_verifications verification
    set status = 'CONSUMED', consumed_at = v_now, consumed_by = p_actor_id,
        version = verification.version + 1
    where verification.id = v_verification.id returning * into v_verification;
    perform pg_catalog.set_config(
      'dastak_v1.return_verification_id', v_verification.id::text, true
    );
    update dastak_v1.return_packages package
    set status = 'MERCHANT_RETURN_CUSTODY',
        current_custody_owner_type = 'MERCHANT_RETURN',
        current_custody_owner_id = v_stop.branch_id,
        returned_at = v_now, version = package.version + 1
    where package.return_id = v_return.id
      and package.destination_branch_id = v_stop.branch_id
      and package.status = 'RETURN_RIDER_CUSTODY';
    update dastak_v1.packages package
    set status = 'RETURNED',
        current_custody_owner_type = 'MERCHANT_RETURN',
        current_custody_owner_id = v_stop.branch_id,
        version = package.version + 1
    from dastak_v1.return_packages return_package
    where v_return.source = 'DELIVERY_RECOVERY'
      and return_package.return_id = v_return.id
      and return_package.destination_branch_id = v_stop.branch_id
      and return_package.source_delivery_package_id = package.id
      and package.status = 'RECOVERY';
    insert into dastak_v1.return_custody_events (
      return_id, return_mission_id, return_package_id, verification_id,
      from_owner_type, from_owner_id, to_owner_type, to_owner_id,
      transferred_by, transferred_at
    ) select
      v_return.id, v_mission.id, package.id, v_verification.id,
      'RETURN_RIDER', p_actor_id, 'MERCHANT_RETURN', v_stop.branch_id,
      p_actor_id, v_now
    from dastak_v1.return_packages package
    where package.return_id = v_return.id
      and package.destination_branch_id = v_stop.branch_id;
    update dastak_v1.return_stops stop
    set status = 'COMPLETED', completed_at = v_now,
        version = stop.version + 1
    where stop.id = v_stop.id returning * into v_stop;
    select count(*) into v_remaining from dastak_v1.return_stops stop
    where stop.return_mission_id = v_mission.id and stop.status <> 'COMPLETED';
    if v_remaining = 0 then
      update dastak_v1.return_missions mission
      set status = 'COMPLETED', completed_at = v_now,
          version = mission.version + 1
      where mission.id = v_mission.id returning * into v_mission;
      update dastak_v1.returns customer_return
      set status = 'RETURNED_TO_ORIGINAL_MERCHANT',
          version = customer_return.version + 1
      where customer_return.id = v_return.id returning * into v_return;
      if v_return.source = 'CUSTOMER_ISSUE' then
        select issue.* into v_issue from dastak_v1.customer_issues issue
        where issue.id = v_return.customer_issue_id for update;
        v_refund_id := dastak_v1_api.create_approved_refund(
          v_return.decided_by, v_return.order_id,
          (select line.order_line_id from dastak_v1.return_lines line
            where line.return_id = v_return.id order by line.order_line_id limit 1),
          null, v_issue.id, v_return.id,
          v_return.approved_refund_amount_paise,
          v_return.refund_fault_source,
          v_return.reason, 'AUTHORIZED_OPERATIONS'
        );
        update dastak_v1.customer_issues issue
        set status = 'RESOLVED', resolution = v_return.reason,
            resolved_at = v_now, version = issue.version + 1
        where issue.id = v_issue.id returning * into v_issue;
      else
        select recovery.* into v_delivery_case
        from dastak_v1.recovery_cases recovery
        where recovery.id = v_return.delivery_recovery_case_id for update;
        select delivery_mission.* into v_delivery_mission
        from dastak_v1.delivery_missions delivery_mission
        where delivery_mission.id = v_delivery_case.delivery_mission_id for update;
        select customer_order.* into v_order
        from dastak_v1.orders customer_order
        where customer_order.id = v_return.order_id for update;
        v_from_order_status := v_order.status;
        update dastak_v1.delivery_missions delivery_mission
        set status = 'RECOVERED_RETURNED', version = delivery_mission.version + 1
        where delivery_mission.id = v_delivery_mission.id
        returning * into v_delivery_mission;
        update dastak_v1.orders customer_order
        set status = 'DASTAK_FULFILMENT_FAILURE',
            version = customer_order.version + 1
        where customer_order.id = v_order.id returning * into v_order;
        insert into dastak_v1.order_state_journal (
          order_id, from_status, to_status, order_version,
          command_name, actor_id, reason, metadata
        ) values (
          v_order.id, v_from_order_status, 'DASTAK_FULFILMENT_FAILURE',
          v_order.version, 'completeDeliveryRecoveryReturn',
          v_return.decided_by, v_return.reason,
          pg_catalog.jsonb_build_object(
            'recoveryCaseId', v_delivery_case.id,
            'returnId', v_return.id,
            'returnMissionId', v_mission.id,
            'allPackagesReturned', true
          )
        );
        update dastak_v1.recovery_cases recovery
        set status = 'RESOLVED',
            fault_source = v_return.delivery_recovery_fault_source,
            resolution = v_return.reason, resolved_by = v_return.decided_by,
            resolved_at = v_now, version = recovery.version + 1
        where recovery.id = v_delivery_case.id returning * into v_delivery_case;
        if v_delivery_case.fault_source <> 'MERCHANT' then
          perform dastak_v1_api.mark_order_settlements_eligible(
            v_order.id, v_return.decided_by,
            'Approved equivalent completion protected correctly fulfilling merchant earnings.',
            false
          );
        end if;
        if v_return.approved_refund_amount_paise is not null then
          v_refund_id := dastak_v1_api.create_approved_refund(
            v_return.decided_by, v_return.order_id, null,
            v_delivery_case.id, null, v_return.id,
            v_return.approved_refund_amount_paise,
            v_return.refund_fault_source, v_return.reason,
            'AUTHORIZED_OPERATIONS'
          );
        end if;
      end if;
      update dastak_v1.returns customer_return
      set status = 'COMPLETED', completed_at = v_now,
          version = customer_return.version + 1
      where customer_return.id = v_return.id returning * into v_return;
      insert into dastak_v1.domain_events_outbox (
        event_key, aggregate_type, aggregate_id, aggregate_version,
        event_type, actor_id, payload
      ) values (
        v_return.id::text || ':RETURN_RECEIPT_VERIFIED:' || v_return.version::text,
        'RETURN', v_return.id, v_return.version,
        'RETURN_RECEIPT_VERIFIED', p_actor_id,
        pg_catalog.jsonb_build_object(
          'orderId', v_return.order_id, 'returnId', v_return.id,
          'returnMissionId', v_mission.id, 'refundId', v_refund_id,
          'allPackagesInMerchantCustody', true
        )
      );
    end if;
  end if;
  v_response := pg_catalog.jsonb_build_object(
    'returnId', v_return.id, 'returnStatus', v_return.status,
    'returnMissionId', v_mission.id, 'missionStatus', v_mission.status,
    'returnStopId', v_stop.id, 'returnStopStatus', v_stop.status,
    'evidenceId', v_evidence_id, 'refundId', v_refund_id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_mission.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_advance_return_mission(
  p_return_mission_id uuid,
  p_action text,
  p_return_stop_id uuid,
  p_object_path text,
  p_verification_code text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.advance_return_mission(
    auth.uid(), p_return_mission_id, p_action, p_return_stop_id,
    p_object_path, p_verification_code, p_idempotency_key
  );
$$;

create function dastak_v1.open_delivery_recovery_case()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem dastak_v1.delivery_problem_reports%rowtype;
  v_case_id uuid;
begin
  if old.status is distinct from 'DELIVERY_RECOVERY'
    and new.status = 'DELIVERY_RECOVERY' then
    select problem.* into v_problem
    from dastak_v1.delivery_problem_reports problem
    where problem.mission_id = new.id
    order by problem.reported_at desc, problem.id desc limit 1;
    insert into dastak_v1.recovery_cases (
      case_type, order_id, delivery_mission_id, status,
      fault_source, reason, opened_by, opened_at
    ) values (
      'DELIVERY', new.order_id, new.id, 'ACTION_REQUIRED',
      'UNKNOWN', coalesce(v_problem.reason, 'Delivery recovery requires Operations.'),
      coalesce(v_problem.reported_by, new.assigned_rider_id),
      coalesce(v_problem.reported_at, pg_catalog.clock_timestamp())
    ) on conflict do nothing returning id into v_case_id;
    if v_case_id is not null then
      insert into dastak_v1.domain_events_outbox (
        event_key, aggregate_type, aggregate_id, aggregate_version,
        event_type, actor_id, payload
      ) values (
        v_case_id::text || ':DELIVERY_RECOVERY_STARTED:1',
        'RECOVERY_CASE', v_case_id, 1, 'DELIVERY_RECOVERY_STARTED',
        coalesce(v_problem.reported_by, new.assigned_rider_id),
        pg_catalog.jsonb_build_object(
          'orderId', new.order_id, 'missionId', new.id,
          'recoveryCaseId', v_case_id, 'custodyRetainedByRider', true
        )
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger delivery_missions_open_recovery_case
after update on dastak_v1.delivery_missions
for each row execute function dastak_v1.open_delivery_recovery_case();

create function dastak_v1_api.manage_delivery_recovery(
  p_actor_id uuid,
  p_recovery_case_id uuid,
  p_action text,
  p_fault_source text,
  p_refund_amount_paise bigint,
  p_corrected_address jsonb,
  p_reason text,
  p_expected_case_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'manageDeliveryRecovery';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_case dastak_v1.recovery_cases%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_fault dastak_v1.recovery_fault_source;
  v_refund_fault dastak_v1.refund_fault_source;
  v_target_status dastak_v1.delivery_mission_status;
  v_limit integer;
  v_return dastak_v1.returns%rowtype;
  v_return_mission dastak_v1.return_missions%rowtype;
  v_stop record;
  v_verification_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.recovery.manage');
  begin v_fault := p_fault_source::dastak_v1.recovery_fault_source;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid recovery fault source';
  end;
  if p_recovery_case_id is null or p_action not in ('RESUME_DELIVERY', 'RETURN_TO_ORIGIN')
    or v_fault = 'UNKNOWN' or p_expected_case_version is null
    or nullif(pg_catalog.btrim(p_reason), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 10 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or (p_action = 'RETURN_TO_ORIGIN' and p_corrected_address is not null)
    or (p_action = 'RESUME_DELIVERY' and p_refund_amount_paise is not null)
    or (p_corrected_address is not null
      and pg_catalog.jsonb_typeof(p_corrected_address) <> 'object') then
    raise exception using errcode = '22023', message = 'invalid delivery recovery action';
  end if;
  if p_refund_amount_paise is not null then
    perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.refunds.approve');
    if v_fault = 'CUSTOMER' or p_refund_amount_paise <= 0 then
      raise exception using errcode = '22023', message = 'customer-caused recovery has no automatic refund';
    end if;
    v_limit := dastak_v1_api.required_setting_integer('refunds.approval_limit_paise');
    if p_refund_amount_paise > v_limit then
      raise exception using errcode = '42501', message = 'REFUND_APPROVAL_LIMIT_EXCEEDED';
    end if;
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'recoveryCaseId', p_recovery_case_id, 'action', p_action,
    'faultSource', v_fault, 'refundAmountPaise', p_refund_amount_paise,
    'correctedAddress', p_corrected_address,
    'reason', pg_catalog.btrim(p_reason), 'expectedVersion', p_expected_case_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select recovery.* into v_case from dastak_v1.recovery_cases recovery
  where recovery.id = p_recovery_case_id for update;
  if not found or v_case.case_type <> 'DELIVERY' then
    raise exception using errcode = 'P0002', message = 'delivery recovery not found';
  end if;
  select mission.* into v_mission from dastak_v1.delivery_missions mission
  where mission.id = v_case.delivery_mission_id for update;
  select customer_order.* into v_order from dastak_v1.orders customer_order
  where customer_order.id = v_case.order_id for update;
  perform 1 from dastak_v1.packages package
  where package.order_id = v_order.id order by package.id for update;
  if v_case.version <> p_expected_case_version
    or v_case.status <> 'ACTION_REQUIRED' or v_mission.status <> 'DELIVERY_RECOVERY'
    or v_mission.assigned_rider_id is null then
    raise exception using errcode = '40001', message = 'STALE_DELIVERY_RECOVERY_VERSION';
  end if;
  if exists (
    select 1 from dastak_v1.packages package
    where package.order_id = v_order.id and (
      package.current_custody_owner_type <> 'RIDER'
      or package.current_custody_owner_id <> v_mission.assigned_rider_id
    )
  ) then
    raise exception using errcode = '55000', message = 'RIDER_CUSTODY_INCOMPLETE';
  end if;
  if p_action = 'RESUME_DELIVERY' then
    if p_corrected_address is not null then
      insert into dastak_v1.delivery_address_exceptions (
        recovery_case_id, order_id, corrected_address, correction_kind,
        authorized_by, reason
      ) values (
        v_case.id, v_order.id, p_corrected_address, 'MINOR_CORRECTION',
        p_actor_id, pg_catalog.btrim(p_reason)
      );
    end if;
    v_target_status := case
      when v_mission.arrived_customer_at is not null
        then 'ARRIVED'::dastak_v1.delivery_mission_status
      when v_mission.out_for_delivery_at is not null
        then 'OUT_FOR_DELIVERY'::dastak_v1.delivery_mission_status
      when v_mission.all_packages_picked_up_at is not null
        then 'ALL_PACKAGES_PICKED_UP'::dastak_v1.delivery_mission_status
      else 'PICKUP_IN_PROGRESS'::dastak_v1.delivery_mission_status
    end;
    update dastak_v1.delivery_missions mission
    set status = v_target_status, version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
    update dastak_v1.recovery_cases recovery
    set status = 'RESOLVED', fault_source = v_fault,
        resolution = pg_catalog.btrim(p_reason), resolved_by = p_actor_id,
        resolved_at = v_now, version = recovery.version + 1
    where recovery.id = v_case.id returning * into v_case;
  else
    if exists (
      select 1
      from dastak_v1.packages package
      join dastak_v1.fulfilments fulfilment on fulfilment.id = package.fulfilment_id
      join dastak_v1.merchant_organizations organization
        on organization.id = fulfilment.organization_id
      where package.order_id = v_order.id
        and organization.merchant_type = 'RESTAURANT_CAFE'
    ) then
      raise exception using errcode = '55000', message = 'PREPARED_FOOD_PHYSICAL_RETURN_FORBIDDEN';
    end if;
    v_refund_fault := v_fault::text::dastak_v1.refund_fault_source;
    insert into dastak_v1.returns (
      order_id, source, delivery_recovery_case_id, status,
      physical_return_required, approved_refund_amount_paise,
      refund_fault_source, delivery_recovery_fault_source,
      reason, requested_by, requested_at,
      decided_by, decided_at
    ) values (
      v_order.id, 'DELIVERY_RECOVERY', v_case.id, 'RETURN_REQUIRED', true,
      p_refund_amount_paise,
      case when p_refund_amount_paise is null then null else v_refund_fault end,
      v_fault, pg_catalog.btrim(p_reason), p_actor_id, v_now, p_actor_id, v_now
    ) returning * into v_return;
    insert into dastak_v1.return_lines (
      return_id, order_line_id, quantity, reason
    ) select v_return.id, line.id, line.quantity, pg_catalog.btrim(p_reason)
    from dastak_v1.order_lines line
    where line.order_id = v_order.id and line.status <> 'REFUNDED';
    insert into dastak_v1.return_packages (
      return_id, order_id, package_number, destination_branch_id,
      source_delivery_package_id, status, current_custody_owner_type,
      current_custody_owner_id, created_by, picked_up_at
    ) select
      v_return.id, v_order.id,
      row_number() over (order by package.id)::integer,
      fulfilment.branch_id, package.id, 'RETURN_RIDER_CUSTODY',
      'RETURN_RIDER', v_mission.assigned_rider_id, p_actor_id, v_now
    from dastak_v1.packages package
    join dastak_v1.fulfilments fulfilment on fulfilment.id = package.fulfilment_id
    where package.order_id = v_order.id order by package.id;
    insert into dastak_v1.return_missions (
      return_id, order_id, status, assigned_rider_id,
      assigned_transport_type, source_delivery_mission_id,
      assigned_at, pickup_completed_at
    ) values (
      v_return.id, v_order.id, 'RETURNING_TO_MERCHANTS',
      v_mission.assigned_rider_id, v_mission.assigned_transport_type,
      v_mission.id, v_mission.assigned_at, v_now
    ) returning * into v_return_mission;
    for v_stop in
      insert into dastak_v1.return_stops (
        return_mission_id, return_id, branch_id, stop_sequence,
        status, package_count
      )
      select
        v_return_mission.id, v_return.id, package.destination_branch_id,
        row_number() over (order by package.destination_branch_id)::integer,
        'PENDING', count(*)::integer
      from dastak_v1.return_packages package
      where package.return_id = v_return.id
      group by package.destination_branch_id
      order by package.destination_branch_id
      returning *
    loop
      v_verification_id := gen_random_uuid();
      insert into dastak_v1.return_verifications (
        id, return_id, return_mission_id, return_stop_id,
        handoff_type, status, code_digest, activated_at
      ) values (
        v_verification_id, v_return.id, v_return_mission.id, v_stop.id,
        'RETURN_RIDER_TO_MERCHANT', 'ACTIVE',
        private.dastak_v1_handoff_digest(private.dastak_v1_handoff_code(
          v_verification_id, 'RETURN_RIDER_TO_MERCHANT', 1
        )), v_now
      );
    end loop;
    update dastak_v1.packages package
    set status = 'RECOVERY', version = package.version + 1
    where package.order_id = v_order.id
      and package.status in ('PICKED_UP', 'IN_TRANSIT');
    update dastak_v1.returns customer_return
    set status = 'IN_RIDER_CUSTODY', version = customer_return.version + 1
    where customer_return.id = v_return.id returning * into v_return;
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_return.id::text || ':DELIVERY_RECOVERY_RETURN_DIRECTED:' || v_return.version::text,
      'RETURN', v_return.id, v_return.version,
      'DELIVERY_RECOVERY_RETURN_DIRECTED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id, 'recoveryCaseId', v_case.id,
        'returnId', v_return.id, 'returnMissionId', v_return_mission.id,
        'riderId', v_mission.assigned_rider_id,
        'refundAmountPaise', p_refund_amount_paise,
        'refundAutomatic', false
      )
    );
  end if;
  v_response := pg_catalog.jsonb_build_object(
    'recoveryCaseId', v_case.id, 'recoveryStatus', v_case.status,
    'deliveryMissionId', v_mission.id, 'missionStatus', v_mission.status,
    'returnId', v_return.id, 'returnStatus', v_return.status,
    'returnMissionId', v_return_mission.id, 'action', p_action
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_case.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_manage_delivery_recovery(
  p_recovery_case_id uuid,
  p_action text,
  p_fault_source text,
  p_refund_amount_paise bigint,
  p_corrected_address jsonb,
  p_reason text,
  p_expected_case_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.manage_delivery_recovery(
    auth.uid(), p_recovery_case_id, p_action, p_fault_source,
    p_refund_amount_paise, p_corrected_address, p_reason,
    p_expected_case_version, p_idempotency_key
  );
$$;

create function dastak_v1_api.prepare_razorpay_refund(
  p_actor_id uuid,
  p_refund_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refund dastak_v1.refunds%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if not dastak_v1_api.actor_has_platform_permission(
    p_actor_id, 'platform.refunds.process'
  ) then
    raise exception using errcode = '42501', message = 'platform permission required';
  end if;
  if p_refund_id is null or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid refund processing request';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-refund:' || p_refund_id::text, 0)
  );
  select refund.* into v_refund from dastak_v1.refunds refund
  where refund.id = p_refund_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'refund not found'; end if;
  if v_refund.status = 'COMPLETED' then
    return pg_catalog.jsonb_build_object(
      'refundId', v_refund.id, 'orderId', v_refund.order_id,
      'refundState', 'processed',
      'providerPaymentId', v_refund.provider_payment_reference,
      'providerRefundId', v_refund.provider_refund_reference,
      'amountPaise', v_refund.amount_paise, 'currency', v_refund.currency_code,
      'receipt', v_refund.provider_receipt
    );
  end if;
  if v_refund.status not in ('APPROVED', 'PROCESSING', 'FAILED') then
    raise exception using errcode = '55000', message = 'REFUND_NOT_APPROVED';
  end if;
  if v_refund.return_id is not null and exists (
    select 1 from dastak_v1.returns customer_return
    where customer_return.id = v_refund.return_id
      and customer_return.physical_return_required
      and customer_return.status <> 'COMPLETED'
  ) then
    raise exception using errcode = '55000', message = 'PHYSICAL_RETURN_NOT_COMPLETED';
  end if;
  if v_refund.status in ('APPROVED', 'FAILED') then
    update dastak_v1.refunds refund
    set status = 'PROCESSING', processing_started_at = v_now,
        failed_at = null, failure_code = null,
        version = refund.version + 1
    where refund.id = v_refund.id returning * into v_refund;
  end if;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'REFUND_PROCESSING_STARTED', 'refund', v_refund.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_refund.order_id, 'amountPaise', v_refund.amount_paise,
      'destination', v_refund.destination, 'idempotencyKey', p_idempotency_key
    )
  );
  return pg_catalog.jsonb_build_object(
    'refundId', v_refund.id, 'orderId', v_refund.order_id,
    'refundState', 'pending',
    'providerPaymentId', v_refund.provider_payment_reference,
    'providerRefundId', v_refund.provider_refund_reference,
    'amountPaise', v_refund.amount_paise, 'currency', v_refund.currency_code,
    'receipt', v_refund.provider_receipt
  );
end;
$$;

create function public.dastak_v1_prepare_razorpay_refund(
  p_account_id uuid,
  p_refund_id uuid,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.prepare_razorpay_refund(
    p_account_id, p_refund_id, p_idempotency_key
  );
$$;

create function dastak_v1_api.attach_razorpay_refund(
  p_actor_id uuid,
  p_refund_id uuid,
  p_provider_refund_reference text,
  p_amount_paise bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refund dastak_v1.refunds%rowtype;
begin
  if not dastak_v1_api.actor_has_platform_permission(
    p_actor_id, 'platform.refunds.process'
  ) then
    raise exception using errcode = '42501', message = 'platform permission required';
  end if;
  if p_provider_refund_reference !~ '^rfnd_[A-Za-z0-9]+$'
    or p_amount_paise is null or p_amount_paise <= 0 then
    raise exception using errcode = '22023', message = 'invalid provider refund';
  end if;
  select refund.* into v_refund from dastak_v1.refunds refund
  where refund.id = p_refund_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'refund not found'; end if;
  if v_refund.amount_paise <> p_amount_paise or v_refund.status <> 'PROCESSING' then
    raise exception using errcode = '55000', message = 'REFUND_PROVIDER_MISMATCH';
  end if;
  if v_refund.provider_refund_reference is not null
    and v_refund.provider_refund_reference <> p_provider_refund_reference then
    raise exception using errcode = '23505', message = 'REFUND_PROVIDER_REFERENCE_CONFLICT';
  end if;
  if v_refund.provider_refund_reference is null then
    update dastak_v1.refunds refund
    set provider_refund_reference = p_provider_refund_reference,
        version = refund.version + 1
    where refund.id = v_refund.id returning * into v_refund;
  end if;
  return pg_catalog.jsonb_build_object(
    'refundId', v_refund.id, 'orderId', v_refund.order_id,
    'refundState', 'pending', 'providerRefundId', v_refund.provider_refund_reference,
    'amountPaise', v_refund.amount_paise, 'currency', v_refund.currency_code
  );
end;
$$;

create function public.dastak_v1_attach_razorpay_refund(
  p_account_id uuid,
  p_refund_id uuid,
  p_provider_refund_reference text,
  p_amount_paise bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.attach_razorpay_refund(
    p_account_id, p_refund_id, p_provider_refund_reference, p_amount_paise
  );
$$;

create function dastak_v1_api.record_razorpay_refund_event(
  p_provider_event_id text,
  p_provider_payment_reference text,
  p_provider_refund_reference text,
  p_amount_paise bigint,
  p_occurred_at timestamptz,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing dastak_v1.refund_provider_events%rowtype;
  v_refund dastak_v1.refunds%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'RAZORPAY:REFUND:' || p_provider_event_id, 0
  ));
  select event.* into v_existing from dastak_v1.refund_provider_events event
  where event.provider = 'RAZORPAY' and event.provider_event_id = p_provider_event_id;
  if found then
    if v_existing.request_digest <> p_request_digest then
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'provider_event_conflict', 'message', 'Provider event payload changed.'
      )); response_status := 409; return next; return;
    end if;
    response_body := v_existing.response_body;
    response_status := 200; return next; return;
  end if;
  select refund.* into v_refund from dastak_v1.refunds refund
  where refund.provider_refund_reference = p_provider_refund_reference for update;
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'payment_not_found', 'message', 'The event does not belong to a Dastak V1 refund.'
    )); response_status := 404; return next; return;
  end if;
  if v_refund.provider_payment_reference <> p_provider_payment_reference
    or v_refund.amount_paise <> p_amount_paise then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'refund_provider_mismatch', 'message', 'Refund amount or payment reference differs.'
    )); response_status := 409; return next; return;
  end if;
  if v_refund.status = 'PROCESSING' then
    update dastak_v1.refunds refund
    set status = 'COMPLETED', completed_at = v_now,
        version = refund.version + 1
    where refund.id = v_refund.id returning * into v_refund;
  elsif v_refund.status <> 'COMPLETED' then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'invalid_refund_state', 'message', 'Refund is not processing.'
    )); response_status := 409; return next; return;
  end if;
  response_body := pg_catalog.jsonb_build_object(
    'refundId', v_refund.id, 'orderId', v_refund.order_id,
    'refundState', 'processed', 'amountPaise', v_refund.amount_paise,
    'providerRefundId', v_refund.provider_refund_reference
  );
  insert into dastak_v1.refund_provider_events (
    provider_event_id, refund_id, order_id,
    provider_payment_reference, provider_refund_reference,
    amount_paise, occurred_at, request_digest, outcome, response_body
  ) values (
    p_provider_event_id, v_refund.id, v_refund.order_id,
    p_provider_payment_reference, p_provider_refund_reference,
    p_amount_paise, p_occurred_at, p_request_digest, 'COMPLETED', response_body
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_refund.id::text || ':REFUND_COMPLETED:' || v_refund.version::text,
    'REFUND', v_refund.id, v_refund.version, 'REFUND_COMPLETED',
    pg_catalog.jsonb_build_object(
      'orderId', v_refund.order_id, 'refundId', v_refund.id,
      'amountPaise', v_refund.amount_paise,
      'providerRefundId', v_refund.provider_refund_reference
    )
  );
  response_status := 200; return next;
end;
$$;

create or replace function public.dastak_v1_record_razorpay_event(
  p_provider_event_id text,
  p_event_type text,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_provider_refund_reference text,
  p_amount_paise bigint,
  p_occurred_at timestamptz,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_event_type = 'payment_captured' and p_provider_refund_reference is null then
    return query select * from dastak_v1_api.record_razorpay_payment_event(
      p_provider_event_id, p_event_type, p_provider_order_reference,
      p_provider_payment_reference, p_amount_paise, p_occurred_at,
      p_request_digest
    );
    return;
  elsif p_event_type = 'refund_succeeded' and p_provider_refund_reference is not null then
    return query select * from dastak_v1_api.record_razorpay_refund_event(
      p_provider_event_id, p_provider_payment_reference,
      p_provider_refund_reference, p_amount_paise,
      p_occurred_at, p_request_digest
    );
    return;
  end if;
  return query select
    pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'payment_not_found',
      'message', 'The event does not belong to a Dastak V1 payment or refund.'
    )), 404;
end;
$$;

create function dastak_v1_api.create_exact_recovery_settlement_debit(
  p_recovery_case_id uuid,
  p_replacement_fulfilment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case dastak_v1.recovery_cases%rowtype;
  v_earning dastak_v1.settlement_entries%rowtype;
  v_id uuid;
begin
  select recovery.* into v_case from dastak_v1.recovery_cases recovery
  where recovery.id = p_recovery_case_id;
  select entry.* into v_earning from dastak_v1.settlement_entries entry
  where entry.fulfilment_id = v_case.source_fulfilment_id
    and entry.order_line_id = v_case.order_line_id
    and entry.entry_type = 'EARNING'
  order by entry.created_at limit 1;
  if not found or (v_earning.amount_paise is not null and v_earning.amount_paise = 0) then
    return null;
  end if;
  insert into dastak_v1.settlement_entries (
    entry_key, subject_type, subject_id, order_id, fulfilment_id,
    order_line_id, entry_type, status, calculation_status,
    gross_amount_paise, amount_paise, calculation_snapshot
  ) values (
    v_case.order_id::text || ':RECOVERY_DEBIT:' || v_case.id::text,
    v_earning.subject_type, v_earning.subject_id, v_case.order_id,
    v_earning.fulfilment_id, v_case.order_line_id,
    'DEBIT_ADJUSTMENT', 'PENDING', v_earning.calculation_status,
    v_earning.gross_amount_paise,
    case when v_earning.amount_paise is null then null else -v_earning.amount_paise end,
    pg_catalog.jsonb_build_object(
      'reason', 'MERCHANT_EXACT_SKU_RECOVERY',
      'recoveryCaseId', v_case.id,
      'originalEarningEntryId', v_earning.id,
      'replacementFulfilmentId', p_replacement_fulfilment_id,
      'historicalEarningPreserved', true
    )
  ) on conflict (entry_key) do nothing returning id into v_id;
  return v_id;
end;
$$;

create function dastak_v1_api.mark_order_settlements_eligible(
  p_order_id uuid,
  p_actor_id uuid,
  p_reason text,
  p_include_rider boolean default true
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  perform pg_catalog.set_config(
    'dastak_v1.settlement_actor_id', coalesce(p_actor_id::text, ''), true
  );
  perform pg_catalog.set_config('dastak_v1.settlement_reason', p_reason, true);
  update dastak_v1.settlement_entries entry
  set status = 'ELIGIBLE', eligible_at = pg_catalog.clock_timestamp(),
      version = entry.version + 1
  where entry.order_id = p_order_id
    and entry.status = 'PENDING'
    and entry.calculation_status = 'CALCULATED'
    and (entry.subject_type = 'MERCHANT_ORGANIZATION' or p_include_rider)
    and (entry.refund_id is null or exists (
      select 1 from dastak_v1.refunds refund
      where refund.id = entry.refund_id and refund.status = 'COMPLETED'
    ))
    and (
      entry.entry_type <> 'EARNING'
      or entry.subject_type <> 'MERCHANT_ORGANIZATION'
      or not exists (
        select 1 from dastak_v1.recovery_cases recovery
        where recovery.source_fulfilment_id = entry.fulfilment_id
          and recovery.order_line_id = entry.order_line_id
      )
      or exists (
        select 1 from dastak_v1.recovery_cases recovery
        where recovery.source_fulfilment_id = entry.fulfilment_id
          and recovery.order_line_id = entry.order_line_id
          and (
            (recovery.status = 'RECOVERED' and exists (
              select 1 from dastak_v1.settlement_entries adjustment
              where adjustment.entry_key = recovery.order_id::text
                || ':RECOVERY_DEBIT:' || recovery.id::text
            ))
            or (recovery.status = 'RECOVERY_FAILED' and exists (
              select 1 from dastak_v1.refunds refund
              where refund.recovery_case_id = recovery.id
                and refund.status = 'COMPLETED'
            ))
          )
      )
    );
  get diagnostics v_changed = row_count;
  return v_changed;
end;
$$;

create function dastak_v1.mark_settlements_after_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
begin
  if old.status <> 'DELIVERED' and new.status = 'DELIVERED' then
    select mission.* into v_mission from dastak_v1.delivery_missions mission
    where mission.order_id = new.id and mission.status = 'DELIVERED'
    order by mission.delivered_at desc limit 1;
    if v_mission.id is not null and v_mission.assigned_rider_id is not null then
      insert into dastak_v1.settlement_entries (
        entry_key, subject_type, subject_id, order_id, delivery_mission_id,
        entry_type, status, calculation_status, gross_amount_paise,
        amount_paise, calculation_snapshot
      ) values (
        new.id::text || ':RIDER:' || v_mission.id::text,
        'RIDER', v_mission.assigned_rider_id, new.id, v_mission.id,
        'EARNING', 'PENDING', 'CALCULATED',
        v_mission.rider_payout_quote_paise,
        v_mission.rider_payout_quote_paise,
        v_mission.rider_payout_quote_snapshot || pg_catalog.jsonb_build_object(
          'missionId', v_mission.id,
          'missionQuotePreserved', true,
          'configurationRequired', false
        )
      ) on conflict (entry_key) do nothing;
    end if;
    perform dastak_v1_api.mark_order_settlements_eligible(
      new.id, null, 'Successful delivery made correct merchant and rider earnings eligible.', true
    );
  end if;
  return new;
end;
$$;

create trigger orders_mark_settlements_after_delivery
after update on dastak_v1.orders
for each row execute function dastak_v1.mark_settlements_after_delivery();

create function dastak_v1.mark_refund_adjustment_eligible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status <> 'COMPLETED' and new.status = 'COMPLETED' then
    perform dastak_v1_api.mark_order_settlements_eligible(
      new.order_id, null,
      'Completed original-method refund made its append-only adjustment eligible.',
      false
    );
  end if;
  return new;
end;
$$;

create trigger refunds_mark_adjustment_eligible
after update on dastak_v1.refunds
for each row execute function dastak_v1.mark_refund_adjustment_eligible();

create function dastak_v1_api.finalize_settlement_calculation(
  p_actor_id uuid,
  p_settlement_entry_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'finalizeSettlementCalculation';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_entry dastak_v1.settlement_entries%rowtype;
  v_rate integer;
  v_amount bigint;
  v_mission_payout_snapshot jsonb;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.settlements.manage');
  if p_settlement_entry_id is null or p_expected_version is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid settlement calculation';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'settlementEntryId', p_settlement_entry_id,
    'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select entry.* into v_entry from dastak_v1.settlement_entries entry
  where entry.id = p_settlement_entry_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'settlement entry not found'; end if;
  if v_entry.version <> p_expected_version or v_entry.status <> 'PENDING' then
    raise exception using errcode = '40001', message = 'STALE_SETTLEMENT_VERSION';
  end if;
  if v_entry.calculation_status = 'SYSTEM_CONFIGURATION_REQUIRED' then
    if v_entry.subject_type = 'RIDER' then
      select mission.rider_payout_quote_paise,
        mission.rider_payout_quote_snapshot
      into v_amount, v_mission_payout_snapshot
      from dastak_v1.delivery_missions mission
      where mission.id = v_entry.delivery_mission_id
        and mission.order_id = v_entry.order_id;
      if v_amount is null or v_mission_payout_snapshot is null then
        raise exception using
          errcode = '55000',
          message = 'SETTLEMENT_MISSION_PAYOUT_SNAPSHOT_REQUIRED';
      end if;
    elsif v_entry.entry_type = 'EARNING' then
      v_rate := dastak_v1_api.required_setting_integer(
        'settlement.merchant_commission_bps'
      );
      if v_rate not between 0 and 10000 then
        raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR';
      end if;
      v_amount := pg_catalog.floor(
        v_entry.gross_amount_paise::numeric * (10000 - v_rate) / 10000
      )::bigint;
    else
      select abs(source.amount_paise) into v_amount
      from dastak_v1.settlement_entries source
      where source.id = (v_entry.calculation_snapshot ->> 'originalEarningEntryId')::uuid;
      if v_amount is null then
        raise exception using errcode = '55000', message = 'SETTLEMENT_SOURCE_NOT_CALCULATED';
      end if;
      v_amount := -least(v_amount, coalesce(v_entry.gross_amount_paise, v_amount));
    end if;
    perform pg_catalog.set_config('dastak_v1.settlement_actor_id', p_actor_id::text, true);
    perform pg_catalog.set_config(
      'dastak_v1.settlement_reason', 'Required settlement configuration supplied.', true
    );
    update dastak_v1.settlement_entries entry
    set calculation_status = 'CALCULATED', amount_paise = v_amount,
        calculation_snapshot = entry.calculation_snapshot
          || case when entry.subject_type = 'RIDER'
            then v_mission_payout_snapshot || pg_catalog.jsonb_build_object(
              'missionId', entry.delivery_mission_id,
              'missionQuotePreserved', true
            )
            else pg_catalog.jsonb_build_object('configuredRate', v_rate)
          end
          || pg_catalog.jsonb_build_object(
            'calculatedBy', p_actor_id,
            'calculatedAt', pg_catalog.clock_timestamp(),
            'configurationRequired', false
          ),
        version = entry.version + 1
    where entry.id = v_entry.id returning * into v_entry;
  end if;
  if exists (
    select 1 from dastak_v1.orders customer_order
    where customer_order.id = v_entry.order_id
      and customer_order.status in ('DELIVERED', 'DASTAK_FULFILMENT_FAILURE')
  ) then
    perform dastak_v1_api.mark_order_settlements_eligible(
      v_entry.order_id, p_actor_id,
      'Finance completed required settlement calculation.', true
    );
    select entry.* into v_entry from dastak_v1.settlement_entries entry
    where entry.id = v_entry.id;
  end if;
  v_response := pg_catalog.jsonb_build_object(
    'settlementEntryId', v_entry.id, 'status', v_entry.status,
    'calculationStatus', v_entry.calculation_status,
    'amountPaise', v_entry.amount_paise, 'currency', v_entry.currency_code,
    'version', v_entry.version
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_entry.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_finalize_settlement_calculation(
  p_settlement_entry_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.finalize_settlement_calculation(
    auth.uid(), p_settlement_entry_id, p_expected_version, p_idempotency_key
  );
$$;

create function dastak_v1_api.settle_entry(
  p_actor_id uuid,
  p_settlement_entry_id uuid,
  p_settlement_reference text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'settleEntry';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_entry dastak_v1.settlement_entries%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.settlements.manage');
  if p_settlement_entry_id is null or p_expected_version is null
    or nullif(pg_catalog.btrim(p_settlement_reference), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_settlement_reference)) > 200
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid settlement reference';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'settlementEntryId', p_settlement_entry_id,
    'settlementReference', pg_catalog.btrim(p_settlement_reference),
    'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select entry.* into v_entry from dastak_v1.settlement_entries entry
  where entry.id = p_settlement_entry_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'settlement entry not found'; end if;
  if v_entry.version <> p_expected_version or v_entry.status <> 'ELIGIBLE' then
    raise exception using errcode = '40001', message = 'STALE_SETTLEMENT_VERSION';
  end if;
  perform pg_catalog.set_config('dastak_v1.settlement_actor_id', p_actor_id::text, true);
  perform pg_catalog.set_config('dastak_v1.settlement_reason', 'Bank payout recorded.', true);
  update dastak_v1.settlement_entries entry
  set status = 'SETTLED', settled_at = pg_catalog.clock_timestamp(),
      settlement_reference = pg_catalog.btrim(p_settlement_reference),
      version = entry.version + 1
  where entry.id = v_entry.id returning * into v_entry;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'SETTLEMENT_RECORDED', 'settlement_entry', v_entry.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_entry.order_id, 'subjectType', v_entry.subject_type,
      'subjectId', v_entry.subject_id, 'amountPaise', v_entry.amount_paise,
      'settlementReference', v_entry.settlement_reference
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'settlementEntryId', v_entry.id, 'status', v_entry.status,
    'amountPaise', v_entry.amount_paise,
    'settlementReference', v_entry.settlement_reference,
    'settledAt', v_entry.settled_at, 'version', v_entry.version
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_entry.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_settle_entry(
  p_settlement_entry_id uuid,
  p_settlement_reference text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.settle_entry(
    auth.uid(), p_settlement_entry_id, p_settlement_reference,
    p_expected_version, p_idempotency_key
  );
$$;

do $$
declare
  v_function regprocedure;
begin
  for v_function in
    select function_row.oid::regprocedure
    from pg_catalog.pg_proc function_row
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function_row.pronamespace
    where namespace.nspname in ('dastak_v1', 'dastak_v1_api')
      and function_row.proname in (
        'required_setting_integer',
        'recovery_branch_eligibility',
        'cancel_pre_custody_mission_for_recovery',
        'seed_merchant_settlement_entry',
        'create_approved_refund',
        'report_exact_sku_failure',
        'create_exact_sku_recovery_offer',
        'respond_exact_sku_recovery_offer',
        'fail_exact_sku_recovery',
        'report_customer_issue',
        'decide_customer_issue',
        'assign_return_rider',
        'advance_return_mission',
        'manage_delivery_recovery',
        'prepare_razorpay_refund',
        'attach_razorpay_refund',
        'record_razorpay_refund_event',
        'create_exact_recovery_settlement_debit',
        'mark_order_settlements_eligible',
        'finalize_settlement_calculation',
        'settle_entry',
        'guard_recovery_case',
        'guard_recovery_opportunity',
        'guard_customer_issue',
        'guard_return',
        'guard_return_mission',
        'guard_refund',
        'guard_settlement_entry',
        'guard_step5_delivery_mission',
        'guard_step5_package',
        'open_delivery_recovery_case',
        'seed_settlements_after_payment',
        'mark_settlements_after_delivery',
        'mark_refund_adjustment_eligible'
      )
  loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      v_function
    );
  end loop;
end;
$$;

revoke execute on function public.dastak_v1_report_exact_sku_failure(
  uuid, uuid, text, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_create_exact_sku_recovery_offer(
  uuid, uuid, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_respond_exact_sku_recovery_offer(
  uuid, text, integer, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_fail_exact_sku_recovery(
  uuid, text, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_report_customer_issue(
  uuid, uuid, text, text, text, text, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_decide_customer_issue(
  uuid, text, bigint, text, integer, text, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_assign_return_rider(
  uuid, uuid, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_advance_return_mission(
  uuid, text, uuid, text, text, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_manage_delivery_recovery(
  uuid, text, text, bigint, jsonb, text, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_prepare_razorpay_refund(
  uuid, uuid, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_attach_razorpay_refund(
  uuid, uuid, text, bigint
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_finalize_settlement_calculation(
  uuid, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_settle_entry(
  uuid, text, bigint, text
) from public, anon, authenticated, service_role;

grant execute on function dastak_v1_api.report_exact_sku_failure(
  uuid, uuid, uuid, text, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.create_exact_sku_recovery_offer(
  uuid, uuid, uuid, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.respond_exact_sku_recovery_offer(
  uuid, uuid, text, integer, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.fail_exact_sku_recovery(
  uuid, uuid, text, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.report_customer_issue(
  uuid, uuid, uuid, text, text, text, text, text
) to authenticated;
grant execute on function dastak_v1_api.decide_customer_issue(
  uuid, uuid, text, bigint, text, integer, text, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.assign_return_rider(
  uuid, uuid, uuid, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) to authenticated;
grant execute on function dastak_v1_api.manage_delivery_recovery(
  uuid, uuid, text, text, bigint, jsonb, text, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.finalize_settlement_calculation(
  uuid, uuid, bigint, text
) to authenticated;
grant execute on function dastak_v1_api.settle_entry(
  uuid, uuid, text, bigint, text
) to authenticated;

grant execute on function dastak_v1_api.prepare_razorpay_refund(
  uuid, uuid, text
) to service_role;
grant execute on function dastak_v1_api.attach_razorpay_refund(
  uuid, uuid, text, bigint
) to service_role;
grant execute on function dastak_v1_api.record_razorpay_refund_event(
  text, text, text, bigint, timestamptz, text
) to service_role;

grant execute on function public.dastak_v1_report_exact_sku_failure(
  uuid, uuid, text, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_create_exact_sku_recovery_offer(
  uuid, uuid, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_respond_exact_sku_recovery_offer(
  uuid, text, integer, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_fail_exact_sku_recovery(
  uuid, text, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_report_customer_issue(
  uuid, uuid, text, text, text, text, text
) to authenticated;
grant execute on function public.dastak_v1_decide_customer_issue(
  uuid, text, bigint, text, integer, text, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_assign_return_rider(
  uuid, uuid, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_advance_return_mission(
  uuid, text, uuid, text, text, text
) to authenticated;
grant execute on function public.dastak_v1_manage_delivery_recovery(
  uuid, text, text, bigint, jsonb, text, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_finalize_settlement_calculation(
  uuid, bigint, text
) to authenticated;
grant execute on function public.dastak_v1_settle_entry(
  uuid, text, bigint, text
) to authenticated;

grant execute on function public.dastak_v1_prepare_razorpay_refund(
  uuid, uuid, text
) to service_role;
grant execute on function public.dastak_v1_attach_razorpay_refund(
  uuid, uuid, text, bigint
) to service_role;
grant execute on function public.dastak_v1_record_razorpay_event(
  text, text, text, text, text, bigint, timestamptz, text
) to service_role;

comment on table dastak_v1.recovery_cases is
  'Locked V1 exact-SKU and delivery recovery state; customer-facing projections hide merchant identity.';
comment on table dastak_v1.returns is
  'Locked V1 return decision and completion record with explicit fault and refund semantics.';
comment on table dastak_v1.refunds is
  'Original-method refund lifecycle, provider idempotency and reconciliation source of truth.';
comment on table dastak_v1.settlement_entries is
  'Append-only earning and adjustment ledger; settlement status mutates under guarded finance commands.';
