-- Dastak V1 Batch B: locked transport limits and scoped operational safety.

create type dastak_v1.rider_escalation_state as enum (
  'NONE', 'STALLED', 'UNRESPONSIVE',
  'RELEASED_PRE_CUSTODY', 'DELIVERY_RECOVERY'
);

create type dastak_v1.operational_pause_scope as enum (
  'ZONE_RETAIL', 'ZONE_FOOD', 'ZONE_MIXED',
  'MERCHANT_BRANCH', 'RIDER_ASSIGNMENTS'
);

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values
  (
    'delivery.rider_stall_threshold_seconds', 'DURATION_SECONDS',
    'Elapsed time without mission progress before a rider mission is marked stalled.',
    null, '{"minimum":1}'::jsonb, true, true
  ),
  (
    'delivery.rider_unresponsive_threshold_seconds', 'DURATION_SECONDS',
    'Elapsed time without rider contact before Operations escalation.',
    null, '{"minimum":1}'::jsonb, true, true
  );

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values
  (
    'platform.delivery.operations.manage',
    'Operate scoped delivery escalation and safe pre-custody rematching.',
    'HIGHLY_SENSITIVE'
  ),
  (
    'platform.operational_safety.manage',
    'Pause or resume narrowly scoped new marketplace commitments.',
    'HIGHLY_SENSITIVE'
  );

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
values
  (
    '10000000-0000-4000-8000-000000000008',
    'platform.delivery.operations.manage'
  ),
  (
    '10000000-0000-4000-8000-000000000008',
    'platform.operational_safety.manage'
  ),
  (
    '10000000-0000-4000-8000-00000000000c',
    'platform.delivery.operations.manage'
  ),
  (
    '10000000-0000-4000-8000-00000000000c',
    'platform.operational_safety.manage'
  );

alter table dastak_v1.delivery_missions
  add column rider_last_contact_at timestamptz,
  add column rider_last_progress_at timestamptz,
  add column stall_detected_at timestamptz,
  add column unresponsive_detected_at timestamptz,
  add column escalation_state dastak_v1.rider_escalation_state not null default 'NONE',
  add column escalated_at timestamptz,
  add column escalation_reason text,
  add column escalated_by uuid references public.accounts(id);

create index delivery_missions_escalation_idx
  on dastak_v1.delivery_missions (escalation_state, rider_last_contact_at, id)
  where assigned_rider_id is not null
    and status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED');
create index delivery_missions_escalated_by_idx
  on dastak_v1.delivery_missions (escalated_by);

create table dastak_v1.operational_pause_controls (
  id uuid primary key default gen_random_uuid(),
  scope dastak_v1.operational_pause_scope not null,
  service_zone_id uuid references public.service_zones(id),
  branch_id uuid references dastak_v1.merchant_branches(id),
  rider_id uuid references public.accounts(id),
  active boolean not null,
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 500
  ),
  activated_by uuid references public.accounts(id),
  activated_at timestamptz,
  cleared_by uuid references public.accounts(id),
  cleared_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (scope in ('ZONE_RETAIL', 'ZONE_FOOD', 'ZONE_MIXED')
      and service_zone_id is not null and branch_id is null and rider_id is null)
    or (scope = 'MERCHANT_BRANCH'
      and service_zone_id is null and branch_id is not null and rider_id is null)
    or (scope = 'RIDER_ASSIGNMENTS'
      and service_zone_id is null and branch_id is null and rider_id is not null)
  ),
  check (
    (active and activated_by is not null and activated_at is not null
      and cleared_by is null and cleared_at is null)
    or (not active and cleared_by is not null and cleared_at is not null)
  )
);

create unique index operational_pause_controls_zone_uidx
  on dastak_v1.operational_pause_controls (scope, service_zone_id)
  where service_zone_id is not null;
create unique index operational_pause_controls_branch_uidx
  on dastak_v1.operational_pause_controls (scope, branch_id)
  where branch_id is not null;
create unique index operational_pause_controls_rider_uidx
  on dastak_v1.operational_pause_controls (scope, rider_id)
  where rider_id is not null;
create index operational_pause_controls_active_idx
  on dastak_v1.operational_pause_controls (scope, updated_at, id)
  where active;
create index operational_pause_controls_service_zone_fk_idx
  on dastak_v1.operational_pause_controls (service_zone_id);
create index operational_pause_controls_branch_fk_idx
  on dastak_v1.operational_pause_controls (branch_id);
create index operational_pause_controls_rider_fk_idx
  on dastak_v1.operational_pause_controls (rider_id);
create index operational_pause_controls_activated_by_idx
  on dastak_v1.operational_pause_controls (activated_by);
create index operational_pause_controls_cleared_by_idx
  on dastak_v1.operational_pause_controls (cleared_by);

alter table dastak_v1.operational_pause_controls enable row level security;
revoke all on table dastak_v1.operational_pause_controls
  from public, anon, authenticated;
grant select, insert, update on table dastak_v1.operational_pause_controls
  to service_role;

create function dastak_v1.guard_operational_pause_control()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
      or new.scope is distinct from old.scope
      or new.service_zone_id is distinct from old.service_zone_id
      or new.branch_id is distinct from old.branch_id
      or new.rider_id is distinct from old.rider_id
      or new.created_at is distinct from old.created_at then
      raise exception 'operational pause identity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'operational pause version must increment exactly once';
    end if;
    if new.active is not distinct from old.active then
      raise exception 'operational pause update must change active state';
    end if;
    new.updated_at := pg_catalog.now();
  end if;
  return new;
end;
$$;

create trigger operational_pause_controls_guard
before update on dastak_v1.operational_pause_controls
for each row execute function dastak_v1.guard_operational_pause_control();
create trigger operational_pause_controls_no_delete
before delete on dastak_v1.operational_pause_controls
for each row execute function dastak_v1.reject_delete();

-- The production profiles are locked product safety limits, not arbitrary
-- merchant or rider-entered values.
create or replace function dastak_v1.is_valid_transport_load_profiles(p_profiles jsonb)
returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_profile jsonb;
  v_type text;
  v_seen text[] := '{}'::text[];
  v_expected_weight bigint;
  v_expected_volume bigint;
  v_expected_packages integer;
  v_expected_longest integer;
begin
  if pg_catalog.jsonb_typeof(p_profiles) <> 'array'
    or pg_catalog.jsonb_array_length(p_profiles) <> 6 then
    return false;
  end if;
  for v_profile in
    select value from pg_catalog.jsonb_array_elements(p_profiles)
  loop
    if pg_catalog.jsonb_typeof(v_profile) <> 'object' then return false; end if;
    v_type := v_profile ->> 'transportType';
    if v_type not in ('WALKING', 'BICYCLE', 'MOTORBIKE', 'SCOOTER', 'AUTO', 'CAR')
      or v_type = any(v_seen) then
      return false;
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_type);
    select expected.weight_grams, expected.volume_mm3,
      expected.package_count, expected.longest_mm
    into v_expected_weight, v_expected_volume,
      v_expected_packages, v_expected_longest
    from (values
      ('WALKING', 5000::bigint, 20000000::bigint, 2, 400),
      ('BICYCLE', 10000::bigint, 35000000::bigint, 3, 500),
      ('MOTORBIKE', 20000::bigint, 60000000::bigint, 4, 600),
      ('SCOOTER', 25000::bigint, 75000000::bigint, 5, 650),
      ('AUTO', 80000::bigint, 250000000::bigint, 12, 1000),
      ('CAR', 150000::bigint, 500000000::bigint, 20, 1200)
    ) expected(transport_type, weight_grams, volume_mm3, package_count, longest_mm)
    where expected.transport_type = v_type;

    if pg_catalog.jsonb_typeof(v_profile -> 'maxWeightGrams') <> 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxVolumeCubicMillimetres') <> 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxPackageCount') <> 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxLongestSideMillimetres') <> 'number'
      or (v_profile ->> 'maxWeightGrams')::bigint <> v_expected_weight
      or (v_profile ->> 'maxVolumeCubicMillimetres')::bigint <> v_expected_volume
      or (v_profile ->> 'maxPackageCount')::integer <> v_expected_packages
      or (v_profile ->> 'maxLongestSideMillimetres')::integer <> v_expected_longest then
      return false;
    end if;
  end loop;
  return pg_catalog.cardinality(v_seen) = 6;
exception
  when invalid_text_representation or numeric_value_out_of_range then return false;
end;
$$;

create or replace function dastak_v1.is_valid_default_sku_logistics(p_value jsonb)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_typeof(p_value) = 'object'
    and pg_catalog.jsonb_typeof(p_value -> 'weightGrams') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'volumeCubicMillimetres') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'longestSideMillimetres') = 'number'
    and (p_value ->> 'weightGrams')::bigint = 1000
    and (p_value ->> 'volumeCubicMillimetres')::bigint = 4000000
    and (p_value ->> 'longestSideMillimetres')::integer = 300,
    false
  );
$$;

create function dastak_v1_api.transport_load_snapshot(
  p_total_weight_grams numeric,
  p_total_volume_cubic_millimetres numeric,
  p_package_count integer,
  p_longest_side_millimetres numeric,
  p_package_count_final boolean,
  p_profiles jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_feasible jsonb;
begin
  if p_total_weight_grams is null or p_total_weight_grams <= 0
    or p_total_volume_cubic_millimetres is null
    or p_total_volume_cubic_millimetres <= 0
    or p_package_count is null or p_package_count < 1
    or p_longest_side_millimetres is null or p_longest_side_millimetres <= 0
    or p_package_count_final is null
    or not dastak_v1.is_valid_transport_load_profiles(p_profiles) then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Locked transport load input or configuration is invalid.';
  end if;
  select coalesce(
    pg_catalog.jsonb_agg(profile.value order by profile.value ->> 'transportType'),
    '[]'::jsonb
  ) into v_feasible
  from pg_catalog.jsonb_array_elements(p_profiles) profile(value)
  where (profile.value ->> 'maxWeightGrams')::numeric >= p_total_weight_grams
    and (profile.value ->> 'maxVolumeCubicMillimetres')::numeric >=
      p_total_volume_cubic_millimetres
    and (profile.value ->> 'maxLongestSideMillimetres')::numeric >=
      p_longest_side_millimetres
    and (profile.value ->> 'maxPackageCount')::integer >= p_package_count;
  return pg_catalog.jsonb_build_object(
    'feasible', pg_catalog.jsonb_array_length(v_feasible) > 0,
    'classificationStage', case when p_package_count_final then 'FINAL' else 'PRE_OFFER' end,
    'packageCountFinal', p_package_count_final,
    'packageCount', p_package_count,
    'totalWeightGrams', p_total_weight_grams,
    'totalVolumeCubicMillimetres', p_total_volume_cubic_millimetres,
    'longestSideMillimetres', p_longest_side_millimetres,
    'containsBulky', false,
    'temperatureClasses', '[]'::jsonb,
    'eligibleTransportTypes', (
      select coalesce(
        pg_catalog.jsonb_agg(profile.value ->> 'transportType'), '[]'::jsonb
      ) from pg_catalog.jsonb_array_elements(v_feasible) profile(value)
    )
  );
end;
$$;

create or replace function dastak_v1_api.order_transport_snapshot(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_configuration jsonb;
  v_default jsonb;
  v_profiles jsonb;
  v_total_weight numeric := 0;
  v_total_volume numeric := 0;
  v_longest_side numeric := 0;
  v_package_count integer := 1;
  v_package_count_final boolean := false;
  v_fulfilment_count integer := 0;
  v_line record;
  v_attributes jsonb;
  v_weight numeric;
  v_volume numeric;
  v_longest numeric;
begin
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_default := v_configuration -> 'defaultSkuLogistics';
  v_profiles := v_configuration -> 'transportLoadProfiles';

  for v_line in
    select order_line.quantity, sku.logistics_attributes
    from dastak_v1.order_lines order_line
    join dastak_v1.skus sku on sku.id = order_line.sku_id
    where order_line.order_id = p_order_id
      and order_line.line_type = 'RETAIL_SKU'
    order by order_line.id
  loop
    v_attributes := v_line.logistics_attributes;
    if pg_catalog.jsonb_typeof(v_attributes -> 'weightGrams') = 'number'
      and pg_catalog.jsonb_typeof(v_attributes -> 'lengthMillimetres') = 'number'
      and pg_catalog.jsonb_typeof(v_attributes -> 'widthMillimetres') = 'number'
      and pg_catalog.jsonb_typeof(v_attributes -> 'heightMillimetres') = 'number'
      and (v_attributes ->> 'weightGrams')::numeric > 0
      and (v_attributes ->> 'lengthMillimetres')::numeric > 0
      and (v_attributes ->> 'widthMillimetres')::numeric > 0
      and (v_attributes ->> 'heightMillimetres')::numeric > 0 then
      v_weight := (v_attributes ->> 'weightGrams')::numeric;
      v_volume := (v_attributes ->> 'lengthMillimetres')::numeric
        * (v_attributes ->> 'widthMillimetres')::numeric
        * (v_attributes ->> 'heightMillimetres')::numeric;
      v_longest := greatest(
        (v_attributes ->> 'lengthMillimetres')::numeric,
        (v_attributes ->> 'widthMillimetres')::numeric,
        (v_attributes ->> 'heightMillimetres')::numeric
      );
    else
      v_weight := (v_default ->> 'weightGrams')::numeric;
      v_volume := (v_default ->> 'volumeCubicMillimetres')::numeric;
      v_longest := (v_default ->> 'longestSideMillimetres')::numeric;
    end if;
    v_total_weight := v_total_weight + v_weight * v_line.quantity;
    v_total_volume := v_total_volume + v_volume * v_line.quantity;
    v_longest_side := greatest(v_longest_side, v_longest);
  end loop;

  select count(*), coalesce(sum(coalesce(fulfilment.package_count, 1)), 0),
    coalesce(bool_and(fulfilment.package_count is not null), false)
  into v_fulfilment_count, v_package_count, v_package_count_final
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id
    and fulfilment.status <> 'RELEASED';
  if v_fulfilment_count = 0 then
    v_package_count := 1;
    v_package_count_final := false;
  end if;

  if v_total_weight <= 0 or v_total_volume <= 0 or v_longest_side <= 0 then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Order logistics could not be calculated from canonical or locked fallback data.';
  end if;

  return dastak_v1_api.transport_load_snapshot(
    v_total_weight, v_total_volume, v_package_count, v_longest_side,
    v_package_count_final, v_profiles
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Canonical SKU logistics or locked transport limits contain invalid numbers.';
end;
$$;

create function dastak_v1_api.rider_escalation_configuration()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_stall integer;
  v_unresponsive integer;
begin
  v_stall := dastak_v1_api.required_setting_integer(
    'delivery.rider_stall_threshold_seconds'
  );
  v_unresponsive := dastak_v1_api.required_setting_integer(
    'delivery.rider_unresponsive_threshold_seconds'
  );
  if v_stall < 1 or v_unresponsive < v_stall then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Rider unresponsive threshold must be at least the stall threshold.';
  end if;
  return pg_catalog.jsonb_build_object(
    'stallThresholdSeconds', v_stall,
    'unresponsiveThresholdSeconds', v_unresponsive
  );
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
  v_transport_revalidation boolean := coalesce(
    pg_catalog.current_setting('dastak_v1.transport_revalidation', true), ''
  ) = 'true';
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or (
      new.transport_snapshot is distinct from old.transport_snapshot
      and not v_transport_revalidation
    )
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
    or new.all_packages_picked_up_at is null or new.out_for_delivery_at is null
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
    old.status not in ('ARRIVED', 'DELIVERY_RECOVERY') or new.delivered_at is null
  ) then
    raise exception 'DELIVERED requires verified or authorized final handoff';
  end if;

  if old.assigned_rider_id is null and new.assigned_rider_id is not null then
    new.rider_last_contact_at := v_now;
    new.rider_last_progress_at := v_now;
    new.stall_detected_at := null;
    new.unresponsive_detected_at := null;
    new.escalation_state := 'NONE';
    new.escalated_at := null;
    new.escalation_reason := null;
    new.escalated_by := null;
  elsif new.assigned_rider_id is not null and new.status is distinct from old.status
    and new.status <> 'DELIVERY_RECOVERY' then
    new.rider_last_progress_at := v_now;
  end if;

  if new.escalation_state is distinct from old.escalation_state and not (
    (old.escalation_state = 'NONE' and new.escalation_state in ('STALLED', 'UNRESPONSIVE'))
    or (old.escalation_state = 'STALLED' and new.escalation_state in ('NONE', 'UNRESPONSIVE'))
    or (old.escalation_state in ('NONE', 'STALLED', 'UNRESPONSIVE')
      and new.escalation_state in ('RELEASED_PRE_CUSTODY', 'DELIVERY_RECOVERY'))
    or (old.assigned_rider_id is null and new.assigned_rider_id is not null
      and new.escalation_state = 'NONE')
  ) then
    raise exception 'invalid rider escalation transition: % -> %',
      old.escalation_state, new.escalation_state;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1_api.mission_has_package_custody(p_mission_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from dastak_v1.delivery_missions mission
    join dastak_v1.packages package on package.order_id = mission.order_id
    where mission.id = p_mission_id
      and (
        mission.first_package_picked_up_at is not null
        or package.current_custody_owner_type = 'RIDER'
      )
  );
$$;

create function dastak_v1_api.reopen_rider_search_after_release(
  p_mission_id uuid,
  p_reason text,
  p_actor_id uuid default null,
  p_now timestamptz default pg_catalog.clock_timestamp()
)
returns dastak_v1.delivery_missions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
begin
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'mission not found'; end if;
  if dastak_v1_api.mission_has_package_custody(v_mission.id) then
    raise exception using errcode = '55000', message = 'DELIVERY_RECOVERY_REQUIRED';
  end if;
  if v_mission.status not in (
    'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS'
  ) then
    raise exception using errcode = '55000', message = 'MISSION_NOT_REASSIGNABLE';
  end if;

  perform pg_catalog.set_config('dastak_v1.recovery_reroute', 'true', true);
  update dastak_v1.delivery_missions mission
  set status = 'REASSIGNING', assigned_rider_id = null,
      assigned_transport_type = null, assigned_at = null,
      escalation_state = 'RELEASED_PRE_CUSTODY', escalated_at = p_now,
      escalation_reason = pg_catalog.btrim(p_reason), escalated_by = p_actor_id,
      version = mission.version + 1
  where mission.id = v_mission.id
  returning * into v_mission;
  update dastak_v1.delivery_offers offer
  set status = 'CLOSED', responded_at = coalesce(offer.responded_at, p_now),
      closed_reason = 'RELEASED_PRE_CUSTODY', version = offer.version + 1
  where offer.mission_id = v_mission.id and offer.status in ('OFFERED', 'ACCEPTED');
  update dastak_v1.delivery_stops stop
  set status = 'PENDING', arrived_at = null, completed_at = null,
      waiting_seconds = null, version = stop.version + 1
  where stop.mission_id = v_mission.id and stop.status = 'ARRIVED';
  update dastak_v1.delivery_missions mission
  set status = 'SEARCHING_RIDER', pool_round = mission.pool_round + 1,
      version = mission.version + 1
  where mission.id = v_mission.id
  returning * into v_mission;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_mission.id::text || ':RIDER_RELEASED_PRE_CUSTODY:' || v_mission.version::text,
    'DELIVERY_MISSION', v_mission.id, v_mission.version,
    'RIDER_RELEASED_PRE_CUSTODY', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_mission.order_id, 'missionId', v_mission.id,
      'reason', pg_catalog.btrim(p_reason)
    )
  );
  perform dastak_v1_api.create_rider_offer_pool(v_mission.id, p_now);
  return v_mission;
end;
$$;

create function dastak_v1.revalidate_mission_transport_after_packages()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_snapshot jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if old.package_count is not null or new.package_count is null then return new; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-delivery:' || new.order_id::text, 0)
  );
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.order_id = new.order_id
    and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
  order by mission.created_at desc limit 1 for update;
  if not found then return new; end if;

  v_snapshot := dastak_v1_api.order_transport_snapshot(new.order_id);
  if not coalesce((v_snapshot ->> 'packageCountFinal')::boolean, false) then
    return new;
  end if;
  perform pg_catalog.set_config('dastak_v1.transport_revalidation', 'true', true);

  if v_mission.assigned_rider_id is not null and not (
    v_snapshot -> 'eligibleTransportTypes'
  ) @> pg_catalog.to_jsonb(array[v_mission.assigned_transport_type::text]) then
    if dastak_v1_api.mission_has_package_custody(v_mission.id) then
      update dastak_v1.delivery_missions mission
      set transport_snapshot = v_snapshot, status = 'DELIVERY_RECOVERY',
          escalation_state = 'DELIVERY_RECOVERY', escalated_at = v_now,
          escalation_reason = 'FINAL_PACKAGE_LOAD_EXCEEDS_ASSIGNED_TRANSPORT',
          version = mission.version + 1
      where mission.id = v_mission.id;
      return new;
    end if;
    update dastak_v1.delivery_missions mission
    set transport_snapshot = v_snapshot, version = mission.version + 1
    where mission.id = v_mission.id;
    perform dastak_v1_api.reopen_rider_search_after_release(
      v_mission.id, 'FINAL_PACKAGE_LOAD_EXCEEDS_ASSIGNED_TRANSPORT', null, v_now
    );
  elsif v_mission.status = 'SEARCHING_RIDER' then
    update dastak_v1.delivery_offers offer
    set status = 'CLOSED', responded_at = coalesce(offer.responded_at, v_now),
        closed_reason = 'FINAL_PACKAGE_LOAD_RECLASSIFIED', version = offer.version + 1
    where offer.mission_id = v_mission.id and offer.status = 'OFFERED';
    update dastak_v1.delivery_missions mission
    set transport_snapshot = v_snapshot, pool_round = mission.pool_round + 1,
        version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, payload
    ) values (
      v_mission.id::text || ':TRANSPORT_LOAD_FINALIZED:' || v_mission.version::text,
      'DELIVERY_MISSION', v_mission.id, v_mission.version,
      'TRANSPORT_LOAD_FINALIZED', pg_catalog.jsonb_build_object(
        'orderId', v_mission.order_id, 'missionId', v_mission.id,
        'transport', v_snapshot
      )
    );
    perform dastak_v1_api.create_rider_offer_pool(v_mission.id, v_now);
  elsif v_mission.first_package_picked_up_at is null then
    update dastak_v1.delivery_missions mission
    set transport_snapshot = v_snapshot, version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, payload
    ) values (
      v_mission.id::text || ':TRANSPORT_LOAD_FINALIZED:' || v_mission.version::text,
      'DELIVERY_MISSION', v_mission.id, v_mission.version,
      'TRANSPORT_LOAD_FINALIZED', pg_catalog.jsonb_build_object(
        'orderId', v_mission.order_id, 'missionId', v_mission.id,
        'transport', v_snapshot
      )
    );
  end if;
  return new;
end;
$$;

create trigger fulfilments_revalidate_transport_after_packages
after update of package_count on dastak_v1.fulfilments
for each row execute function dastak_v1.revalidate_mission_transport_after_packages();

create function dastak_v1.enforce_final_transport_before_pickup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_actual_package_count integer;
begin
  if old.status = 'READY' and new.status = 'PICKED_UP' then
    select mission.* into v_mission
    from dastak_v1.delivery_missions mission
    where mission.order_id = new.order_id
      and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
    order by mission.created_at desc limit 1 for update;
    if not found or v_mission.assigned_rider_id is null
      or coalesce((v_mission.transport_snapshot ->> 'packageCountFinal')::boolean, false) is false
      or not (v_mission.transport_snapshot -> 'eligibleTransportTypes') @>
        pg_catalog.to_jsonb(array[v_mission.assigned_transport_type::text]) then
      raise exception using errcode = '55000', message = 'FINAL_TRANSPORT_REVALIDATION_REQUIRED';
    end if;
    select count(*) into v_actual_package_count
    from dastak_v1.packages package where package.order_id = new.order_id;
    if v_actual_package_count <> (v_mission.transport_snapshot ->> 'packageCount')::integer then
      raise exception using errcode = '55000', message = 'FINAL_PACKAGE_COUNT_MISMATCH';
    end if;
  end if;
  return new;
end;
$$;

create trigger packages_enforce_final_transport_before_pickup
before update of status on dastak_v1.packages
for each row execute function dastak_v1.enforce_final_transport_before_pickup();

create function dastak_v1.enforce_zone_ordering_pause()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_type dastak_v1.order_type;
  v_scope dastak_v1.operational_pause_scope;
begin
  select customer_order.order_type into v_order_type
  from dastak_v1.orders customer_order where customer_order.id = new.order_id;
  if pg_catalog.jsonb_typeof(new.delivery_address -> 'latitude') <> 'number'
    or pg_catalog.jsonb_typeof(new.delivery_address -> 'longitude') <> 'number' then
    return new;
  end if;
  v_scope := case v_order_type
    when 'RETAIL_ONLY' then 'ZONE_RETAIL'::dastak_v1.operational_pause_scope
    when 'FOOD_ONLY' then 'ZONE_FOOD'::dastak_v1.operational_pause_scope
    else 'ZONE_MIXED'::dastak_v1.operational_pause_scope
  end;
  if exists (
    select 1
    from dastak_v1.operational_pause_controls control
    join public.service_zones zone on zone.id = control.service_zone_id
    where control.scope = v_scope and control.active and zone.active
      and extensions.st_covers(
        zone.boundary,
        extensions.st_setsrid(extensions.st_makepoint(
          (new.delivery_address ->> 'longitude')::double precision,
          (new.delivery_address ->> 'latitude')::double precision
        ), 4326)
      )
  ) then
    raise exception using errcode = '55000', message = 'ORDERING_PAUSED',
      detail = v_scope::text || ' is paused for this service zone.';
  end if;
  return new;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'invalid delivery coordinates';
end;
$$;

create trigger order_context_snapshots_enforce_zone_pause
after insert on dastak_v1.order_context_snapshots
for each row execute function dastak_v1.enforce_zone_ordering_pause();

create function dastak_v1.enforce_branch_opportunity_pause()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from dastak_v1.operational_pause_controls control
    where control.scope = 'MERCHANT_BRANCH'
      and control.branch_id = new.branch_id and control.active
  ) then
    if tg_op = 'INSERT' then return null; end if;
    if old.status = 'OFFERED' and new.status in ('SELECTED', 'PROVISIONALLY_ACCEPTED') then
      raise exception using errcode = '55000', message = 'MERCHANT_BRANCH_PAUSED';
    end if;
  end if;
  return new;
end;
$$;

create trigger merchant_opportunities_enforce_emergency_pause
before insert or update of status on dastak_v1.merchant_opportunities
for each row execute function dastak_v1.enforce_branch_opportunity_pause();

create function dastak_v1.enforce_rider_assignment_pause()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from dastak_v1.operational_pause_controls control
    where control.scope = 'RIDER_ASSIGNMENTS'
      and control.rider_id = new.rider_id and control.active
  ) then
    if tg_op = 'INSERT' then return null; end if;
    if old.status = 'OFFERED' and new.status = 'ACCEPTED' then
      raise exception using errcode = '55000', message = 'RIDER_ASSIGNMENTS_PAUSED';
    end if;
  end if;
  return new;
end;
$$;

create trigger delivery_offers_enforce_rider_pause
before insert or update of status on dastak_v1.delivery_offers
for each row execute function dastak_v1.enforce_rider_assignment_pause();

create function dastak_v1_api.process_rider_escalations(
  p_limit integer default 100,
  p_now timestamptz default pg_catalog.clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_configuration jsonb;
  v_stall integer;
  v_unresponsive integer;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_stalled integer := 0;
  v_unresponsive_count integer := 0;
  v_recovery integer := 0;
  v_has_custody boolean;
begin
  if p_limit is null or p_limit not between 1 and 500 then
    raise exception using errcode = '22023', message = 'invalid rider escalation batch limit';
  end if;
  v_configuration := dastak_v1_api.rider_escalation_configuration();
  v_stall := (v_configuration ->> 'stallThresholdSeconds')::integer;
  v_unresponsive := (v_configuration ->> 'unresponsiveThresholdSeconds')::integer;

  for v_mission in
    select mission.*
    from dastak_v1.delivery_missions mission
    where mission.assigned_rider_id is not null
      and mission.status in (
        'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
        'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED'
      )
      and (
        mission.rider_last_progress_at <= p_now - pg_catalog.make_interval(secs => v_stall)
        or mission.rider_last_contact_at <= p_now - pg_catalog.make_interval(secs => v_unresponsive)
      )
    order by least(mission.rider_last_progress_at, mission.rider_last_contact_at), mission.id
    limit p_limit
    for update skip locked
  loop
    v_has_custody := dastak_v1_api.mission_has_package_custody(v_mission.id);
    if v_mission.rider_last_contact_at <=
      p_now - pg_catalog.make_interval(secs => v_unresponsive) then
      if v_has_custody then
        update dastak_v1.delivery_missions mission
        set status = 'DELIVERY_RECOVERY', escalation_state = 'DELIVERY_RECOVERY',
            unresponsive_detected_at = coalesce(mission.unresponsive_detected_at, p_now),
            escalated_at = p_now,
            escalation_reason = 'RIDER_UNRESPONSIVE_AFTER_CUSTODY',
            version = mission.version + 1
        where mission.id = v_mission.id
          and mission.status <> 'DELIVERY_RECOVERY'
        returning * into v_mission;
        v_recovery := v_recovery + 1;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, payload
        ) values (
          v_mission.id::text || ':RIDER_UNRESPONSIVE_RECOVERY:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'RIDER_UNRESPONSIVE_RECOVERY', pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'custodyStarted', true, 'detectedAt', p_now
          )
        );
      elsif v_mission.escalation_state not in ('UNRESPONSIVE', 'RELEASED_PRE_CUSTODY') then
        update dastak_v1.delivery_missions mission
        set escalation_state = 'UNRESPONSIVE',
            unresponsive_detected_at = coalesce(mission.unresponsive_detected_at, p_now),
            escalated_at = p_now, escalation_reason = 'RIDER_UNRESPONSIVE_PRE_CUSTODY',
            version = mission.version + 1
        where mission.id = v_mission.id returning * into v_mission;
        v_unresponsive_count := v_unresponsive_count + 1;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, payload
        ) values (
          v_mission.id::text || ':RIDER_UNRESPONSIVE:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'RIDER_UNRESPONSIVE', pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'custodyStarted', false, 'detectedAt', p_now
          )
        );
      end if;
    elsif v_mission.rider_last_progress_at <=
      p_now - pg_catalog.make_interval(secs => v_stall)
      and v_mission.escalation_state = 'NONE' then
      update dastak_v1.delivery_missions mission
      set escalation_state = 'STALLED',
          stall_detected_at = coalesce(mission.stall_detected_at, p_now),
          escalated_at = p_now, escalation_reason = 'RIDER_PROGRESS_STALLED',
          version = mission.version + 1
      where mission.id = v_mission.id returning * into v_mission;
      v_stalled := v_stalled + 1;
      insert into dastak_v1.domain_events_outbox (
        event_key, aggregate_type, aggregate_id, aggregate_version,
        event_type, payload
      ) values (
        v_mission.id::text || ':RIDER_STALLED:' || v_mission.version::text,
        'DELIVERY_MISSION', v_mission.id, v_mission.version,
        'RIDER_STALLED', pg_catalog.jsonb_build_object(
          'orderId', v_mission.order_id, 'missionId', v_mission.id,
          'detectedAt', p_now
        )
      );
    end if;
  end loop;
  return pg_catalog.jsonb_build_object(
    'stalled', v_stalled, 'unresponsive', v_unresponsive_count,
    'deliveryRecovery', v_recovery
  );
end;
$$;

create function dastak_v1_api.rider_heartbeat(
  p_actor_id uuid,
  p_mission_id uuid,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id and mission.assigned_rider_id = p_actor_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'mission not found'; end if;
  if v_mission.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'STALE_MISSION_VERSION';
  end if;
  if v_mission.status in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED') then
    raise exception using errcode = '55000', message = 'MISSION_NOT_ACTIVE';
  end if;
  update dastak_v1.delivery_missions mission
  set rider_last_contact_at = v_now,
      escalation_state = case when mission.escalation_state = 'STALLED'
        then 'NONE' else mission.escalation_state end,
      escalated_at = case when mission.escalation_state = 'STALLED'
        then null else mission.escalated_at end,
      escalation_reason = case when mission.escalation_state = 'STALLED'
        then null else mission.escalation_reason end,
      version = mission.version + 1
  where mission.id = v_mission.id returning * into v_mission;
  return pg_catalog.jsonb_build_object(
    'missionId', v_mission.id, 'version', v_mission.version,
    'lastContactAt', v_mission.rider_last_contact_at,
    'escalationState', v_mission.escalation_state
  );
end;
$$;

create function dastak_v1_api.manage_rider_escalation(
  p_actor_id uuid,
  p_mission_id uuid,
  p_action text,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'manageRiderEscalationV1';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_response jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.delivery.operations.manage'
  );
  if p_mission_id is null or p_action not in ('RELEASE_REMATCH', 'ENTER_DELIVERY_RECOVERY')
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 10 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid rider escalation action';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'missionId', p_mission_id, 'action', p_action,
    'reason', pg_catalog.btrim(p_reason), 'expectedVersion', p_expected_version
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
  select mission.* into v_mission from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'mission not found'; end if;
  if v_mission.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'STALE_MISSION_VERSION';
  end if;
  if p_action = 'RELEASE_REMATCH' then
    if v_mission.escalation_state not in ('STALLED', 'UNRESPONSIVE') then
      raise exception using errcode = '55000', message = 'MISSION_NOT_ESCALATED';
    end if;
    v_mission := dastak_v1_api.reopen_rider_search_after_release(
      v_mission.id, p_reason, p_actor_id, v_now
    );
  else
    if not dastak_v1_api.mission_has_package_custody(v_mission.id) then
      raise exception using errcode = '55000', message = 'PRE_CUSTODY_REMATCH_REQUIRED';
    end if;
    update dastak_v1.delivery_missions mission
    set status = 'DELIVERY_RECOVERY', escalation_state = 'DELIVERY_RECOVERY',
        escalated_at = v_now, escalation_reason = pg_catalog.btrim(p_reason),
        escalated_by = p_actor_id, version = mission.version + 1
    where mission.id = v_mission.id returning * into v_mission;
  end if;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'RIDER_ESCALATION_MANAGED', 'delivery_mission', v_mission.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_mission.order_id, 'action', p_action,
      'reason', pg_catalog.btrim(p_reason), 'custodyStarted',
      dastak_v1_api.mission_has_package_custody(v_mission.id)
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'missionId', v_mission.id, 'status', v_mission.status,
    'escalationState', v_mission.escalation_state, 'version', v_mission.version
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

create function dastak_v1_api.set_operational_pause(
  p_actor_id uuid,
  p_scope text,
  p_target_id uuid,
  p_active boolean,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'setOperationalPauseV1';
  v_scope dastak_v1.operational_pause_scope;
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_control dastak_v1.operational_pause_controls%rowtype;
  v_response jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.operational_safety.manage'
  );
  begin v_scope := p_scope::dastak_v1.operational_pause_scope;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid operational pause scope';
  end;
  if p_target_id is null or p_active is null or p_expected_version is null
    or p_expected_version < 0
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid operational pause';
  end if;
  if v_scope in ('ZONE_RETAIL', 'ZONE_FOOD', 'ZONE_MIXED') and not exists (
    select 1 from public.service_zones zone where zone.id = p_target_id
  ) then raise exception using errcode = 'P0002', message = 'service zone not found';
  elsif v_scope = 'MERCHANT_BRANCH' and not exists (
    select 1 from dastak_v1.merchant_branches branch where branch.id = p_target_id
  ) then raise exception using errcode = 'P0002', message = 'merchant branch not found';
  elsif v_scope = 'RIDER_ASSIGNMENTS' and not exists (
    select 1 from public.accounts account where account.id = p_target_id
  ) then raise exception using errcode = 'P0002', message = 'rider not found';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'scope', v_scope, 'targetId', p_target_id, 'active', p_active,
    'reason', pg_catalog.btrim(p_reason), 'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-operational-pause:' || v_scope::text || ':' || p_target_id::text, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select control.* into v_control
  from dastak_v1.operational_pause_controls control
  where control.scope = v_scope
    and control.service_zone_id is not distinct from case
      when v_scope in ('ZONE_RETAIL', 'ZONE_FOOD', 'ZONE_MIXED') then p_target_id else null end
    and control.branch_id is not distinct from case
      when v_scope = 'MERCHANT_BRANCH' then p_target_id else null end
    and control.rider_id is not distinct from case
      when v_scope = 'RIDER_ASSIGNMENTS' then p_target_id else null end
  for update;
  if found then
    if v_control.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'STALE_OPERATIONAL_PAUSE_VERSION';
    end if;
    if v_control.active is distinct from p_active then
      update dastak_v1.operational_pause_controls control
      set active = p_active, reason = pg_catalog.btrim(p_reason),
          activated_by = case when p_active then p_actor_id else control.activated_by end,
          activated_at = case when p_active then v_now else control.activated_at end,
          cleared_by = case when p_active then null else p_actor_id end,
          cleared_at = case when p_active then null else v_now end,
          version = control.version + 1
      where control.id = v_control.id returning * into v_control;
    end if;
  else
    if not p_active or p_expected_version <> 0 then
      raise exception using errcode = '40001', message = 'OPERATIONAL_PAUSE_NOT_FOUND';
    end if;
    insert into dastak_v1.operational_pause_controls (
      scope, service_zone_id, branch_id, rider_id,
      active, reason, activated_by, activated_at
    ) values (
      v_scope,
      case when v_scope in ('ZONE_RETAIL', 'ZONE_FOOD', 'ZONE_MIXED') then p_target_id end,
      case when v_scope = 'MERCHANT_BRANCH' then p_target_id end,
      case when v_scope = 'RIDER_ASSIGNMENTS' then p_target_id end,
      true, pg_catalog.btrim(p_reason), p_actor_id, v_now
    ) returning * into v_control;
  end if;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    case when p_active then 'OPERATIONAL_SCOPE_PAUSED' else 'OPERATIONAL_SCOPE_RESUMED' end,
    'operational_pause', v_control.id,
    pg_catalog.jsonb_build_object(
      'scope', v_scope, 'targetId', p_target_id,
      'reason', pg_catalog.btrim(p_reason), 'version', v_control.version
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_control.id::text || ':' || case when p_active then 'PAUSED:' else 'RESUMED:' end
      || v_control.version::text,
    'OPERATIONAL_PAUSE', v_control.id, v_control.version,
    case when p_active then 'OPERATIONAL_SCOPE_PAUSED' else 'OPERATIONAL_SCOPE_RESUMED' end,
    p_actor_id, pg_catalog.jsonb_build_object(
      'scope', v_scope, 'targetId', p_target_id, 'reason', pg_catalog.btrim(p_reason)
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'id', v_control.id, 'scope', v_control.scope,
    'targetId', p_target_id, 'active', v_control.active,
    'reason', v_control.reason, 'version', v_control.version,
    'updatedAt', v_control.updated_at
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_control.id
  );
  return v_response;
end;
$$;

create function dastak_v1_api.admin_operational_safety(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.orders.trace');
  return pg_catalog.jsonb_build_object(
    'permissions', pg_catalog.jsonb_build_object(
      'canManageRiderEscalations', dastak_v1_api.actor_has_platform_permission(
        p_actor_id, 'platform.delivery.operations.manage'
      ),
      'canManageOperationalPauses', dastak_v1_api.actor_has_platform_permission(
        p_actor_id, 'platform.operational_safety.manage'
      )
    ),
    'pauses', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', control.id, 'scope', control.scope,
        'targetId', coalesce(control.service_zone_id, control.branch_id, control.rider_id),
        'active', control.active, 'reason', control.reason,
        'activatedAt', control.activated_at, 'clearedAt', control.cleared_at,
        'version', control.version
      ) order by control.active desc, control.updated_at desc, control.id)
      from dastak_v1.operational_pause_controls control
    ), '[]'::jsonb),
    'riderEscalations', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'missionId', mission.id, 'orderId', mission.order_id,
        'displayOrderNumber', customer_order.display_order_number,
        'status', mission.status, 'riderId', mission.assigned_rider_id,
        'transportType', mission.assigned_transport_type,
        'lastContactAt', mission.rider_last_contact_at,
        'lastProgressAt', mission.rider_last_progress_at,
        'stallDetectedAt', mission.stall_detected_at,
        'unresponsiveDetectedAt', mission.unresponsive_detected_at,
        'escalationState', mission.escalation_state,
        'escalatedAt', mission.escalated_at,
        'escalationReason', mission.escalation_reason,
        'custodyStarted', dastak_v1_api.mission_has_package_custody(mission.id),
        'version', mission.version
      ) order by mission.escalated_at desc nulls last, mission.id)
      from dastak_v1.delivery_missions mission
      join dastak_v1.orders customer_order on customer_order.id = mission.order_id
      where mission.escalation_state <> 'NONE'
        and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
    ), '[]'::jsonb)
  );
end;
$$;

alter function dastak_v1_api.rider_mission_json(uuid, uuid)
  rename to rider_mission_json_step5;

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
begin
  v_result := dastak_v1_api.rider_mission_json_step5(p_rider_id, p_mission_id);
  select mission.* into v_mission from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id and mission.assigned_rider_id = p_rider_id;
  if not found then raise exception using errcode = 'P0002', message = 'mission not found'; end if;
  return v_result || pg_catalog.jsonb_build_object(
    'transportLoad', v_mission.transport_snapshot,
    'riderSafety', pg_catalog.jsonb_build_object(
      'lastContactAt', v_mission.rider_last_contact_at,
      'lastProgressAt', v_mission.rider_last_progress_at,
      'stallDetectedAt', v_mission.stall_detected_at,
      'unresponsiveDetectedAt', v_mission.unresponsive_detected_at,
      'escalationState', v_mission.escalation_state,
      'escalatedAt', v_mission.escalated_at,
      'escalationReason', v_mission.escalation_reason
    )
  );
end;
$$;

create function public.dastak_v1_rider_heartbeat(
  p_account_id uuid,
  p_mission_id uuid,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.rider_heartbeat(p_account_id, p_mission_id, p_expected_version);
$$;

create function public.dastak_v1_manage_rider_escalation(
  p_mission_id uuid,
  p_action text,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.manage_rider_escalation(
    auth.uid(), p_mission_id, p_action, p_reason,
    p_expected_version, p_idempotency_key
  );
$$;

create function public.dastak_v1_set_operational_pause(
  p_scope text,
  p_target_id uuid,
  p_active boolean,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.set_operational_pause(
    auth.uid(), p_scope, p_target_id, p_active, p_reason,
    p_expected_version, p_idempotency_key
  );
$$;

create function public.dastak_v1_admin_operational_safety()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_operational_safety(auth.uid());
$$;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'dastak-v1-rider-matching'
  loop perform cron.unschedule(v_job_id); end loop;
end;
$$;

select cron.schedule(
  'dastak-v1-rider-matching',
  '* * * * *',
  $cron$
    select dastak_v1_api.process_rider_matching_due_orders(100);
    select dastak_v1_api.process_rider_escalations(100);
  $cron$
);

revoke all on function dastak_v1.guard_operational_pause_control(),
  dastak_v1.is_valid_transport_load_profiles(jsonb),
  dastak_v1.is_valid_default_sku_logistics(jsonb),
  dastak_v1.guard_delivery_mission(),
  dastak_v1.enforce_zone_ordering_pause(),
  dastak_v1.enforce_branch_opportunity_pause(),
  dastak_v1.enforce_rider_assignment_pause(),
  dastak_v1.revalidate_mission_transport_after_packages(),
  dastak_v1.enforce_final_transport_before_pickup()
from public, anon, authenticated;

revoke all on function dastak_v1_api.order_transport_snapshot(uuid),
  dastak_v1_api.transport_load_snapshot(numeric,numeric,integer,numeric,boolean,jsonb),
  dastak_v1_api.rider_escalation_configuration(),
  dastak_v1_api.mission_has_package_custody(uuid),
  dastak_v1_api.reopen_rider_search_after_release(uuid,text,uuid,timestamptz),
  dastak_v1_api.process_rider_escalations(integer,timestamptz),
  dastak_v1_api.rider_heartbeat(uuid,uuid,bigint),
  dastak_v1_api.manage_rider_escalation(uuid,uuid,text,text,bigint,text),
  dastak_v1_api.set_operational_pause(uuid,text,uuid,boolean,text,bigint,text),
  dastak_v1_api.admin_operational_safety(uuid),
  dastak_v1_api.rider_mission_json_step5(uuid,uuid),
  dastak_v1_api.rider_mission_json(uuid,uuid)
from public, anon, authenticated, service_role;

revoke all on function public.dastak_v1_rider_heartbeat(uuid,uuid,bigint),
  public.dastak_v1_manage_rider_escalation(uuid,text,text,bigint,text),
  public.dastak_v1_set_operational_pause(text,uuid,boolean,text,bigint,text),
  public.dastak_v1_admin_operational_safety()
from public, anon, authenticated, service_role;

grant execute on function dastak_v1_api.order_transport_snapshot(uuid),
  dastak_v1_api.transport_load_snapshot(numeric,numeric,integer,numeric,boolean,jsonb),
  dastak_v1_api.rider_escalation_configuration(),
  dastak_v1_api.mission_has_package_custody(uuid),
  dastak_v1_api.reopen_rider_search_after_release(uuid,text,uuid,timestamptz),
  dastak_v1_api.process_rider_escalations(integer,timestamptz),
  dastak_v1_api.rider_heartbeat(uuid,uuid,bigint),
  dastak_v1_api.manage_rider_escalation(uuid,uuid,text,text,bigint,text),
  dastak_v1_api.set_operational_pause(uuid,text,uuid,boolean,text,bigint,text),
  dastak_v1_api.admin_operational_safety(uuid),
  dastak_v1_api.rider_mission_json_step5(uuid,uuid),
  dastak_v1_api.rider_mission_json(uuid,uuid)
to service_role;

grant execute on function public.dastak_v1_manage_rider_escalation(uuid,text,text,bigint,text),
  public.dastak_v1_set_operational_pause(text,uuid,boolean,text,bigint,text),
  public.dastak_v1_admin_operational_safety()
to authenticated;

grant execute on function public.dastak_v1_rider_heartbeat(uuid,uuid,bigint)
to service_role;
