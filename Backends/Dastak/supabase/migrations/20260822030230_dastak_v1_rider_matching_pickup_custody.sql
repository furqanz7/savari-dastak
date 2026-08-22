-- Dastak V1 Step 4A: rider matching, assignment and atomic pickup custody.

create type dastak_v1.transport_type as enum (
  'WALKING', 'BICYCLE', 'MOTORBIKE', 'SCOOTER', 'AUTO', 'CAR'
);

create type dastak_v1.delivery_mission_status as enum (
  'SEARCHING_RIDER', 'ASSIGNED', 'EN_ROUTE_TO_PICKUPS',
  'PICKUP_IN_PROGRESS', 'ALL_PACKAGES_PICKED_UP',
  'OUT_FOR_DELIVERY', 'ARRIVED', 'DELIVERED',
  'REASSIGNING', 'DELIVERY_RECOVERY', 'CANCELLED'
);

create type dastak_v1.delivery_offer_status as enum (
  'OFFERED', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'CLOSED'
);

create type dastak_v1.delivery_stop_status as enum (
  'PENDING', 'ARRIVED', 'COMPLETED'
);

create type dastak_v1.verification_handoff_type as enum (
  'MERCHANT_TO_RIDER', 'RIDER_TO_CUSTOMER',
  'CUSTOMER_TO_RETURN_RIDER', 'RETURN_RIDER_TO_MERCHANT'
);

create type dastak_v1.verification_handoff_status as enum (
  'INACTIVE', 'ACTIVE', 'CONSUMED', 'BLOCKED', 'OVERRIDDEN'
);

create table dastak_v1.delivery_missions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  status dastak_v1.delivery_mission_status not null default 'SEARCHING_RIDER',
  assigned_rider_id uuid references public.accounts(id),
  assigned_transport_type dastak_v1.transport_type,
  transport_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(transport_snapshot) = 'object'
  ),
  pickup_count integer not null check (pickup_count >= 1),
  pool_round integer not null default 1 check (pool_round >= 1),
  search_started_at timestamptz not null default pg_catalog.now(),
  assigned_at timestamptz,
  first_package_picked_up_at timestamptz,
  all_packages_picked_up_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (assigned_rider_id is null) = (assigned_transport_type is null)
  ),
  check (
    status in ('SEARCHING_RIDER', 'REASSIGNING', 'CANCELLED')
    or (assigned_rider_id is not null and assigned_at is not null)
  ),
  check (
    (status = 'CANCELLED' and cancelled_at is not null and cancellation_reason is not null)
    or (status <> 'CANCELLED' and cancelled_at is null)
  )
);

create unique index delivery_missions_one_active_order_uidx
  on dastak_v1.delivery_missions (order_id)
  where status not in ('DELIVERED', 'CANCELLED');
create index delivery_missions_order_idx
  on dastak_v1.delivery_missions (order_id, created_at desc, id);
create unique index delivery_missions_one_active_rider_uidx
  on dastak_v1.delivery_missions (assigned_rider_id)
  where assigned_rider_id is not null
    and status in (
      'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
      'DELIVERY_RECOVERY'
    );
create index delivery_missions_status_idx
  on dastak_v1.delivery_missions (status, search_started_at, id);
create index delivery_missions_rider_history_idx
  on dastak_v1.delivery_missions (assigned_rider_id, created_at desc, id);

create table dastak_v1.delivery_offers (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  order_id uuid not null references dastak_v1.orders(id),
  rider_id uuid not null references public.accounts(id),
  transport_type dastak_v1.transport_type not null,
  pool_round integer not null check (pool_round >= 1),
  status dastak_v1.delivery_offer_status not null default 'OFFERED',
  distance_meters numeric not null check (distance_meters >= 0),
  offered_at timestamptz not null,
  respond_by timestamptz not null check (respond_by > offered_at),
  responded_at timestamptz,
  closed_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  unique (mission_id, rider_id, pool_round),
  check (
    (status = 'OFFERED' and responded_at is null)
    or (status <> 'OFFERED' and responded_at is not null)
  )
);

create unique index delivery_offers_one_accepted_mission_uidx
  on dastak_v1.delivery_offers (mission_id)
  where status = 'ACCEPTED';
create index delivery_offers_rider_open_idx
  on dastak_v1.delivery_offers (rider_id, respond_by, offered_at)
  where status = 'OFFERED';
create index delivery_offers_mission_round_idx
  on dastak_v1.delivery_offers (mission_id, pool_round, status, offered_at);
create index delivery_offers_order_idx
  on dastak_v1.delivery_offers (order_id, offered_at, id);

create table dastak_v1.delivery_stops (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  order_id uuid not null references dastak_v1.orders(id),
  fulfilment_id uuid not null unique references dastak_v1.fulfilments(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  stop_sequence integer not null check (stop_sequence >= 1),
  status dastak_v1.delivery_stop_status not null default 'PENDING',
  declared_package_count integer check (
    declared_package_count is null or declared_package_count >= 1
  ),
  arrived_at timestamptz,
  completed_at timestamptz,
  waiting_seconds integer check (waiting_seconds is null or waiting_seconds >= 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  unique (mission_id, stop_sequence),
  unique (id, mission_id),
  check (
    (status = 'PENDING' and arrived_at is null and completed_at is null)
    or (status = 'ARRIVED' and arrived_at is not null and completed_at is null)
    or (status = 'COMPLETED' and completed_at is not null)
  )
);

create index delivery_stops_mission_status_idx
  on dastak_v1.delivery_stops (mission_id, status, stop_sequence);
create index delivery_stops_order_idx
  on dastak_v1.delivery_stops (order_id, status, stop_sequence);
create index delivery_stops_branch_idx
  on dastak_v1.delivery_stops (branch_id, status);

create table dastak_v1.verification_handoffs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  fulfilment_id uuid references dastak_v1.fulfilments(id),
  handoff_type dastak_v1.verification_handoff_type not null,
  status dastak_v1.verification_handoff_status not null default 'INACTIVE',
  code_version integer not null default 1 check (code_version >= 1),
  code_digest bytea not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  activated_at timestamptz,
  consumed_at timestamptz,
  consumed_by uuid references public.accounts(id),
  blocked_at timestamptz,
  overridden_at timestamptz,
  overridden_by uuid references public.accounts(id),
  override_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (handoff_type = 'MERCHANT_TO_RIDER' and fulfilment_id is not null)
    or (handoff_type <> 'MERCHANT_TO_RIDER')
  ),
  check (
    (status = 'INACTIVE' and activated_at is null and consumed_at is null and blocked_at is null)
    or (status = 'ACTIVE' and activated_at is not null and consumed_at is null and blocked_at is null)
    or (status = 'CONSUMED' and activated_at is not null and consumed_at is not null and consumed_by is not null)
    or (status = 'BLOCKED' and activated_at is not null and blocked_at is not null)
    or (
      status = 'OVERRIDDEN' and overridden_at is not null
      and overridden_by is not null and override_reason is not null
    )
  )
);

create unique index verification_handoffs_pickup_fulfilment_uidx
  on dastak_v1.verification_handoffs (fulfilment_id)
  where handoff_type = 'MERCHANT_TO_RIDER';
create index verification_handoffs_fulfilment_idx
  on dastak_v1.verification_handoffs (fulfilment_id, handoff_type, status);
create unique index verification_handoffs_delivery_order_uidx
  on dastak_v1.verification_handoffs (order_id)
  where handoff_type = 'RIDER_TO_CUSTOMER';
create index verification_handoffs_order_idx
  on dastak_v1.verification_handoffs (order_id, handoff_type, status);
create index verification_handoffs_mission_idx
  on dastak_v1.verification_handoffs (mission_id, status, handoff_type);
create index verification_handoffs_consumed_by_idx
  on dastak_v1.verification_handoffs (consumed_by, consumed_at);
create index verification_handoffs_overridden_by_idx
  on dastak_v1.verification_handoffs (overridden_by, overridden_at);

create table dastak_v1.package_custody_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  fulfilment_id uuid not null references dastak_v1.fulfilments(id),
  package_id uuid not null references dastak_v1.packages(id),
  verification_handoff_id uuid not null references dastak_v1.verification_handoffs(id),
  from_owner_type dastak_v1.package_custody_owner_type not null,
  from_owner_id uuid not null,
  to_owner_type dastak_v1.package_custody_owner_type not null,
  to_owner_id uuid not null,
  transferred_by uuid not null references public.accounts(id),
  transferred_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  unique (package_id, verification_handoff_id)
);

create index package_custody_events_order_idx
  on dastak_v1.package_custody_events (order_id, transferred_at, id);
create index package_custody_events_mission_idx
  on dastak_v1.package_custody_events (mission_id, transferred_at, id);
create index package_custody_events_fulfilment_idx
  on dastak_v1.package_custody_events (fulfilment_id, transferred_at, id);
create index package_custody_events_verification_idx
  on dastak_v1.package_custody_events (verification_handoff_id);
create index package_custody_events_transferred_by_idx
  on dastak_v1.package_custody_events (transferred_by, transferred_at);

create table dastak_v1.delivery_problem_reports (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  reported_by uuid not null references public.accounts(id),
  mission_status_at_report dastak_v1.delivery_mission_status not null,
  custody_started boolean not null,
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 500
  ),
  reported_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);

create index delivery_problem_reports_mission_idx
  on dastak_v1.delivery_problem_reports (mission_id, reported_at, id);
create index delivery_problem_reports_order_idx
  on dastak_v1.delivery_problem_reports (order_id, reported_at, id);
create index delivery_problem_reports_reported_by_idx
  on dastak_v1.delivery_problem_reports (reported_by, reported_at);

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values
  (
    'delivery.rider_initial_pool_size', 'INTEGER',
    'Initial nearby eligible rider offer pool size.', null,
    '{"minimum":1}'::jsonb, true, true
  ),
  (
    'delivery.rider_pool_expansion', 'JSON',
    'Nearby rider pool radius and bounded expansion configuration.', null,
    '{}'::jsonb, true, true
  ),
  (
    'delivery.verification_invalid_attempt_limit', 'INTEGER',
    'Invalid in-app handoff attempts before the code is blocked.', null,
    '{"minimum":1}'::jsonb, true, true
  );

-- Preserve legacy `bike` records while allowing every locked V1 transport.
alter table private.delivery_partner_applications
  drop constraint delivery_partner_applications_delivery_method_check,
  drop constraint delivery_partner_v2_vehicle_contract;
alter table private.delivery_partner_applications
  add constraint delivery_partner_applications_delivery_method_check check (
    delivery_method in (
      'walking', 'bicycle', 'bike', 'motorbike', 'scooter', 'auto', 'car'
    )
  ),
  add constraint delivery_partner_v2_vehicle_contract check (
    verification_version = 1
    or (
      delivery_method in ('walking', 'bicycle')
      and vehicle_registration_number is null
      and vehicle_make_model is null
      and vehicle_evidence_object_path is null
    )
    or (
      delivery_method in ('bike', 'motorbike', 'scooter', 'auto', 'car')
      and vehicle_registration_number is not null
      and vehicle_make_model is not null
      and vehicle_evidence_object_path is not null
      and vehicle_evidence_object_path <> identity_evidence_object_path
    )
  );

alter table private.delivery_partner_profiles
  drop constraint delivery_partner_profiles_delivery_method_check;
alter table private.delivery_partner_profiles
  add constraint delivery_partner_profiles_delivery_method_check check (
    delivery_method in (
      'walking', 'bicycle', 'bike', 'motorbike', 'scooter', 'auto', 'car'
    )
  );

create or replace function private.enforce_delivery_partner_vehicle_approval()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'approved'
    and new.delivery_method in ('bike', 'motorbike', 'scooter', 'auto', 'car')
    and (
      new.verification_version < 2
      or new.vehicle_registration_number is null
      or new.vehicle_make_model is null
      or new.vehicle_evidence_object_path is null
    )
  then
    raise exception using
      errcode = '23514',
      message = 'Vehicle verification is required before approval.';
  end if;
  return new;
end;
$$;

create function dastak_v1.rider_transport_type(p_delivery_method text)
returns dastak_v1.transport_type
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_delivery_method
    when 'walking' then 'WALKING'::dastak_v1.transport_type
    when 'bicycle' then 'BICYCLE'::dastak_v1.transport_type
    when 'bike' then 'MOTORBIKE'::dastak_v1.transport_type
    when 'motorbike' then 'MOTORBIKE'::dastak_v1.transport_type
    when 'scooter' then 'SCOOTER'::dastak_v1.transport_type
    when 'auto' then 'AUTO'::dastak_v1.transport_type
    when 'car' then 'CAR'::dastak_v1.transport_type
    else null
  end;
$$;

create function dastak_v1.is_valid_rider_pool_expansion(p_value jsonb)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_typeof(p_value) = 'object'
    and p_value ?& array[
      'initialRadiusMeters', 'radiusStepMeters',
      'additionalRidersPerRound', 'maximumRounds'
    ]
    and pg_catalog.jsonb_typeof(p_value -> 'initialRadiusMeters') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'radiusStepMeters') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'additionalRidersPerRound') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'maximumRounds') = 'number'
    and p_value ->> 'initialRadiusMeters' ~ '^[1-9][0-9]*$'
    and p_value ->> 'radiusStepMeters' ~ '^[1-9][0-9]*$'
    and p_value ->> 'additionalRidersPerRound' ~ '^[1-9][0-9]*$'
    and p_value ->> 'maximumRounds' ~ '^[1-9][0-9]*$';
$$;

create function dastak_v1_api.rider_matching_configuration()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_initial_pool jsonb;
  v_offer_timeout jsonb;
  v_expansion jsonb;
  v_attempt_limit jsonb;
  v_transport_profiles jsonb;
begin
  v_initial_pool := dastak_v1_api.effective_setting_json(
    'delivery.rider_initial_pool_size'
  );
  v_offer_timeout := dastak_v1_api.effective_setting_json(
    'delivery.rider_offer_timeout_seconds'
  );
  v_expansion := dastak_v1_api.effective_setting_json(
    'delivery.rider_pool_expansion'
  );
  v_attempt_limit := dastak_v1_api.effective_setting_json(
    'delivery.verification_invalid_attempt_limit'
  );
  v_transport_profiles := dastak_v1_api.effective_setting_json(
    'delivery.transport_load_profiles'
  );

  if v_initial_pool is null
    or v_offer_timeout is null
    or v_expansion is null
    or v_attempt_limit is null
    or v_transport_profiles is null
    or not dastak_v1.validate_setting_value(
      'delivery.rider_initial_pool_size', v_initial_pool
    )
    or (v_initial_pool #>> '{}')::numeric > 2147483647
    or not dastak_v1.validate_setting_value(
      'delivery.rider_offer_timeout_seconds', v_offer_timeout
    )
    or (v_offer_timeout #>> '{}')::numeric > 2147483647
    or not dastak_v1.is_valid_rider_pool_expansion(v_expansion)
    or not dastak_v1.validate_setting_value(
      'delivery.verification_invalid_attempt_limit', v_attempt_limit
    )
    or (v_attempt_limit #>> '{}')::numeric > 2147483647
    or not dastak_v1.is_valid_transport_load_profiles(v_transport_profiles)
  then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Rider pool, offer, verification or transport configuration is missing or invalid.',
      hint = 'Configure explicit V1 rider pool, expansion, offer timeout, verification and transport load values.';
  end if;

  return pg_catalog.jsonb_build_object(
    'initialPoolSize', (v_initial_pool #>> '{}')::integer,
    'offerTimeoutSeconds', (v_offer_timeout #>> '{}')::integer,
    'poolExpansion', v_expansion,
    'verificationInvalidAttemptLimit', (v_attempt_limit #>> '{}')::integer,
    'transportLoadProfiles', v_transport_profiles
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Rider matching numeric configuration is invalid.';
end;
$$;

create function private.dastak_v1_handoff_code(
  p_handoff_id uuid,
  p_handoff_type dastak_v1.verification_handoff_type,
  p_version integer
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_bytes bytea;
  v_number bigint;
begin
  if p_handoff_id is null or p_handoff_type is null or p_version < 1 then
    raise exception 'invalid V1 handoff code context';
  end if;
  v_bytes := extensions.hmac(
    p_handoff_id::text || ':' || p_handoff_type::text || ':' || p_version::text,
    private.order_handoff_secret(),
    'sha256'
  );
  v_number := (
    pg_catalog.get_byte(v_bytes, 0)::bigint * 16777216
    + pg_catalog.get_byte(v_bytes, 1)::bigint * 65536
    + pg_catalog.get_byte(v_bytes, 2)::bigint * 256
    + pg_catalog.get_byte(v_bytes, 3)::bigint
  ) % 1000000;
  return pg_catalog.lpad(v_number::text, 6, '0');
end;
$$;

create function private.dastak_v1_handoff_digest(p_code text)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.hmac(
    p_code,
    private.order_handoff_secret(),
    'sha256'
  );
$$;

create function dastak_v1.guard_delivery_mission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
    or (old.status = 'ALL_PACKAGES_PICKED_UP' and new.status in (
      'OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'OUT_FOR_DELIVERY' and new.status in ('ARRIVED', 'DELIVERY_RECOVERY'))
    or (old.status = 'ARRIVED' and new.status in ('DELIVERED', 'DELIVERY_RECOVERY'))
    or (old.status = 'REASSIGNING' and new.status = 'SEARCHING_RIDER')
    or (old.status = 'DELIVERY_RECOVERY' and new.status in (
      'PICKUP_IN_PROGRESS', 'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY',
      'ARRIVED', 'DELIVERED'
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
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_delivery_offer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.mission_id is distinct from old.mission_id
    or new.order_id is distinct from old.order_id
    or new.rider_id is distinct from old.rider_id
    or new.transport_type is distinct from old.transport_type
    or new.pool_round is distinct from old.pool_round
    or new.distance_meters is distinct from old.distance_meters
    or new.offered_at is distinct from old.offered_at
    or new.respond_by is distinct from old.respond_by
    or new.created_at is distinct from old.created_at then
    raise exception 'delivery offer identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'delivery offer version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'OFFERED'
      and new.status in ('ACCEPTED', 'DECLINED', 'EXPIRED', 'CLOSED'))
    or (old.status = 'ACCEPTED' and new.status = 'CLOSED')
  ) then
    raise exception 'invalid delivery offer transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_delivery_stop()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.mission_id is distinct from old.mission_id
    or new.order_id is distinct from old.order_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.branch_id is distinct from old.branch_id
    or new.stop_sequence is distinct from old.stop_sequence
    or new.created_at is distinct from old.created_at then
    raise exception 'delivery stop identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'delivery stop version must increment exactly once';
  end if;
  if old.declared_package_count is not null
    and new.declared_package_count is distinct from old.declared_package_count then
    raise exception 'pickup package count cannot change';
  end if;
  if old.declared_package_count is null
    and new.declared_package_count is not null
    and not exists (
      select 1 from dastak_v1.fulfilments fulfilment
      where fulfilment.id = new.fulfilment_id
        and fulfilment.package_count = new.declared_package_count
    ) then
    raise exception 'pickup package count must match the fulfilment declaration';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'PENDING' and new.status in ('ARRIVED', 'COMPLETED'))
    or (old.status = 'ARRIVED' and new.status in ('PENDING', 'COMPLETED'))
  ) then
    raise exception 'invalid delivery stop transition: % -> %', old.status, new.status;
  end if;
  if old.status = 'ARRIVED' and new.status = 'PENDING' and not exists (
    select 1 from dastak_v1.delivery_missions mission
    where mission.id = new.mission_id and mission.status = 'REASSIGNING'
  ) then
    raise exception 'an arrived pickup may reset only during pre-custody reassignment';
  end if;
  if new.status = 'COMPLETED' and old.status <> 'COMPLETED' and not exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    where fulfilment.id = new.fulfilment_id
      and fulfilment.status = 'PICKED_UP'
  ) then
    raise exception 'pickup stop completion requires a Picked Up fulfilment';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_verification_handoff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.mission_id is distinct from old.mission_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.handoff_type is distinct from old.handoff_type
    or new.code_version is distinct from old.code_version
    or new.code_digest is distinct from old.code_digest
    or new.created_at is distinct from old.created_at then
    raise exception 'verification handoff identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'verification handoff version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'INACTIVE' and new.status = 'ACTIVE')
    or (old.status = 'ACTIVE' and new.status in ('CONSUMED', 'BLOCKED', 'OVERRIDDEN'))
    or (old.status = 'BLOCKED' and new.status = 'OVERRIDDEN')
  ) then
    raise exception 'invalid verification transition: % -> %', old.status, new.status;
  end if;
  if old.status in ('CONSUMED', 'OVERRIDDEN') then
    raise exception 'completed verification history is immutable';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger delivery_missions_guard
before update on dastak_v1.delivery_missions
for each row execute function dastak_v1.guard_delivery_mission();
create trigger delivery_missions_no_delete
before delete on dastak_v1.delivery_missions
for each row execute function dastak_v1.reject_delete();
create trigger delivery_offers_guard
before update on dastak_v1.delivery_offers
for each row execute function dastak_v1.guard_delivery_offer();
create trigger delivery_offers_no_delete
before delete on dastak_v1.delivery_offers
for each row execute function dastak_v1.reject_delete();
create trigger delivery_stops_guard
before update on dastak_v1.delivery_stops
for each row execute function dastak_v1.guard_delivery_stop();
create trigger delivery_stops_no_delete
before delete on dastak_v1.delivery_stops
for each row execute function dastak_v1.reject_delete();
create trigger verification_handoffs_guard
before update on dastak_v1.verification_handoffs
for each row execute function dastak_v1.guard_verification_handoff();
create trigger verification_handoffs_no_delete
before delete on dastak_v1.verification_handoffs
for each row execute function dastak_v1.reject_delete();
create trigger package_custody_events_immutable
before update or delete on dastak_v1.package_custody_events
for each row execute function dastak_v1.reject_mutation();
create trigger delivery_problem_reports_immutable
before update or delete on dastak_v1.delivery_problem_reports
for each row execute function dastak_v1.reject_mutation();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'delivery_missions', 'delivery_offers', 'delivery_stops',
    'verification_handoffs', 'package_custody_events',
    'delivery_problem_reports'
  ] loop
    execute pg_catalog.format(
      'alter table dastak_v1.%I enable row level security', v_table
    );
  end loop;
end;
$$;

revoke all on table dastak_v1.delivery_missions from public, anon, authenticated;
revoke all on table dastak_v1.delivery_offers from public, anon, authenticated;
revoke all on table dastak_v1.delivery_stops from public, anon, authenticated;
revoke all on table dastak_v1.verification_handoffs from public, anon, authenticated;
revoke all on table dastak_v1.package_custody_events from public, anon, authenticated;
revoke all on table dastak_v1.delivery_problem_reports from public, anon, authenticated;
grant select, insert, update on table dastak_v1.delivery_missions to service_role;
grant select, insert, update on table dastak_v1.delivery_offers to service_role;
grant select, insert, update on table dastak_v1.delivery_stops to service_role;
grant select, insert, update on table dastak_v1.verification_handoffs to service_role;
grant select, insert on table dastak_v1.package_custody_events to service_role;
grant select, insert on table dastak_v1.delivery_problem_reports to service_role;

create function dastak_v1_api.create_rider_offer_pool(
  p_mission_id uuid,
  p_now timestamptz default pg_catalog.clock_timestamp()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_configuration jsonb;
  v_expansion jsonb;
  v_pool_size integer;
  v_radius_meters integer;
  v_offer_timeout integer;
  v_inserted integer;
  v_rider_ids jsonb;
begin
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'delivery mission not found';
  end if;
  if v_mission.status <> 'SEARCHING_RIDER' then
    return 0;
  end if;

  v_configuration := dastak_v1_api.rider_matching_configuration();
  v_expansion := v_configuration -> 'poolExpansion';
  if v_mission.pool_round > (v_expansion ->> 'maximumRounds')::integer then
    return 0;
  end if;
  v_pool_size := case
    when v_mission.pool_round = 1 then
      (v_configuration ->> 'initialPoolSize')::integer
    else (v_expansion ->> 'additionalRidersPerRound')::integer
  end;
  v_radius_meters := (v_expansion ->> 'initialRadiusMeters')::integer
    + (v_mission.pool_round - 1) * (v_expansion ->> 'radiusStepMeters')::integer;
  v_offer_timeout := (v_configuration ->> 'offerTimeoutSeconds')::integer;

  with candidate as (
    select
      availability.account_id as rider_id,
      dastak_v1.rider_transport_type(profile.delivery_method) as transport_type,
      nearest.distance_meters
    from private.delivery_partner_availability availability
    join private.delivery_partner_profiles profile
      on profile.account_id = availability.account_id
    join private.account_memberships membership
      on membership.account_id = availability.account_id
     and membership.role = 'dastak_partner'
     and membership.approved_at is not null
     and (
       membership.suspended_until is null
       or membership.suspended_until <= p_now
     )
    cross join lateral (
      select min(extensions.st_distance(
        availability.location::extensions.geography,
        branch.location::extensions.geography
      )) as distance_meters
      from dastak_v1.delivery_stops stop
      join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
      where stop.mission_id = v_mission.id
        and branch.location is not null
        and availability.service_zone_id = branch.service_zone_id
    ) nearest
    where availability.status = 'online'
      and availability.available_until > p_now
      and availability.location is not null
      and dastak_v1.rider_transport_type(profile.delivery_method) is not null
      and (v_mission.transport_snapshot -> 'eligibleTransportTypes') @>
        pg_catalog.to_jsonb(array[
          dastak_v1.rider_transport_type(profile.delivery_method)::text
        ])
      and nearest.distance_meters is not null
      and nearest.distance_meters <= v_radius_meters
      and not exists (
        select 1 from dastak_v1.delivery_missions active_mission
        where active_mission.assigned_rider_id = availability.account_id
          and active_mission.status in (
            'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
            'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
            'DELIVERY_RECOVERY'
          )
      )
      and not exists (
        select 1 from dastak_v1.delivery_offers prior_offer
        where prior_offer.mission_id = v_mission.id
          and prior_offer.rider_id = availability.account_id
      )
    order by nearest.distance_meters, availability.account_id
    limit v_pool_size
  ), inserted as (
    insert into dastak_v1.delivery_offers (
      mission_id, order_id, rider_id, transport_type, pool_round,
      status, distance_meters, offered_at, respond_by
    )
    select
      v_mission.id, v_mission.order_id, candidate.rider_id,
      candidate.transport_type, v_mission.pool_round, 'OFFERED',
      candidate.distance_meters, p_now,
      p_now + pg_catalog.make_interval(secs => v_offer_timeout)
    from candidate
    returning rider_id
  )
  select count(*), coalesce(
    pg_catalog.jsonb_agg(inserted.rider_id order by inserted.rider_id), '[]'::jsonb
  ) into v_inserted, v_rider_ids
  from inserted;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_mission.id::text || ':RIDER_POOL_OPENED:' || v_mission.version::text,
    'DELIVERY_MISSION', v_mission.id, v_mission.version,
    case when v_inserted > 0 then 'RIDER_POOL_OPENED' else 'RIDER_POOL_EMPTY' end,
    pg_catalog.jsonb_build_object(
      'orderId', v_mission.order_id,
      'missionId', v_mission.id,
      'poolRound', v_mission.pool_round,
      'radiusMeters', v_radius_meters,
      'respondBy', p_now + pg_catalog.make_interval(secs => v_offer_timeout),
      'riderIds', v_rider_ids
    )
  );
  return v_inserted;
end;
$$;

create function dastak_v1_api.ensure_delivery_mission(
  p_order_id uuid,
  p_now timestamptz default pg_catalog.clock_timestamp()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_existing_id uuid;
  v_eligibility jsonb;
  v_transport jsonb;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_pickup_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-delivery:' || p_order_id::text, 0)
  );

  select mission.id into v_existing_id
  from dastak_v1.delivery_missions mission
  where mission.order_id = p_order_id
    and mission.status not in ('DELIVERED', 'CANCELLED')
  order by mission.created_at desc
  limit 1;
  if found then
    return v_existing_id;
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;
  if v_order.status <> 'PREPARING' then
    raise exception using errcode = '55000', message = 'ORDER_NOT_RIDER_MATCHABLE';
  end if;

  v_eligibility := dastak_v1_api.order_rider_match_eligibility(p_order_id, p_now);
  if not coalesce((v_eligibility ->> 'eligible')::boolean, false) then
    raise exception using errcode = '55000', message = 'ORDER_NOT_RIDER_MATCH_ELIGIBLE';
  end if;

  perform dastak_v1_api.rider_matching_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(p_order_id);
  if not coalesce((v_transport ->> 'feasible')::boolean, false)
    or pg_catalog.jsonb_array_length(
      coalesce(v_transport -> 'eligibleTransportTypes', '[]'::jsonb)
    ) = 0 then
    raise exception using
      errcode = '55000',
      message = 'ORDER_TRANSPORT_INVARIANT_VIOLATION',
      detail = 'A paid secured order has no capable configured transport.';
  end if;

  select count(*) into v_pickup_count
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id
    and fulfilment.status in ('PREPARING', 'READY');
  if v_pickup_count < 1 then
    raise exception using errcode = '55000', message = 'ORDER_FULFILMENT_INVARIANT_VIOLATION';
  end if;

  insert into dastak_v1.delivery_missions (
    order_id, status, transport_snapshot, pickup_count,
    pool_round, search_started_at
  ) values (
    p_order_id, 'SEARCHING_RIDER', v_transport, v_pickup_count, 1, p_now
  ) returning * into v_mission;

  insert into dastak_v1.delivery_stops (
    mission_id, order_id, fulfilment_id, branch_id, stop_sequence,
    status, declared_package_count
  )
  select
    v_mission.id, p_order_id, fulfilment.id, fulfilment.branch_id,
    row_number() over (
      order by
        case when fulfilment.status = 'READY' then 0 else 1 end,
        fulfilment.estimated_ready_at,
        fulfilment.branch_id,
        fulfilment.id
    )::integer,
    'PENDING', fulfilment.package_count
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id
    and fulfilment.status in ('PREPARING', 'READY')
  order by
    case when fulfilment.status = 'READY' then 0 else 1 end,
    fulfilment.estimated_ready_at,
    fulfilment.branch_id,
    fulfilment.id;

  with handoff_source as (
    select
      gen_random_uuid() as id,
      fulfilment.id as fulfilment_id,
      fulfilment.status
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = p_order_id
      and fulfilment.status in ('PREPARING', 'READY')
    order by fulfilment.id
  )
  insert into dastak_v1.verification_handoffs (
    id, order_id, mission_id, fulfilment_id, handoff_type, status,
    code_version, code_digest, activated_at
  )
  select
    source.id, p_order_id, v_mission.id, source.fulfilment_id,
    'MERCHANT_TO_RIDER',
    case when source.status = 'READY'
      then 'ACTIVE'::dastak_v1.verification_handoff_status
      else 'INACTIVE'::dastak_v1.verification_handoff_status
    end,
    1,
    private.dastak_v1_handoff_digest(private.dastak_v1_handoff_code(
      source.id, 'MERCHANT_TO_RIDER', 1
    )),
    case when source.status = 'READY' then p_now else null end
  from handoff_source source;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_mission.id::text || ':DELIVERY_MISSION_CREATED:1',
    'DELIVERY_MISSION', v_mission.id, 1, 'DELIVERY_MISSION_CREATED',
    pg_catalog.jsonb_build_object(
      'orderId', p_order_id,
      'missionId', v_mission.id,
      'pickupCount', v_pickup_count,
      'transport', v_transport,
      'riderMatchEligibility', v_eligibility
    )
  );
  perform dastak_v1_api.create_rider_offer_pool(v_mission.id, p_now);
  return v_mission.id;
end;
$$;

create function dastak_v1_api.expand_rider_pool_if_due(
  p_mission_id uuid,
  p_now timestamptz default pg_catalog.clock_timestamp()
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_configuration jsonb;
  v_maximum_rounds integer;
begin
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  if not found or v_mission.status <> 'SEARCHING_RIDER' then
    return false;
  end if;
  v_configuration := dastak_v1_api.rider_matching_configuration();
  v_maximum_rounds := (
    v_configuration -> 'poolExpansion' ->> 'maximumRounds'
  )::integer;

  if exists (
    select 1 from dastak_v1.delivery_offers offer
    where offer.mission_id = v_mission.id
      and offer.status = 'OFFERED'
      and offer.respond_by > p_now
  ) then
    return false;
  end if;
  if not exists (
    select 1 from dastak_v1.delivery_offers offer
    where offer.mission_id = v_mission.id
  ) and v_mission.updated_at + pg_catalog.make_interval(
    secs => (v_configuration ->> 'offerTimeoutSeconds')::integer
  ) > p_now then
    return false;
  end if;

  update dastak_v1.delivery_offers offer
  set status = 'EXPIRED', responded_at = p_now,
      closed_reason = 'OFFER_WINDOW_EXPIRED', version = offer.version + 1
  where offer.mission_id = v_mission.id
    and offer.status = 'OFFERED';

  if v_mission.pool_round >= v_maximum_rounds then
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, payload
    ) values (
      v_mission.id::text || ':RIDER_SEARCH_EXHAUSTED:' || v_mission.version::text,
      'DELIVERY_MISSION', v_mission.id, v_mission.version,
      'RIDER_SEARCH_EXHAUSTED',
      pg_catalog.jsonb_build_object(
        'orderId', v_mission.order_id,
        'missionId', v_mission.id,
        'poolRound', v_mission.pool_round
      )
    ) on conflict (event_key) do nothing;
    return false;
  end if;

  update dastak_v1.delivery_missions mission
  set pool_round = mission.pool_round + 1,
      version = mission.version + 1
  where mission.id = v_mission.id
  returning * into v_mission;
  perform dastak_v1_api.create_rider_offer_pool(v_mission.id, p_now);
  return true;
end;
$$;

create function dastak_v1_api.process_rider_matching_due_orders(
  p_limit integer default 100,
  p_now timestamptz default pg_catalog.clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_mission_id uuid;
  v_started integer := 0;
  v_expanded integer := 0;
begin
  perform dastak_v1_api.rider_matching_configuration();
  if p_limit is null or p_limit not between 1 and 500 then
    raise exception using errcode = '22023', message = 'invalid rider matching batch limit';
  end if;

  for v_order_id in
    select customer_order.id
    from dastak_v1.orders customer_order
    where customer_order.status = 'PREPARING'
      and not exists (
        select 1 from dastak_v1.delivery_missions mission
        where mission.order_id = customer_order.id
          and mission.status not in ('DELIVERED', 'CANCELLED')
      )
      and (
        dastak_v1_api.order_rider_match_eligibility(
          customer_order.id, p_now
        ) ->> 'eligible'
      )::boolean
    order by customer_order.paid_at, customer_order.id
    limit p_limit
    for update skip locked
  loop
    perform dastak_v1_api.ensure_delivery_mission(v_order_id, p_now);
    v_started := v_started + 1;
  end loop;

  for v_mission_id in
    select mission.id
    from dastak_v1.delivery_missions mission
    where mission.status = 'SEARCHING_RIDER'
    order by mission.updated_at, mission.id
    limit p_limit
    for update skip locked
  loop
    if dastak_v1_api.expand_rider_pool_if_due(v_mission_id, p_now) then
      v_expanded := v_expanded + 1;
    end if;
  end loop;

  return pg_catalog.jsonb_build_object(
    'startedMissions', v_started,
    'expandedPools', v_expanded,
    'processedAt', p_now
  );
end;
$$;

create function dastak_v1_api.rider_offer_json(
  p_rider_id uuid,
  p_offer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_offer dastak_v1.delivery_offers%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
begin
  select offer.* into v_offer
  from dastak_v1.delivery_offers offer
  where offer.id = p_offer_id
    and offer.rider_id = p_rider_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'delivery offer not found';
  end if;
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission where mission.id = v_offer.mission_id;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order where customer_order.id = v_offer.order_id;

  return pg_catalog.jsonb_build_object(
    'id', v_offer.id,
    'missionId', v_offer.mission_id,
    'displayOrderNumber', v_order.display_order_number,
    'status', v_offer.status,
    'poolRound', v_offer.pool_round,
    'transportType', v_offer.transport_type,
    'distanceMeters', v_offer.distance_meters,
    'offeredAt', v_offer.offered_at,
    'respondBy', v_offer.respond_by,
    'secondsRemaining', greatest(0, pg_catalog.ceil(extract(epoch from (
      v_offer.respond_by - pg_catalog.clock_timestamp()
    )))::integer),
    'pickupCount', v_mission.pickup_count,
    'orderLoad', pg_catalog.jsonb_build_object(
      'totalWeightGrams', v_mission.transport_snapshot -> 'totalWeightGrams',
      'totalVolumeCubicMillimetres',
        v_mission.transport_snapshot -> 'totalVolumeCubicMillimetres',
      'longestSideMillimetres',
        v_mission.transport_snapshot -> 'longestSideMillimetres',
      'containsBulky', v_mission.transport_snapshot -> 'containsBulky',
      'eligibleTransportTypes',
        v_mission.transport_snapshot -> 'eligibleTransportTypes'
    ),
    'pickupStops', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', stop.id,
        'sequence', stop.stop_sequence,
        'ready', fulfilment.status in ('READY', 'PICKED_UP'),
        'estimatedReadyAt', fulfilment.estimated_ready_at,
        'branch', pg_catalog.jsonb_build_object(
          'displayName', branch.display_name,
          'address', branch.address_snapshot,
          'location', case when branch.location is not null then
            pg_catalog.jsonb_build_object(
              'latitude', extensions.st_y(branch.location),
              'longitude', extensions.st_x(branch.location)
            ) else null end
        )
      ) order by
        case when fulfilment.status in ('READY', 'PICKED_UP') then 0 else 1 end,
        stop.stop_sequence)
      from dastak_v1.delivery_stops stop
      join dastak_v1.fulfilments fulfilment on fulfilment.id = stop.fulfilment_id
      join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
      where stop.mission_id = v_mission.id
    ), '[]'::jsonb)
  );
end;
$$;

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
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
begin
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
    and mission.assigned_rider_id = p_rider_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'delivery mission not found';
  end if;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order where customer_order.id = v_mission.order_id;

  return pg_catalog.jsonb_build_object(
    'id', v_mission.id,
    'displayOrderNumber', v_order.display_order_number,
    'status', v_mission.status,
    'version', v_mission.version,
    'transportType', v_mission.assigned_transport_type,
    'pickupCount', v_mission.pickup_count,
    'assignedAt', v_mission.assigned_at,
    'firstPackagePickedUpAt', v_mission.first_package_picked_up_at,
    'allPackagesPickedUpAt', v_mission.all_packages_picked_up_at,
    'canCancelBeforePickup', v_mission.first_package_picked_up_at is null
      and v_mission.status in ('ASSIGNED', 'EN_ROUTE_TO_PICKUPS'),
    'mustUseDeliveryRecovery', v_mission.first_package_picked_up_at is not null,
    'orderLoad', v_mission.transport_snapshot,
    'pickupStops', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', stop.id,
        'sequence', stop.stop_sequence,
        'status', stop.status,
        'ready', fulfilment.status in ('READY', 'PICKED_UP'),
        'runningLate', fulfilment.status = 'PREPARING'
          and pg_catalog.clock_timestamp() > fulfilment.estimated_ready_at,
        'estimatedReadyAt', fulfilment.estimated_ready_at,
        'actualReadyAt', fulfilment.actual_ready_at,
        'packageCount', stop.declared_package_count,
        'arrivedAt', stop.arrived_at,
        'waitingSeconds', case
          when stop.status = 'ARRIVED' then greatest(0, pg_catalog.floor(extract(epoch from (
            pg_catalog.clock_timestamp() - stop.arrived_at
          )))::integer)
          else coalesce(stop.waiting_seconds, 0)
        end,
        'branch', pg_catalog.jsonb_build_object(
          'id', branch.id,
          'displayName', branch.display_name,
          'address', branch.address_snapshot,
          'location', case when branch.location is not null then
            pg_catalog.jsonb_build_object(
              'latitude', extensions.st_y(branch.location),
              'longitude', extensions.st_x(branch.location)
            ) else null end
        )
      ) order by
        case
          when stop.status = 'COMPLETED' then 2
          when fulfilment.status in ('READY', 'PICKED_UP') then 0
          else 1
        end,
        stop.stop_sequence)
      from dastak_v1.delivery_stops stop
      join dastak_v1.fulfilments fulfilment on fulfilment.id = stop.fulfilment_id
      join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
      where stop.mission_id = v_mission.id
    ), '[]'::jsonb)
  );
end;
$$;

create function dastak_v1_api.delivery_partner_snapshot(p_rider_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_offer_id uuid;
  v_mission_id uuid;
begin
  if not exists (
    select 1
    from private.account_memberships membership
    join private.delivery_partner_profiles profile
      on profile.account_id = membership.account_id
    where membership.account_id = p_rider_id
      and membership.role = 'dastak_partner'
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.clock_timestamp()
      )
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select mission.id into v_mission_id
  from dastak_v1.delivery_missions mission
  where mission.assigned_rider_id = p_rider_id
    and mission.status in (
      'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
      'DELIVERY_RECOVERY'
    )
  order by mission.assigned_at desc, mission.id
  limit 1;

  if v_mission_id is null then
    select offer.id into v_offer_id
    from dastak_v1.delivery_offers offer
    join dastak_v1.delivery_missions mission on mission.id = offer.mission_id
    where offer.rider_id = p_rider_id
      and offer.status = 'OFFERED'
      and offer.respond_by > pg_catalog.clock_timestamp()
      and mission.status = 'SEARCHING_RIDER'
    order by offer.respond_by, offer.offered_at, offer.id
    limit 1;
  end if;

  return pg_catalog.jsonb_build_object(
    'offer', case when v_offer_id is null then null
      else dastak_v1_api.rider_offer_json(p_rider_id, v_offer_id) end,
    'currentMission', case when v_mission_id is null then null
      else dastak_v1_api.rider_mission_json(p_rider_id, v_mission_id) end
  );
end;
$$;

create function public.dastak_v1_delivery_partner_snapshot(p_account_id uuid)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
  response_status := 200;
  return next;
exception
  when insufficient_privilege then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved delivery partner account is required.'
      )
    );
    response_status := 403;
    return next;
end;
$$;

create function public.dastak_v1_accept_delivery_offer(
  p_account_id uuid,
  p_offer_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_command constant text := 'acceptDeliveryOfferV1';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_offer dastak_v1.delivery_offers%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_mission_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_delivery_method text;
  v_transport_type dastak_v1.transport_type;
  v_transport jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if p_account_id is null or p_offer_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200
    or nullif(pg_catalog.btrim(p_request_digest), '') is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The rider acceptance is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;
  v_request_hash := extensions.digest(p_request_digest, 'sha256');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_account_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_account_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with another request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-rider:' || p_account_id::text, 0)
  );
  select offer.mission_id into v_mission_id
  from dastak_v1.delivery_offers offer where offer.id = p_offer_id;
  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'offer_not_found', 'message', 'This rider offer is unavailable.'
      )
    );
    response_status := 404;
  else
    select mission.* into v_mission
    from dastak_v1.delivery_missions mission
    where mission.id = v_mission_id
    for update;
    select customer_order.* into v_order
    from dastak_v1.orders customer_order
    where customer_order.id = v_mission.order_id
    for update;
    perform 1 from dastak_v1.delivery_offers offer
    where offer.mission_id = v_mission.id
    order by offer.id
    for update;
    select offer.* into v_offer
    from dastak_v1.delivery_offers offer where offer.id = p_offer_id;

    select profile.delivery_method into v_delivery_method
    from private.delivery_partner_profiles profile
    join private.account_memberships membership
      on membership.account_id = profile.account_id
     and membership.role = 'dastak_partner'
     and membership.approved_at is not null
     and (
       membership.suspended_until is null
       or membership.suspended_until <= v_now
     )
    join private.delivery_partner_availability availability
      on availability.account_id = profile.account_id
     and availability.status = 'online'
     and availability.available_until > v_now
    where profile.account_id = p_account_id
    for share of profile, membership, availability;
    v_transport_type := dastak_v1.rider_transport_type(v_delivery_method);
    perform dastak_v1_api.rider_matching_configuration();
    v_transport := dastak_v1_api.order_transport_snapshot(v_mission.order_id);

    if v_offer.rider_id is distinct from p_account_id then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'offer_not_found', 'message', 'This rider offer is unavailable.'
        )
      );
      response_status := 404;
    elsif v_delivery_method is null then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'rider_not_eligible',
          'message', 'An online approved rider is required.'
        )
      );
      response_status := 403;
    elsif v_offer.status <> 'OFFERED'
      or v_offer.respond_by <= v_now
      or v_mission.status <> 'SEARCHING_RIDER' then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'offer_closed', 'message', 'Another rider already won or this offer expired.'
        )
      );
      response_status := 409;
    elsif v_transport_type is null
      or v_transport_type is distinct from v_offer.transport_type
      or not (v_transport -> 'eligibleTransportTypes') @>
        pg_catalog.to_jsonb(array[v_transport_type::text]) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'transport_incapable',
          'message', 'This rider transport cannot carry the complete order.'
        )
      );
      response_status := 409;
    elsif exists (
      select 1 from dastak_v1.delivery_missions active_mission
      where active_mission.assigned_rider_id = p_account_id
        and active_mission.status in (
          'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
          'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
          'DELIVERY_RECOVERY'
        )
    ) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'rider_has_active_mission',
          'message', 'Complete the active customer order before accepting another.'
        )
      );
      response_status := 409;
    else
      update dastak_v1.delivery_offers offer
      set status = 'ACCEPTED', responded_at = v_now,
          closed_reason = 'FIRST_VALID_ACCEPTANCE', version = offer.version + 1
      where offer.id = v_offer.id;
      update dastak_v1.delivery_offers offer
      set status = 'CLOSED', responded_at = v_now,
          closed_reason = 'COMPETING_OFFER_WON', version = offer.version + 1
      where offer.mission_id = v_mission.id
        and offer.id <> v_offer.id and offer.status = 'OFFERED';

      update dastak_v1.delivery_missions mission
      set status = 'ASSIGNED', assigned_rider_id = p_account_id,
          assigned_transport_type = v_transport_type, assigned_at = v_now,
          version = mission.version + 1
      where mission.id = v_mission.id
      returning * into v_mission;

      if v_order.status = 'PREPARING' then
        update dastak_v1.orders customer_order
        set status = 'PICKUP_IN_PROGRESS', version = customer_order.version + 1
        where customer_order.id = v_order.id
        returning * into v_order;
        insert into dastak_v1.order_state_journal (
          order_id, from_status, to_status, order_version,
          command_name, actor_id, metadata
        ) values (
          v_order.id, 'PREPARING', 'PICKUP_IN_PROGRESS', v_order.version,
          v_command, p_account_id,
          pg_catalog.jsonb_build_object(
            'missionId', v_mission.id, 'offerId', v_offer.id,
            'transportType', v_transport_type
          )
        );
      end if;

      insert into dastak_v1.domain_events_outbox (
        event_key, aggregate_type, aggregate_id, aggregate_version,
        event_type, actor_id, payload
      ) values (
        v_mission.id::text || ':RIDER_ASSIGNED:' || v_mission.version::text,
        'DELIVERY_MISSION', v_mission.id, v_mission.version,
        'RIDER_ASSIGNED', p_account_id,
        pg_catalog.jsonb_build_object(
          'orderId', v_mission.order_id, 'missionId', v_mission.id,
          'riderId', p_account_id, 'transportType', v_transport_type,
          'pickupCount', v_mission.pickup_count
        )
      );
      insert into dastak_v1.audit_events (
        actor_id, action, resource_type, resource_id, metadata
      ) values (
        p_account_id, 'RIDER_ASSIGNED', 'delivery_mission', v_mission.id,
        pg_catalog.jsonb_build_object(
          'orderId', v_mission.order_id, 'offerId', v_offer.id,
          'transportType', v_transport_type
        )
      );
      response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
      response_status := 200;
    end if;
  end if;

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_account_id, v_command, p_idempotency_key, v_request_hash,
    response_body, response_status, coalesce(v_mission.id, p_offer_id)
  );
  return next;
end;
$$;

create function public.dastak_v1_decline_delivery_offer(
  p_account_id uuid,
  p_offer_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_command constant text := 'declineDeliveryOfferV1';
  v_request_hash bytea := extensions.digest(p_request_digest, 'sha256');
  v_existing dastak_v1.idempotency_records%rowtype;
  v_offer dastak_v1.delivery_offers%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if p_account_id is null or p_offer_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or (p_reason is not null and pg_catalog.char_length(pg_catalog.btrim(p_reason)) > 300) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The rider decline is invalid.'
      )
    ); response_status := 400; return next; return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_account_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing from dastak_v1.idempotency_records record
  where record.actor_id = p_account_id and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      response_body := v_existing.response_body; response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict', 'message', 'The idempotency key conflicts.'
      )); response_status := 409;
    end if;
    return next; return;
  end if;

  select offer.* into v_offer from dastak_v1.delivery_offers offer
  where offer.id = p_offer_id for update;
  if not found or v_offer.rider_id is distinct from p_account_id then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'offer_not_found', 'message', 'This rider offer is unavailable.'
    )); response_status := 404;
  elsif v_offer.status <> 'OFFERED' then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'offer_closed', 'message', 'This rider offer is already closed.'
    )); response_status := 409;
  else
    update dastak_v1.delivery_offers offer
    set status = 'DECLINED', responded_at = v_now,
        closed_reason = coalesce(nullif(pg_catalog.btrim(p_reason), ''), 'RIDER_DECLINED'),
        version = offer.version + 1
    where offer.id = v_offer.id;
    perform dastak_v1_api.expand_rider_pool_if_due(v_offer.mission_id, v_now);
    response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
    response_status := 200;
  end if;
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_account_id, v_command, p_idempotency_key, v_request_hash,
    response_body, response_status, p_offer_id
  );
  return next;
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
    exception when invalid_text_representation then
      v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'MERCHANT_BRANCH'
      or new.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_id is null
      or new.picked_up_at is null
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

create or replace function dastak_v1.guard_fulfilment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_handoff_id uuid;
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.source_opportunity_id is distinct from old.source_opportunity_id
    or new.fulfilment_type is distinct from old.fulfilment_type
    or new.promised_prep_minutes is distinct from old.promised_prep_minutes
    or new.committed_at is distinct from old.committed_at
    or new.created_at is distinct from old.created_at then
    raise exception 'fulfilment commitment identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'fulfilment version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'RESERVED_PREPAYMENT' and new.status in ('PREPARING', 'RELEASED'))
    or (old.status = 'PREPARING' and new.status = 'READY')
    or (old.status = 'READY' and new.status = 'PICKED_UP')
    or (old.status = 'PICKED_UP' and new.status = 'COMPLETED')
  ) then
    raise exception 'invalid fulfilment transition: % -> %', old.status, new.status;
  end if;
  if old.prep_started_at is not null
    and new.prep_started_at is distinct from old.prep_started_at then
    raise exception 'preparation start cannot be reset';
  end if;
  if old.estimated_ready_at is not null
    and new.estimated_ready_at is distinct from old.estimated_ready_at then
    raise exception 'promised preparation time cannot be extended after payment';
  end if;
  if old.actual_ready_at is not null
    and new.actual_ready_at is distinct from old.actual_ready_at then
    raise exception 'actual Ready timestamp cannot change';
  end if;
  if old.ready_at is not null and new.ready_at is distinct from old.ready_at then
    raise exception 'Ready timestamp cannot change';
  end if;
  if old.package_count is not null
    and new.package_count is distinct from old.package_count then
    raise exception 'declared package count cannot change';
  end if;
  if new.status = 'PREPARING' and (
    new.prep_started_at is null
    or new.estimated_ready_at is null
    or new.estimated_ready_at <> new.prep_started_at
      + pg_catalog.make_interval(mins => new.promised_prep_minutes)
  ) then
    raise exception 'PREPARING fulfilment requires an authoritative preparation clock';
  end if;
  if new.package_count is not null and new.status <> 'PREPARING'
    and old.package_count is null then
    raise exception 'packages can only be declared while Preparing';
  end if;
  if new.status = 'READY' and old.status <> 'READY' and (
    old.status <> 'PREPARING'
    or new.ready_at is null
    or new.actual_ready_at is null
    or new.ready_at is distinct from new.actual_ready_at
    or new.package_count is null
  ) then
    raise exception 'READY requires immutable time, packages and a PREPARING predecessor';
  end if;
  if old.status = 'READY' and new.status = 'PICKED_UP' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.pickup_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then
      v_handoff_id := null;
    end;
    if v_handoff_id is null
      or not exists (
        select 1 from dastak_v1.verification_handoffs handoff
        where handoff.id = v_handoff_id
          and handoff.fulfilment_id = new.id
          and handoff.status = 'CONSUMED'
      )
      or (
        select count(*) from dastak_v1.packages package
        where package.fulfilment_id = new.id
          and package.status = 'PICKED_UP'
          and package.current_custody_owner_type = 'RIDER'
      ) <> new.package_count then
      raise exception 'fulfilment pickup requires verified custody of every package';
    end if;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function public.dastak_v1_advance_delivery_mission(
  p_account_id uuid,
  p_mission_id uuid,
  p_action text,
  p_stop_id uuid,
  p_accounted_package_count integer,
  p_verification_code text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_command constant text := 'advanceDeliveryMissionV1';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_stop dastak_v1.delivery_stops%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_package_rows integer;
  v_attempt_limit integer;
  v_failed_attempts integer;
  v_custody_started boolean;
begin
  if p_account_id is null or p_mission_id is null
    or p_action not in (
      'START_PICKUPS', 'ARRIVE_PICKUP', 'VERIFY_PICKUP',
      'CANCEL_BEFORE_PICKUP', 'REPORT_DELIVERY_PROBLEM'
    )
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or (
      p_action in ('ARRIVE_PICKUP', 'VERIFY_PICKUP') and p_stop_id is null
    )
    or (
      p_action = 'VERIFY_PICKUP' and (
        p_accounted_package_count is null or p_accounted_package_count < 1
        or p_verification_code is null or p_verification_code !~ '^[0-9]{6}$'
      )
    )
    or (
      p_action in ('CANCEL_BEFORE_PICKUP', 'REPORT_DELIVERY_PROBLEM')
      and (
        p_reason is null
        or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
      )
    ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The delivery action is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  v_request_hash := extensions.digest(p_request_digest, 'sha256');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_account_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_account_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with another request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-rider:' || p_account_id::text, 0)
  );
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  if not found or v_mission.assigned_rider_id is distinct from p_account_id then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'mission_not_found', 'message', 'This delivery mission is unavailable.'
      )
    );
    response_status := 404;
  else
    select customer_order.* into v_order
    from dastak_v1.orders customer_order
    where customer_order.id = v_mission.order_id
    for update;
    v_custody_started := v_mission.first_package_picked_up_at is not null
      or exists (
        select 1 from dastak_v1.packages package
        where package.order_id = v_mission.order_id
          and package.current_custody_owner_type = 'RIDER'
      );

    if p_action = 'START_PICKUPS' then
      if v_mission.status <> 'ASSIGNED' then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'invalid_mission_state', 'message', 'This mission cannot start pickups.'
        )); response_status := 409;
      else
        update dastak_v1.delivery_missions mission
        set status = 'EN_ROUTE_TO_PICKUPS', version = mission.version + 1
        where mission.id = v_mission.id returning * into v_mission;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_mission.id::text || ':RIDER_STARTED_PICKUPS:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'RIDER_STARTED_PICKUPS', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;

    elsif p_action = 'ARRIVE_PICKUP' then
      select stop.* into v_stop
      from dastak_v1.delivery_stops stop
      where stop.id = p_stop_id and stop.mission_id = v_mission.id
      for update;
      if not found then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'pickup_stop_not_found', 'message', 'This pickup stop is unavailable.'
        )); response_status := 404;
      elsif v_mission.status not in ('EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS')
        or v_stop.status <> 'PENDING' then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'invalid_pickup_state', 'message', 'This pickup arrival is not allowed.'
        )); response_status := 409;
      else
        update dastak_v1.delivery_stops stop
        set status = 'ARRIVED', arrived_at = v_now,
            version = stop.version + 1
        where stop.id = v_stop.id returning * into v_stop;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_stop.id::text || ':RIDER_ARRIVED_PICKUP:' || v_stop.version::text,
          'DELIVERY_STOP', v_stop.id, v_stop.version,
          'RIDER_ARRIVED_PICKUP', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'stopId', v_stop.id, 'fulfilmentId', v_stop.fulfilment_id,
            'arrivedAt', v_stop.arrived_at
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;

    elsif p_action = 'VERIFY_PICKUP' then
      select stop.* into v_stop
      from dastak_v1.delivery_stops stop
      where stop.id = p_stop_id and stop.mission_id = v_mission.id
      for update;
      if found then
        select fulfilment.* into v_fulfilment
        from dastak_v1.fulfilments fulfilment
        where fulfilment.id = v_stop.fulfilment_id
        for update;
        select handoff.* into v_handoff
        from dastak_v1.verification_handoffs handoff
        where handoff.mission_id = v_mission.id
          and handoff.fulfilment_id = v_stop.fulfilment_id
          and handoff.handoff_type = 'MERCHANT_TO_RIDER'
        for update;
        perform 1 from dastak_v1.packages package
        where package.fulfilment_id = v_stop.fulfilment_id
        order by package.id for update;
      end if;

      if v_stop.id is null then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'pickup_stop_not_found', 'message', 'This pickup stop is unavailable.'
        )); response_status := 404;
      elsif v_mission.status not in ('EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS')
        or v_stop.status not in ('PENDING', 'ARRIVED') then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'invalid_pickup_state', 'message', 'This pickup cannot be verified now.'
        )); response_status := 409;
      elsif v_fulfilment.status <> 'READY' then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'fulfilment_not_ready',
          'message', 'The merchant must explicitly mark this fulfilment Ready.'
        )); response_status := 409;
      elsif v_stop.declared_package_count is null
        or p_accounted_package_count <> v_stop.declared_package_count
        or p_accounted_package_count <> v_fulfilment.package_count
        or (
          select count(*) from dastak_v1.packages package
          where package.fulfilment_id = v_fulfilment.id
            and package.status = 'READY'
            and package.current_custody_owner_type = 'MERCHANT_BRANCH'
            and package.current_custody_owner_id = v_fulfilment.branch_id
        ) <> p_accounted_package_count then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'package_count_mismatch',
          'message', 'Every declared package must be present for one complete pickup.'
        )); response_status := 409;
      elsif v_handoff.status = 'CONSUMED' then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'pickup_code_consumed', 'message', 'This pickup code was already consumed.'
        )); response_status := 409;
      elsif v_handoff.status <> 'ACTIVE' then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', case when v_handoff.status = 'BLOCKED' then 'pickup_code_blocked'
            else 'pickup_code_inactive' end,
          'message', 'This pickup code is not active.'
        )); response_status := 409;
      elsif v_handoff.code_digest <> private.dastak_v1_handoff_digest(
        p_verification_code
      ) then
        v_attempt_limit := (
          dastak_v1_api.rider_matching_configuration()
          ->> 'verificationInvalidAttemptLimit'
        )::integer;
        v_failed_attempts := v_handoff.failed_attempts + 1;
        update dastak_v1.verification_handoffs handoff
        set failed_attempts = v_failed_attempts,
            status = case when v_failed_attempts >= v_attempt_limit
              then 'BLOCKED' else handoff.status end,
            blocked_at = case when v_failed_attempts >= v_attempt_limit
              then v_now else null end,
            version = handoff.version + 1
        where handoff.id = v_handoff.id;
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'PICKUP_CODE_REJECTED', 'verification_handoff', v_handoff.id,
          pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'failedAttempts', v_failed_attempts,
            'blocked', v_failed_attempts >= v_attempt_limit
          )
        );
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', case when v_failed_attempts >= v_attempt_limit
            then 'pickup_code_blocked' else 'pickup_code_invalid' end,
          'message', case when v_failed_attempts >= v_attempt_limit
            then 'The pickup code is blocked for Operations review.'
            else 'The pickup code is incorrect.' end
        )); response_status := 409;
      else
        update dastak_v1.verification_handoffs handoff
        set status = 'CONSUMED', consumed_at = v_now,
            consumed_by = p_account_id, version = handoff.version + 1
        where handoff.id = v_handoff.id
        returning * into v_handoff;
        perform pg_catalog.set_config(
          'dastak_v1.pickup_verification_id', v_handoff.id::text, true
        );
        update dastak_v1.packages package
        set status = 'PICKED_UP', picked_up_at = v_now,
            current_custody_owner_type = 'RIDER',
            current_custody_owner_id = p_account_id,
            version = package.version + 1
        where package.fulfilment_id = v_fulfilment.id
          and package.status = 'READY';
        get diagnostics v_package_rows = row_count;
        if v_package_rows <> v_fulfilment.package_count then
          raise exception 'pickup custody transfer was not complete';
        end if;

        insert into dastak_v1.package_custody_events (
          order_id, mission_id, fulfilment_id, package_id,
          verification_handoff_id, from_owner_type, from_owner_id,
          to_owner_type, to_owner_id, transferred_by, transferred_at
        )
        select
          v_mission.order_id, v_mission.id, v_fulfilment.id, package.id,
          v_handoff.id, 'MERCHANT_BRANCH', v_fulfilment.branch_id,
          'RIDER', p_account_id, p_account_id, v_now
        from dastak_v1.packages package
        where package.fulfilment_id = v_fulfilment.id
        order by package.package_number;

        update dastak_v1.fulfilments fulfilment
        set status = 'PICKED_UP', version = fulfilment.version + 1
        where fulfilment.id = v_fulfilment.id
        returning * into v_fulfilment;
        update dastak_v1.delivery_stops stop
        set status = 'COMPLETED', arrived_at = coalesce(stop.arrived_at, v_now),
            completed_at = v_now,
            waiting_seconds = greatest(0, pg_catalog.floor(extract(epoch from (
              v_fulfilment.actual_ready_at - coalesce(stop.arrived_at, v_now)
            )))::integer),
            version = stop.version + 1
        where stop.id = v_stop.id returning * into v_stop;

        if v_mission.status = 'EN_ROUTE_TO_PICKUPS' then
          update dastak_v1.delivery_missions mission
          set status = 'PICKUP_IN_PROGRESS',
              first_package_picked_up_at = coalesce(
                mission.first_package_picked_up_at, v_now
              ),
              version = mission.version + 1
          where mission.id = v_mission.id returning * into v_mission;
        elsif v_mission.first_package_picked_up_at is null then
          update dastak_v1.delivery_missions mission
          set first_package_picked_up_at = v_now,
              version = mission.version + 1
          where mission.id = v_mission.id returning * into v_mission;
        end if;
        if not exists (
          select 1 from dastak_v1.delivery_stops stop
          where stop.mission_id = v_mission.id and stop.status <> 'COMPLETED'
        ) then
          update dastak_v1.delivery_missions mission
          set status = 'ALL_PACKAGES_PICKED_UP',
              all_packages_picked_up_at = v_now,
              version = mission.version + 1
          where mission.id = v_mission.id returning * into v_mission;
        end if;

        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_fulfilment.id::text || ':FULFILMENT_PICKED_UP:' || v_fulfilment.version::text,
          'FULFILMENT', v_fulfilment.id, v_fulfilment.version,
          'FULFILMENT_PICKED_UP', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'stopId', v_stop.id, 'fulfilmentId', v_fulfilment.id,
            'packageCount', v_package_rows, 'handoffId', v_handoff.id,
            'waitingSeconds', v_stop.waiting_seconds
          )
        );
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'FULFILMENT_PICKED_UP', 'fulfilment', v_fulfilment.id,
          pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'packageCount', v_package_rows, 'handoffId', v_handoff.id,
            'waitingSeconds', v_stop.waiting_seconds
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;

    elsif p_action = 'CANCEL_BEFORE_PICKUP' then
      if v_custody_started then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'delivery_recovery_required',
          'message', 'Normal cancellation is forbidden after package custody begins.'
        )); response_status := 409;
      elsif v_mission.status not in ('ASSIGNED', 'EN_ROUTE_TO_PICKUPS') then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'invalid_mission_state', 'message', 'This mission cannot be reassigned.'
        )); response_status := 409;
      else
        update dastak_v1.delivery_missions mission
        set status = 'REASSIGNING', assigned_rider_id = null,
            assigned_transport_type = null, assigned_at = null,
            version = mission.version + 1
        where mission.id = v_mission.id returning * into v_mission;
        update dastak_v1.delivery_offers offer
        set status = 'CLOSED', responded_at = coalesce(offer.responded_at, v_now),
            closed_reason = 'RIDER_CANCELLED_BEFORE_PICKUP',
            version = offer.version + 1
        where offer.mission_id = v_mission.id and offer.status = 'ACCEPTED';
        update dastak_v1.delivery_stops stop
        set status = 'PENDING', arrived_at = null, completed_at = null,
            waiting_seconds = null, version = stop.version + 1
        where stop.mission_id = v_mission.id and stop.status = 'ARRIVED';
        update dastak_v1.delivery_missions mission
        set status = 'SEARCHING_RIDER', pool_round = mission.pool_round + 1,
            version = mission.version + 1
        where mission.id = v_mission.id returning * into v_mission;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_mission.id::text || ':RIDER_REASSIGNING:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'RIDER_REASSIGNING', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'reason', pg_catalog.btrim(p_reason), 'custodyStarted', false
          )
        );
        perform dastak_v1_api.create_rider_offer_pool(v_mission.id, v_now);
        response_body := pg_catalog.jsonb_build_object(
          'offer', null, 'currentMission', null, 'reassignmentStarted', true
        );
        response_status := 200;
      end if;

    elsif p_action = 'REPORT_DELIVERY_PROBLEM' then
      if not v_custody_started then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'cancel_before_pickup_available',
          'message', 'Cancel before pickup while no package is in rider custody.'
        )); response_status := 409;
      elsif v_mission.status not in (
        'PICKUP_IN_PROGRESS', 'ALL_PACKAGES_PICKED_UP',
        'OUT_FOR_DELIVERY', 'ARRIVED'
      ) then
        response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
          'code', 'invalid_mission_state', 'message', 'Delivery Recovery is unavailable.'
        )); response_status := 409;
      else
        insert into dastak_v1.delivery_problem_reports (
          order_id, mission_id, reported_by, mission_status_at_report,
          custody_started, reason, reported_at
        ) values (
          v_mission.order_id, v_mission.id, p_account_id, v_mission.status,
          true, pg_catalog.btrim(p_reason), v_now
        );
        update dastak_v1.delivery_missions mission
        set status = 'DELIVERY_RECOVERY', version = mission.version + 1
        where mission.id = v_mission.id returning * into v_mission;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_mission.id::text || ':DELIVERY_RECOVERY_REQUIRED:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'DELIVERY_RECOVERY_REQUIRED', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_mission.order_id, 'missionId', v_mission.id,
            'reason', pg_catalog.btrim(p_reason), 'custodyStarted', true
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;
    end if;
  end if;

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_account_id, v_command, p_idempotency_key, v_request_hash,
    response_body, response_status, p_mission_id
  );
  return next;
end;
$$;

create function dastak_v1.activate_pickup_after_ready()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eligible boolean;
begin
  if old.status <> 'READY' and new.status = 'READY' then
    update dastak_v1.delivery_stops stop
    set declared_package_count = new.package_count,
        version = stop.version + 1
    where stop.fulfilment_id = new.id
      and stop.declared_package_count is null;

    update dastak_v1.verification_handoffs handoff
    set status = 'ACTIVE', activated_at = new.actual_ready_at,
        version = handoff.version + 1
    where handoff.fulfilment_id = new.id
      and handoff.handoff_type = 'MERCHANT_TO_RIDER'
      and handoff.status = 'INACTIVE';

    select (
      dastak_v1_api.order_rider_match_eligibility(
        new.order_id, pg_catalog.clock_timestamp()
      ) ->> 'eligible'
    )::boolean into v_eligible;
    if v_eligible then
      begin
        perform dastak_v1_api.ensure_delivery_mission(
          new.order_id, pg_catalog.clock_timestamp()
        );
      exception when sqlstate '55000' then
        insert into dastak_v1.audit_events (
          action, resource_type, resource_id, metadata
        ) values (
          'RIDER_MATCH_SYSTEM_CONFIGURATION_ERROR', 'order', new.order_id,
          pg_catalog.jsonb_build_object(
            'fulfilmentId', new.id,
            'sqlState', sqlstate,
            'message', sqlerrm
          )
        );
      end;
    end if;
  end if;
  return new;
end;
$$;

create trigger fulfilments_activate_pickup_after_ready
after update of status on dastak_v1.fulfilments
for each row execute function dastak_v1.activate_pickup_after_ready();

alter function dastak_v1_api.order_json(uuid, uuid)
  rename to order_json_step3;

create function dastak_v1_api.order_json(
  p_order_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order jsonb;
begin
  v_order := dastak_v1_api.order_json_step3(p_order_id, p_customer_id);
  if v_order is null then return null; end if;
  if v_order ->> 'status' = 'PICKUP_IN_PROGRESS' then
    v_order := pg_catalog.jsonb_set(
      v_order, '{customerState}', '"PICKING_UP"'::jsonb, true
    );
    v_order := pg_catalog.jsonb_set(
      v_order, '{fulfilmentProgress}',
      '{"state":"PICKING_UP","title":"Picking up your order"}'::jsonb,
      true
    );
  end if;
  return v_order;
end;
$$;

alter function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  rename to merchant_fulfilment_json_step3;

create function dastak_v1_api.merchant_fulfilment_json(
  p_actor_id uuid,
  p_fulfilment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_stop dastak_v1.delivery_stops%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
begin
  v_result := dastak_v1_api.merchant_fulfilment_json_step3(
    p_actor_id, p_fulfilment_id
  );
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment where fulfilment.id = p_fulfilment_id;
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  join dastak_v1.delivery_stops stop on stop.mission_id = mission.id
  where stop.fulfilment_id = p_fulfilment_id
    and mission.status not in ('DELIVERED', 'CANCELLED')
  order by mission.created_at desc limit 1;
  if found then
    select stop.* into v_stop from dastak_v1.delivery_stops stop
    where stop.mission_id = v_mission.id
      and stop.fulfilment_id = p_fulfilment_id;
    select handoff.* into v_handoff
    from dastak_v1.verification_handoffs handoff
    where handoff.mission_id = v_mission.id
      and handoff.fulfilment_id = p_fulfilment_id
      and handoff.handoff_type = 'MERCHANT_TO_RIDER';

    v_result := v_result || pg_catalog.jsonb_build_object(
      'delivery', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'missionId', v_mission.id,
        'missionStatus', v_mission.status,
        'riderAssigned', v_mission.assigned_rider_id is not null,
        'rider', case when v_mission.assigned_rider_id is not null then (
          select pg_catalog.jsonb_build_object(
            'id', account.id, 'displayName', account.display_name
          ) from public.accounts account where account.id = v_mission.assigned_rider_id
        ) else null end,
        'transportType', v_mission.assigned_transport_type,
        'stopId', v_stop.id,
        'stopStatus', v_stop.status,
        'riderArrivedAt', v_stop.arrived_at,
        'waitingSeconds', case
          when v_stop.status = 'ARRIVED' then greatest(0, pg_catalog.floor(extract(epoch from (
            pg_catalog.clock_timestamp() - v_stop.arrived_at
          )))::integer)
          else coalesce(v_stop.waiting_seconds, 0)
        end,
        'verificationStatus', v_handoff.status,
        'pickupCode', case
          when v_handoff.status = 'ACTIVE'
            and v_fulfilment.status = 'READY'
            and v_mission.assigned_rider_id is not null
            and v_stop.declared_package_count = v_fulfilment.package_count
          then private.dastak_v1_handoff_code(
            v_handoff.id, v_handoff.handoff_type, v_handoff.code_version
          )
          else null
        end,
        'pickedUpAt', v_stop.completed_at
      ))
    );
  end if;
  return v_result;
end;
$$;

create or replace function dastak_v1_api.list_merchant_fulfilments(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'fulfilments', coalesce(pg_catalog.jsonb_agg(
      dastak_v1_api.merchant_fulfilment_json(p_actor_id, visible.id)
      order by visible.committed_at desc, visible.id desc
    ), '[]'::jsonb)
  )
  from (
    select fulfilment.id, fulfilment.committed_at
    from dastak_v1.fulfilments fulfilment
    where fulfilment.status in (
      'RESERVED_PREPAYMENT', 'PREPARING', 'READY', 'PICKED_UP'
    )
      and dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id, fulfilment.organization_id,
        'merchant.fulfilment.manage', fulfilment.branch_id
      )
    order by fulfilment.committed_at desc, fulfilment.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
  ) visible;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_step3;

create function dastak_v1_api.admin_execution_trace(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trace jsonb;
begin
  v_trace := dastak_v1_api.admin_execution_trace_step3(p_actor_id, p_order_id);
  return v_trace || pg_catalog.jsonb_build_object(
    'delivery', pg_catalog.jsonb_build_object(
      'mission', (
        select pg_catalog.jsonb_build_object(
          'id', mission.id, 'status', mission.status, 'version', mission.version,
          'riderId', mission.assigned_rider_id,
          'riderName', account.display_name,
          'transportType', mission.assigned_transport_type,
          'pickupCount', mission.pickup_count,
          'poolRound', mission.pool_round,
          'searchStartedAt', mission.search_started_at,
          'assignedAt', mission.assigned_at,
          'firstPackagePickedUpAt', mission.first_package_picked_up_at,
          'allPackagesPickedUpAt', mission.all_packages_picked_up_at,
          'transportSnapshot', mission.transport_snapshot
        )
        from dastak_v1.delivery_missions mission
        left join public.accounts account on account.id = mission.assigned_rider_id
        where mission.order_id = p_order_id
        order by mission.created_at desc limit 1
      ),
      'offers', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', offer.id, 'missionId', offer.mission_id,
          'riderId', offer.rider_id, 'riderName', account.display_name,
          'transportType', offer.transport_type, 'poolRound', offer.pool_round,
          'status', offer.status, 'distanceMeters', offer.distance_meters,
          'offeredAt', offer.offered_at, 'respondBy', offer.respond_by,
          'respondedAt', offer.responded_at, 'closedReason', offer.closed_reason
        ) order by offer.offered_at, offer.id)
        from dastak_v1.delivery_offers offer
        join public.accounts account on account.id = offer.rider_id
        where offer.order_id = p_order_id
      ), '[]'::jsonb),
      'pickupStops', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', stop.id, 'missionId', stop.mission_id,
          'fulfilmentId', stop.fulfilment_id, 'branchId', stop.branch_id,
          'branchName', branch.display_name, 'sequence', stop.stop_sequence,
          'status', stop.status, 'packageCount', stop.declared_package_count,
          'arrivedAt', stop.arrived_at, 'completedAt', stop.completed_at,
          'waitingSeconds', case when stop.status = 'ARRIVED' then greatest(
            0, pg_catalog.floor(extract(epoch from (
              pg_catalog.clock_timestamp() - stop.arrived_at
            )))::integer
          ) else coalesce(stop.waiting_seconds, 0) end
        ) order by stop.stop_sequence)
        from dastak_v1.delivery_stops stop
        join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
        where stop.order_id = p_order_id
      ), '[]'::jsonb),
      'verification', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', handoff.id, 'missionId', handoff.mission_id,
          'fulfilmentId', handoff.fulfilment_id,
          'type', handoff.handoff_type, 'status', handoff.status,
          'failedAttempts', handoff.failed_attempts,
          'activatedAt', handoff.activated_at,
          'consumedAt', handoff.consumed_at,
          'consumedBy', handoff.consumed_by,
          'blockedAt', handoff.blocked_at
        ) order by handoff.created_at, handoff.id)
        from dastak_v1.verification_handoffs handoff
        where handoff.order_id = p_order_id
      ), '[]'::jsonb),
      'custody', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', custody.id, 'missionId', custody.mission_id,
          'fulfilmentId', custody.fulfilment_id, 'packageId', custody.package_id,
          'verificationHandoffId', custody.verification_handoff_id,
          'fromOwnerType', custody.from_owner_type,
          'fromOwnerId', custody.from_owner_id,
          'toOwnerType', custody.to_owner_type,
          'toOwnerId', custody.to_owner_id,
          'transferredBy', custody.transferred_by,
          'transferredAt', custody.transferred_at
        ) order by custody.transferred_at, custody.id)
        from dastak_v1.package_custody_events custody
        where custody.order_id = p_order_id
      ), '[]'::jsonb),
      'problems', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', problem.id, 'missionId', problem.mission_id,
          'reportedBy', problem.reported_by,
          'missionStatusAtReport', problem.mission_status_at_report,
          'custodyStarted', problem.custody_started,
          'reason', problem.reason, 'reportedAt', problem.reported_at
        ) order by problem.reported_at, problem.id)
        from dastak_v1.delivery_problem_reports problem
        where problem.order_id = p_order_id
      ), '[]'::jsonb)
    )
  );
end;
$$;

create or replace function private.delivery_partner_application_json(
  application_row private.delivery_partner_applications
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'applicationId', (application_row).id,
    'status', (application_row).status,
    'deliveryMethod', (application_row).delivery_method,
    'vehicleVerificationRequired',
      (application_row).delivery_method in (
        'bike', 'motorbike', 'scooter', 'auto', 'car'
      )
  );
$$;

create function public.submit_delivery_partner_application_v3(
  p_account_id uuid,
  p_delivery_method text,
  p_identity_evidence_object_path text,
  p_vehicle_registration_number text,
  p_vehicle_make_model text,
  p_vehicle_evidence_object_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mapped_method text;
  v_result record;
begin
  if p_delivery_method not in (
    'walking', 'bicycle', 'motorbike', 'scooter', 'auto', 'car'
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The transport type is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;
  v_mapped_method := case p_delivery_method
    when 'motorbike' then 'bike'
    when 'scooter' then 'auto'
    else p_delivery_method
  end;
  select result.* into v_result
  from public.submit_delivery_partner_application_v2(
    p_account_id, v_mapped_method, p_identity_evidence_object_path,
    p_vehicle_registration_number, p_vehicle_make_model,
    p_vehicle_evidence_object_path, p_idempotency_key, p_request_digest
  ) result;
  response_status := v_result.response_status;
  response_body := v_result.response_body;
  if response_status = 200 then
    update private.delivery_partner_applications application
    set delivery_method = p_delivery_method,
        updated_at = pg_catalog.now()
    where application.account_id = p_account_id
      and application.status = 'pending';
    response_body := pg_catalog.jsonb_set(
      response_body, '{deliveryMethod}', pg_catalog.to_jsonb(p_delivery_method), true
    );
  end if;
  return next;
end;
$$;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'dastak-v1-rider-matching'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
end;
$$;

select cron.schedule(
  'dastak-v1-rider-matching',
  '* * * * *',
  $cron$select dastak_v1_api.process_rider_matching_due_orders(100);$cron$
);

revoke all on function dastak_v1.rider_transport_type(text) from public;
revoke all on function dastak_v1.is_valid_rider_pool_expansion(jsonb) from public;
revoke all on function dastak_v1.guard_delivery_mission() from public;
revoke all on function dastak_v1.guard_delivery_offer() from public;
revoke all on function dastak_v1.guard_delivery_stop() from public;
revoke all on function dastak_v1.guard_verification_handoff() from public;
revoke all on function dastak_v1.activate_pickup_after_ready() from public;
revoke all on function private.dastak_v1_handoff_code(
  uuid, dastak_v1.verification_handoff_type, integer
) from public, anon, authenticated;
revoke all on function private.dastak_v1_handoff_digest(text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.rider_matching_configuration() from public;
revoke all on function dastak_v1_api.create_rider_offer_pool(uuid, timestamptz)
  from public;
revoke all on function dastak_v1_api.ensure_delivery_mission(uuid, timestamptz)
  from public;
revoke all on function dastak_v1_api.expand_rider_pool_if_due(uuid, timestamptz)
  from public;
revoke all on function dastak_v1_api.process_rider_matching_due_orders(
  integer, timestamptz
) from public;
revoke all on function dastak_v1_api.rider_offer_json(uuid, uuid) from public;
revoke all on function dastak_v1_api.rider_mission_json(uuid, uuid) from public;
revoke all on function dastak_v1_api.delivery_partner_snapshot(uuid) from public;
revoke all on function dastak_v1_api.order_json_step3(uuid, uuid) from public;
revoke all on function dastak_v1_api.merchant_fulfilment_json_step3(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.admin_execution_trace_step3(uuid, uuid)
  from public;
revoke all on function public.dastak_v1_delivery_partner_snapshot(uuid)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_accept_delivery_offer(
  uuid, uuid, text, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_decline_delivery_offer(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.submit_delivery_partner_application_v3(
  uuid, text, text, text, text, text, text, text
) from public, anon, authenticated;

grant execute on function dastak_v1.rider_transport_type(text) to service_role;
grant execute on function dastak_v1.is_valid_rider_pool_expansion(jsonb)
  to service_role;
grant execute on function private.dastak_v1_handoff_code(
  uuid, dastak_v1.verification_handoff_type, integer
) to service_role;
grant execute on function private.dastak_v1_handoff_digest(text) to service_role;
grant execute on function dastak_v1_api.rider_matching_configuration()
  to service_role;
grant execute on function dastak_v1_api.create_rider_offer_pool(uuid, timestamptz)
  to service_role;
grant execute on function dastak_v1_api.ensure_delivery_mission(uuid, timestamptz)
  to service_role;
grant execute on function dastak_v1_api.expand_rider_pool_if_due(uuid, timestamptz)
  to service_role;
grant execute on function dastak_v1_api.process_rider_matching_due_orders(
  integer, timestamptz
) to service_role;
grant execute on function dastak_v1_api.rider_offer_json(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.rider_mission_json(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.delivery_partner_snapshot(uuid)
  to service_role;
grant execute on function dastak_v1_api.order_json_step3(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.merchant_fulfilment_json_step3(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.admin_execution_trace_step3(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.order_json(uuid, uuid)
  to authenticated, service_role;
grant execute on function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  to authenticated, service_role;
grant execute on function dastak_v1_api.list_merchant_fulfilments(uuid, integer)
  to authenticated, service_role;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.dastak_v1_delivery_partner_snapshot(uuid)
  to service_role;
grant execute on function public.dastak_v1_accept_delivery_offer(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.dastak_v1_decline_delivery_offer(
  uuid, uuid, text, text, text
) to service_role;
grant execute on function public.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) to service_role;
grant execute on function public.submit_delivery_partner_application_v3(
  uuid, text, text, text, text, text, text, text
) to service_role;
