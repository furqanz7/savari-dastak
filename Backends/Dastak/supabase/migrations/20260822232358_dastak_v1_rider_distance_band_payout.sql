-- Dastak V1 production rider payout: immutable distance-band mission quotes.

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values (
  'settlement.rider_distance_payout',
  'JSON',
  'Server-authoritative rider payout bands snapshotted onto each delivery mission.',
  null,
  '{"requiredKeys":["base_distance_meters","base_payout_paise","increment_distance_meters","increment_payout_paise","rounding"],"allowedRounding":["STARTED_DISTANCE_BAND"]}'::jsonb,
  true,
  true
);

alter table dastak_v1.delivery_missions
  add column delivery_distance_meters bigint not null
    check (delivery_distance_meters >= 0),
  add column rider_payout_quote_paise bigint not null
    check (rider_payout_quote_paise >= 0),
  add column rider_payout_quote_snapshot jsonb not null
    check (pg_catalog.jsonb_typeof(rider_payout_quote_snapshot) = 'object');

create function dastak_v1.is_valid_rider_distance_payout(p_value jsonb)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_typeof(p_value) = 'object'
    and p_value ?& array[
      'base_distance_meters', 'base_payout_paise',
      'increment_distance_meters', 'increment_payout_paise', 'rounding'
    ]
    and pg_catalog.jsonb_typeof(p_value -> 'base_distance_meters') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'base_payout_paise') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'increment_distance_meters') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'increment_payout_paise') = 'number'
    and pg_catalog.jsonb_typeof(p_value -> 'rounding') = 'string'
    and p_value ->> 'base_distance_meters' ~ '^[1-9][0-9]*$'
    and p_value ->> 'base_payout_paise' ~ '^(0|[1-9][0-9]*)$'
    and p_value ->> 'increment_distance_meters' ~ '^[1-9][0-9]*$'
    and p_value ->> 'increment_payout_paise' ~ '^(0|[1-9][0-9]*)$'
    and (p_value ->> 'base_distance_meters')::numeric <= 2147483647
    and (p_value ->> 'base_payout_paise')::numeric <= 2147483647
    and (p_value ->> 'increment_distance_meters')::numeric <= 2147483647
    and (p_value ->> 'increment_payout_paise')::numeric <= 2147483647
    and p_value ->> 'rounding' = 'STARTED_DISTANCE_BAND',
    false
  );
$$;

create function dastak_v1_api.rider_distance_payout_configuration()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_configuration jsonb;
begin
  v_configuration := dastak_v1_api.effective_setting_json(
    'settlement.rider_distance_payout'
  );
  if not dastak_v1.is_valid_rider_distance_payout(v_configuration) then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'settlement.rider_distance_payout is missing or invalid.';
  end if;
  return v_configuration;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'settlement.rider_distance_payout is outside its supported range.';
end;
$$;

create function dastak_v1_api.calculate_rider_distance_payout(
  p_delivery_distance_meters bigint,
  p_configuration jsonb
)
returns bigint
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_base_distance bigint;
  v_base_payout bigint;
  v_increment_distance bigint;
  v_increment_payout bigint;
  v_started_increment_bands bigint;
  v_payout numeric;
begin
  if p_delivery_distance_meters is null or p_delivery_distance_meters < 0
    or not dastak_v1.is_valid_rider_distance_payout(p_configuration) then
    raise exception using
      errcode = '22023', message = 'invalid rider distance payout input';
  end if;

  v_base_distance := (p_configuration ->> 'base_distance_meters')::bigint;
  v_base_payout := (p_configuration ->> 'base_payout_paise')::bigint;
  v_increment_distance := (p_configuration ->> 'increment_distance_meters')::bigint;
  v_increment_payout := (p_configuration ->> 'increment_payout_paise')::bigint;
  v_started_increment_bands := case
    when p_delivery_distance_meters <= v_base_distance then 0
    else pg_catalog.ceil(
      (p_delivery_distance_meters - v_base_distance)::numeric
        / v_increment_distance::numeric
    )::bigint
  end;
  v_payout := v_base_payout::numeric
    + v_started_increment_bands::numeric * v_increment_payout::numeric;
  if v_payout > 9223372036854775807 then
    raise exception using
      errcode = '22003', message = 'rider payout exceeds bigint range';
  end if;
  return v_payout::bigint;
end;
$$;

create function dastak_v1.quote_delivery_mission_payout()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_ids uuid[];
  v_configuration jsonb;
begin
  select pg_catalog.array_agg(branch.branch_id order by branch.branch_id)
  into v_branch_ids
  from (
    select distinct fulfilment.branch_id
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = new.order_id
  ) branch;

  if pg_catalog.cardinality(v_branch_ids) not between 1 and 3 then
    raise exception using
      errcode = '55000',
      message = 'ORDER_FULFILMENT_INVARIANT_VIOLATION',
      detail = 'A delivery mission requires one to three authoritative pickup branches.';
  end if;

  new.delivery_distance_meters := dastak_v1_api.pickup_route_distance_meters(
    new.order_id, v_branch_ids
  );
  if new.delivery_distance_meters is null then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Authoritative Dastak delivery distance could not be calculated.';
  end if;

  v_configuration := dastak_v1_api.rider_distance_payout_configuration();
  new.rider_payout_quote_paise := dastak_v1_api.calculate_rider_distance_payout(
    new.delivery_distance_meters, v_configuration
  );
  new.rider_payout_quote_snapshot := pg_catalog.jsonb_build_object(
    'payoutFormula', 'DISTANCE_BAND',
    'distanceSource', 'DASTAK_PICKUP_ROUTE_METERS',
    'deliveryDistanceMeters', new.delivery_distance_meters,
    'baseDistanceMeters', (v_configuration ->> 'base_distance_meters')::bigint,
    'basePayoutPaise', (v_configuration ->> 'base_payout_paise')::bigint,
    'incrementDistanceMeters',
      (v_configuration ->> 'increment_distance_meters')::bigint,
    'incrementPayoutPaise',
      (v_configuration ->> 'increment_payout_paise')::bigint,
    'rounding', v_configuration ->> 'rounding',
    'quotedPayoutPaise', new.rider_payout_quote_paise,
    'quotedAt', pg_catalog.clock_timestamp()
  );
  return new;
end;
$$;

create trigger delivery_missions_quote_rider_payout
before insert on dastak_v1.delivery_missions
for each row execute function dastak_v1.quote_delivery_mission_payout();

create function dastak_v1.guard_delivery_mission_payout_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.delivery_distance_meters is distinct from old.delivery_distance_meters
    or new.rider_payout_quote_paise is distinct from old.rider_payout_quote_paise
    or new.rider_payout_quote_snapshot is distinct from old.rider_payout_quote_snapshot then
    raise exception 'delivery mission payout quote cannot change';
  end if;
  return new;
end;
$$;

create trigger delivery_missions_00_payout_snapshot_guard
before update on dastak_v1.delivery_missions
for each row execute function dastak_v1.guard_delivery_mission_payout_snapshot();

revoke all on function dastak_v1.is_valid_rider_distance_payout(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.rider_distance_payout_configuration()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.calculate_rider_distance_payout(bigint,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.quote_delivery_mission_payout()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.guard_delivery_mission_payout_snapshot()
  from public, anon, authenticated, service_role;
