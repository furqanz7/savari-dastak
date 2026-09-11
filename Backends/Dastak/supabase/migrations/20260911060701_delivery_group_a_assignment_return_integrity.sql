-- Delivery Web Group A secures one delivery partner / one active job across every
-- delivery domain, plus server-authoritative return-arrival custody gates.

-- A single predicate is deliberately used by every acquisition guard. The
-- delivery-recovery mission that originated a return is the only compatible
-- V1/return pair: it represents one continuous custody obligation.
create function private.delivery_partner_active_work(
  p_rider_id uuid,
  p_excluded_domain text default null,
  p_excluded_id uuid default null,
  p_related_delivery_mission_id uuid default null
)
returns table(work_domain text, work_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select active.work_domain, active.work_id
  from (
    select 'DASTAK_V1'::text as work_domain, mission.id as work_id, 1 as priority
    from dastak_v1.delivery_missions mission
    where mission.assigned_rider_id = p_rider_id
      and mission.status in (
        'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
        'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
        'DELIVERY_RECOVERY'
      )
      and not (
        p_excluded_domain is not distinct from 'DASTAK_V1'
        and mission.id is not distinct from p_excluded_id
      )
      and not (
        mission.status = 'DELIVERY_RECOVERY'
        and mission.id is not distinct from p_related_delivery_mission_id
      )

    union all

    select 'RETURN'::text, mission.id, 2
    from dastak_v1.return_missions mission
    where mission.assigned_rider_id = p_rider_id
      and mission.status not in ('COMPLETED', 'CANCELLED')
      and not (
        p_excluded_domain is not distinct from 'RETURN'
        and mission.id is not distinct from p_excluded_id
      )
      and not (
        p_excluded_domain is not distinct from 'DASTAK_V1'
        and p_related_delivery_mission_id is not null
        and mission.source_delivery_mission_id
          is not distinct from p_related_delivery_mission_id
      )

    union all

    select 'LEGACY_COURIER'::text, assignment.id, 3
    from private.delivery_assignment_attempts assignment
    where assignment.partner_account_id = p_rider_id
      and assignment.status = 'accepted'
      and not (
        p_excluded_domain is not distinct from 'LEGACY_COURIER'
        and assignment.id is not distinct from p_excluded_id
      )

    union all

    select 'PARCEL'::text, assignment.id, 4
    from private.parcel_assignment_attempts assignment
    where assignment.partner_account_id = p_rider_id
      and assignment.status = 'acknowledged'
      and not (
        p_excluded_domain is not distinct from 'PARCEL'
        and assignment.id is not distinct from p_excluded_id
      )
  ) active
  order by active.priority, active.work_id
  limit 1;
$$;

create function private.delivery_partner_has_active_work(
  p_rider_id uuid,
  p_excluded_domain text default null,
  p_excluded_id uuid default null,
  p_related_delivery_mission_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.delivery_partner_active_work(
      p_rider_id,
      p_excluded_domain,
      p_excluded_id,
      p_related_delivery_mission_id
    )
  );
$$;

create function private.lock_delivery_partner_active_work(p_rider_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_rider_id is null then
    raise exception using errcode = '22023', message = 'INVALID_RIDER_ID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'dastak:delivery-partner-active-work:' || p_rider_id::text,
      0
    )
  );
end;
$$;

-- This trigger is a defence-in-depth backstop for all canonical mutation
-- functions. Those functions acquire the same rider lock before issuing the
-- statement, so the predicate observes every earlier committed acquisition.
create function private.enforce_delivery_partner_active_work()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  rider_id uuid;
  excluded_domain text;
  excluded_id uuid;
  related_delivery_mission_id uuid;
  is_active boolean := false;
begin
  if tg_table_schema = 'dastak_v1' and tg_table_name = 'delivery_missions' then
    rider_id := new.assigned_rider_id;
    excluded_domain := 'DASTAK_V1';
    excluded_id := new.id;
    related_delivery_mission_id := case
      when new.status = 'DELIVERY_RECOVERY' then new.id
      else null
    end;
    is_active := rider_id is not null and new.status in (
      'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
      'DELIVERY_RECOVERY'
    );
  elsif tg_table_schema = 'dastak_v1' and tg_table_name = 'return_missions' then
    rider_id := new.assigned_rider_id;
    excluded_domain := 'RETURN';
    excluded_id := new.id;
    related_delivery_mission_id := new.source_delivery_mission_id;
    is_active := rider_id is not null and new.status not in ('COMPLETED', 'CANCELLED');
  elsif tg_table_schema = 'private' and tg_table_name = 'delivery_assignment_attempts' then
    rider_id := new.partner_account_id;
    excluded_domain := 'LEGACY_COURIER';
    excluded_id := new.id;
    is_active := new.status = 'accepted';
  elsif tg_table_schema = 'private' and tg_table_name = 'parcel_assignment_attempts' then
    rider_id := new.partner_account_id;
    excluded_domain := 'PARCEL';
    excluded_id := new.id;
    is_active := new.status = 'acknowledged';
  end if;

  if is_active then
    perform private.lock_delivery_partner_active_work(rider_id);
    if private.delivery_partner_has_active_work(
      rider_id,
      excluded_domain,
      excluded_id,
      related_delivery_mission_id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'RIDER_ACTIVE_WORK_CONFLICT',
        detail = 'The delivery partner already has incompatible active work.';
    end if;
  end if;
  return new;
end;
$$;

create trigger delivery_missions_global_active_work
before insert or update of assigned_rider_id, status
on dastak_v1.delivery_missions
for each row execute function private.enforce_delivery_partner_active_work();

create trigger return_missions_global_active_work
before insert or update of assigned_rider_id, status
on dastak_v1.return_missions
for each row execute function private.enforce_delivery_partner_active_work();

create trigger legacy_assignments_global_active_work
before insert or update of partner_account_id, status
on private.delivery_assignment_attempts
for each row execute function private.enforce_delivery_partner_active_work();

create trigger parcel_assignments_global_active_work
before insert or update of partner_account_id, status
on private.parcel_assignment_attempts
for each row execute function private.enforce_delivery_partner_active_work();

-- Do not silently grandfather an incompatible assignment that predates these
-- guards. A recovery mission and its own active return remain one obligation.
do $$
begin
  if exists (
    with active_obligations as (
      select mission.assigned_rider_id as rider_id
      from dastak_v1.delivery_missions mission
      where mission.assigned_rider_id is not null
        and mission.status in (
          'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
          'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
          'DELIVERY_RECOVERY'
        )
        and not (
          mission.status = 'DELIVERY_RECOVERY'
          and exists (
            select 1
            from dastak_v1.return_missions return_mission
            where return_mission.assigned_rider_id = mission.assigned_rider_id
              and return_mission.source_delivery_mission_id = mission.id
              and return_mission.status not in ('COMPLETED', 'CANCELLED')
          )
        )
      union all
      select mission.assigned_rider_id
      from dastak_v1.return_missions mission
      where mission.assigned_rider_id is not null
        and mission.status not in ('COMPLETED', 'CANCELLED')
      union all
      select assignment.partner_account_id
      from private.delivery_assignment_attempts assignment
      where assignment.status = 'accepted'
      union all
      select assignment.partner_account_id
      from private.parcel_assignment_attempts assignment
      where assignment.status = 'acknowledged'
    )
    select 1
    from active_obligations obligation
    group by obligation.rider_id
    having pg_catalog.count(*) > 1
  ) then
    raise exception using
      errcode = '55000',
      message = 'EXISTING_RIDER_ACTIVE_WORK_CONFLICT',
      detail = 'Resolve incompatible existing rider assignments before enabling the invariant.';
  end if;
end;
$$;

-- Put the one shared rider lock around every canonical acquisition path. The
-- original functions retain their mature domain checks, idempotency and side
-- effects; they are no longer executable outside these wrappers.
alter function dastak_v1_api.dastak_v1_accept_delivery_offer(uuid, uuid, text, text)
  rename to dastak_v1_accept_delivery_offer_pre_group_a;

create function dastak_v1_api.dastak_v1_accept_delivery_offer(
  p_account_id uuid,
  p_offer_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  conflict_body jsonb;
begin
  if p_account_id is not null then
    perform private.lock_delivery_partner_active_work(p_account_id);
  end if;
  begin
    return query
      select result.response_body, result.response_status
      from dastak_v1_api.dastak_v1_accept_delivery_offer_pre_group_a(
        p_account_id, p_offer_id, p_idempotency_key, p_request_digest
      ) result;
    return;
  exception when raise_exception then
    if sqlerrm <> 'RIDER_ACTIVE_WORK_CONFLICT' then raise; end if;
  end;

  conflict_body := pg_catalog.jsonb_build_object(
    'error', pg_catalog.jsonb_build_object(
      'code', 'rider_active_work_conflict',
      'message', 'Complete your active delivery before accepting another job.'
    )
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_account_id, 'acceptDeliveryOfferV1', p_idempotency_key,
    extensions.digest(p_request_digest, 'sha256'),
    conflict_body, 409, p_offer_id
  ) on conflict (actor_id, command_name, idempotency_key) do nothing;
  response_body := conflict_body;
  response_status := 409;
  return next;
end;
$$;

alter function dastak_v1_api.assign_return_rider(uuid, uuid, uuid, bigint, text)
  rename to assign_return_rider_pre_group_a;

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
  existing_record dastak_v1.idempotency_records%rowtype;
  mission dastak_v1.return_missions%rowtype;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id,
    'platform.recovery.manage'
  );
  if p_rider_id is null then
    return dastak_v1_api.assign_return_rider_pre_group_a(
      p_actor_id, p_return_mission_id, p_rider_id,
      p_expected_mission_version, p_idempotency_key
    );
  end if;
  perform private.lock_delivery_partner_active_work(p_rider_id);

  -- A completed command must remain replayable even though its own mission is
  -- now active. The original function verifies the request hash.
  select record.* into existing_record
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = 'assignReturnRider'
    and record.idempotency_key = p_idempotency_key;
  if found then
    return dastak_v1_api.assign_return_rider_pre_group_a(
      p_actor_id, p_return_mission_id, p_rider_id,
      p_expected_mission_version, p_idempotency_key
    );
  end if;

  select value.* into mission
  from dastak_v1.return_missions value
  where value.id = p_return_mission_id;
  if mission.id is not null and private.delivery_partner_has_active_work(
    p_rider_id, 'RETURN', mission.id, mission.source_delivery_mission_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'RIDER_ACTIVE_WORK_CONFLICT',
      detail = 'The delivery partner already has incompatible active work.';
  end if;

  return dastak_v1_api.assign_return_rider_pre_group_a(
    p_actor_id, p_return_mission_id, p_rider_id,
    p_expected_mission_version, p_idempotency_key
  );
end;
$$;

alter function private.accept_delivery_assignment_impl(uuid, uuid, text, text)
  rename to accept_delivery_assignment_impl_pre_group_a;

create function private.accept_delivery_assignment_impl(
  p_account_id uuid,
  p_assignment_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  conflict_body jsonb;
begin
  if p_account_id is not null then
    perform private.lock_delivery_partner_active_work(p_account_id);
  end if;
  begin
    return query
      select result.response_body, result.response_status
      from private.accept_delivery_assignment_impl_pre_group_a(
        p_account_id, p_assignment_id, p_idempotency_key, p_request_digest
      ) result;
    return;
  exception when raise_exception then
    if sqlerrm <> 'RIDER_ACTIVE_WORK_CONFLICT' then raise; end if;
  end;

  conflict_body := pg_catalog.jsonb_build_object(
    'error', pg_catalog.jsonb_build_object(
      'code', 'rider_active_work_conflict',
      'message', 'Complete your active delivery before accepting another job.'
    )
  );
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, 'accept_delivery_assignment',
    pg_catalog.btrim(p_idempotency_key), pg_catalog.btrim(p_request_digest),
    conflict_body, 409
  ) on conflict (account_id, function_name, idempotency_key) do nothing;
  response_body := conflict_body;
  response_status := 409;
  return next;
end;
$$;

alter function public.acknowledge_parcel_assignment(uuid, uuid, text, text)
  rename to acknowledge_parcel_assignment_pre_group_a;

create function public.acknowledge_parcel_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  conflict_body jsonb;
begin
  if p_account_id is not null then
    perform private.lock_delivery_partner_active_work(p_account_id);
  end if;
  begin
    return query
      select result.response_body, result.response_status
      from public.acknowledge_parcel_assignment_pre_group_a(
        p_account_id, p_assignment_id, p_idempotency_key, p_request_digest
      ) result;
    return;
  exception when raise_exception then
    if sqlerrm <> 'RIDER_ACTIVE_WORK_CONFLICT' then raise; end if;
  end;

  conflict_body := pg_catalog.jsonb_build_object(
    'error', pg_catalog.jsonb_build_object(
      'code', 'rider_active_work_conflict',
      'message', 'Complete your active delivery before accepting another job.'
    )
  );
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, 'acknowledge_parcel_assignment',
    pg_catalog.btrim(p_idempotency_key), pg_catalog.btrim(p_request_digest),
    conflict_body, 409
  ) on conflict (account_id, function_name, idempotency_key) do nothing;
  response_body := conflict_body;
  response_status := 409;
  return next;
end;
$$;

-- Return missions use the same private tracking sample fields, with exactly
-- one owning mission at a time.
alter table private.delivery_partner_availability
  add column tracking_return_mission_id uuid
  references dastak_v1.return_missions(id);

alter table private.delivery_partner_availability
  drop constraint tracking_sample_complete;

alter table private.delivery_partner_availability
  add constraint tracking_sample_complete check (
    (
      tracking_mission_id is null
      and tracking_return_mission_id is null
      and tracking_location is null
      and tracking_recorded_at is null
      and tracking_received_at is null
      and tracking_accuracy_meters is null
    )
    or (
      (tracking_mission_id is not null) <> (tracking_return_mission_id is not null)
      and tracking_location is not null
      and tracking_recorded_at is not null
      and tracking_received_at is not null
      and tracking_accuracy_meters between 0 and 200
    )
  );

create index delivery_partner_return_tracking_idx
  on private.delivery_partner_availability(tracking_return_mission_id)
  where tracking_return_mission_id is not null;

create function dastak_v1_api.return_arrival_eligibility(
  p_return_mission_id uuid,
  p_return_stop_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  mission dastak_v1.return_missions%rowtype;
  availability private.delivery_partner_availability%rowtype;
  destination extensions.geometry;
  distance_meters double precision;
  reason text := 'LOCATION_REQUIRED';
  valid_until timestamptz;
begin
  select value.* into mission
  from dastak_v1.return_missions value
  where value.id = p_return_mission_id;

  if p_return_stop_id is not null then
    select branch.location into destination
    from dastak_v1.return_stops stop
    join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
    where stop.id = p_return_stop_id
      and stop.return_mission_id = mission.id
      and stop.status = 'PENDING'
      and mission.status = 'RETURNING_TO_MERCHANTS';
  elsif mission.status = 'ASSIGNED' then
    select case
      when pg_catalog.jsonb_typeof(context.delivery_address -> 'latitude') = 'number'
        and pg_catalog.jsonb_typeof(context.delivery_address -> 'longitude') = 'number'
        and (context.delivery_address ->> 'latitude')::double precision between -90 and 90
        and (context.delivery_address ->> 'longitude')::double precision between -180 and 180
      then extensions.st_setsrid(extensions.st_makepoint(
        (context.delivery_address ->> 'longitude')::double precision,
        (context.delivery_address ->> 'latitude')::double precision
      ), 4326)
      else null
    end into destination
    from dastak_v1.order_context_snapshots context
    where context.order_id = mission.order_id;
  end if;

  select value.* into availability
  from private.delivery_partner_availability value
  where value.account_id = mission.assigned_rider_id
    and value.tracking_return_mission_id = mission.id
    and value.tracking_recorded_at >= mission.assigned_at;

  if destination is null then
    reason := 'DESTINATION_UNAVAILABLE';
  elsif availability.tracking_location is not null then
    valid_until := least(
      availability.tracking_recorded_at,
      availability.tracking_received_at
    ) + interval '30 seconds';
    distance_meters := extensions.st_distance(
      availability.tracking_location::extensions.geography,
      destination::extensions.geography
    );
    if valid_until <= pg_catalog.clock_timestamp() then
      reason := 'LOCATION_STALE';
    elsif availability.tracking_accuracy_meters > 35 then
      reason := 'LOCATION_INACCURATE';
    elsif distance_meters > 50 then
      reason := 'TOO_FAR';
    else
      reason := 'ELIGIBLE';
    end if;
  end if;

  return pg_catalog.jsonb_build_object(
    'eligible', reason = 'ELIGIBLE',
    'reason', reason,
    'distanceMeters', distance_meters,
    'radiusMeters', 50,
    'validUntil', valid_until
  );
end;
$$;

create function dastak_v1.enforce_return_arrival()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  eligibility jsonb;
begin
  if tg_table_name = 'return_missions'
    and old.status::text = 'ASSIGNED' and new.status::text = 'AT_CUSTOMER' then
    eligibility := dastak_v1_api.return_arrival_eligibility(new.id, null);
  elsif tg_table_name = 'return_stops'
    and old.status::text = 'PENDING' and new.status::text = 'ARRIVED' then
    eligibility := dastak_v1_api.return_arrival_eligibility(
      new.return_mission_id,
      new.id
    );
  end if;

  if eligibility is not null and not (eligibility ->> 'eligible')::boolean then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_ARRIVAL_LOCATION_REQUIRED',
      detail = 'A fresh, accurate rider location within 50 metres is required.';
  end if;
  return new;
end;
$$;

create trigger return_missions_arrival_proximity
before update of status
on dastak_v1.return_missions
for each row execute function dastak_v1.enforce_return_arrival();

create trigger return_stops_arrival_proximity
before update of status
on dastak_v1.return_stops
for each row execute function dastak_v1.enforce_return_arrival();

-- One authenticated location endpoint now accepts the rider's active normal or
-- return mission. Realtime messages remain coordinate-free invalidations.
create or replace function dastak_v1_api.publish_mission_location(
  p_account_id uuid,
  p_mission_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy double precision,
  p_recorded_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery_mission dastak_v1.delivery_missions%rowtype;
  return_mission dastak_v1.return_missions%rowtype;
  availability private.delivery_partner_availability%rowtype;
  now_at timestamptz := pg_catalog.clock_timestamp();
  is_return boolean := false;
begin
  if not exists (
    select 1
    from private.account_memberships membership
    join private.delivery_partner_profiles profile
      on profile.account_id = membership.account_id
    where membership.account_id = p_account_id
      and membership.role = 'dastak_partner'
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= now_at
      )
  ) then
    raise exception using errcode = '42501', message = 'MISSION_NOT_ASSIGNED';
  end if;
  if p_latitude is null or not (p_latitude between -90 and 90)
    or p_longitude is null or not (p_longitude between -180 and 180)
    or p_accuracy is null or not (p_accuracy between 0 and 200)
    or p_recorded_at is null
    or p_recorded_at > now_at + interval '5 seconds'
    or p_recorded_at < now_at - interval '60 seconds' then
    raise exception using errcode = '22023', message = 'INVALID_LOCATION_SAMPLE';
  end if;

  select value.* into delivery_mission
  from dastak_v1.delivery_missions value
  where value.id = p_mission_id
    and value.assigned_rider_id = p_account_id
  for update;
  if not found then
    select value.* into return_mission
    from dastak_v1.return_missions value
    where value.id = p_mission_id
      and value.assigned_rider_id = p_account_id
    for update;
    if not found then
      raise exception using errcode = '42501', message = 'MISSION_NOT_ASSIGNED';
    end if;
    is_return := true;
  end if;

  if (
    not is_return and delivery_mission.status not in (
      'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
      'DELIVERY_RECOVERY'
    )
  ) or (
    is_return and return_mission.status in ('COMPLETED', 'CANCELLED', 'RIDER_SEARCH')
  ) then
    return dastak_v1_api.delivery_partner_snapshot(p_account_id);
  end if;

  if p_recorded_at < (case when is_return
      then return_mission.assigned_at else delivery_mission.assigned_at end) then
    raise exception using errcode = '22023', message = 'LOCATION_BEFORE_ASSIGNMENT';
  end if;

  insert into private.delivery_partner_availability(account_id)
  values (p_account_id)
  on conflict (account_id) do nothing;
  select value.* into availability
  from private.delivery_partner_availability value
  where value.account_id = p_account_id
  for update;

  if (
    not is_return and availability.tracking_mission_id is distinct from delivery_mission.id
  ) or (
    is_return and availability.tracking_return_mission_id is distinct from return_mission.id
  ) or (
    p_recorded_at > availability.tracking_recorded_at
    and now_at >= availability.tracking_received_at + interval '2 seconds'
  ) then
    update private.delivery_partner_availability value
    set tracking_mission_id = case when is_return then null else delivery_mission.id end,
        tracking_return_mission_id = case when is_return then return_mission.id else null end,
        tracking_location = extensions.st_setsrid(
          extensions.st_makepoint(p_longitude, p_latitude), 4326
        ),
        tracking_accuracy_meters = p_accuracy,
        tracking_recorded_at = p_recorded_at,
        tracking_received_at = now_at,
        tracking_sequence = value.tracking_sequence + 1
    where value.account_id = p_account_id
    returning value.* into availability;

    if not is_return and (
      delivery_mission.rider_last_contact_at is null
      or delivery_mission.rider_last_contact_at < now_at - interval '60 seconds'
    ) then
      update dastak_v1.delivery_missions value
      set rider_last_contact_at = now_at,
          version = value.version + 1
      where value.id = delivery_mission.id;
    end if;

    perform dastak_v1_api.broadcast_delivery_tracking(
      case when is_return then return_mission.order_id else delivery_mission.order_id end,
      availability.tracking_sequence
    );
  end if;

  return dastak_v1_api.delivery_partner_snapshot(p_account_id);
end;
$$;

create or replace function dastak_v1.clear_completed_delivery_tracking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assigned_rider_id is distinct from old.assigned_rider_id
    or new.status in (
      'DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED',
      'REASSIGNING', 'SEARCHING_RIDER'
    ) then
    update private.delivery_partner_availability
    set tracking_mission_id = null,
        tracking_return_mission_id = null,
        tracking_location = null,
        tracking_accuracy_meters = null,
        tracking_recorded_at = null,
        tracking_received_at = null
    where tracking_mission_id = new.id;
  end if;
  return new;
end;
$$;

create function dastak_v1.clear_completed_return_tracking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assigned_rider_id is distinct from old.assigned_rider_id
    or new.status in ('COMPLETED', 'CANCELLED', 'RIDER_SEARCH') then
    update private.delivery_partner_availability
    set tracking_mission_id = null,
        tracking_return_mission_id = null,
        tracking_location = null,
        tracking_accuracy_meters = null,
        tracking_recorded_at = null,
        tracking_received_at = null
    where tracking_return_mission_id = new.id;
  end if;
  return new;
end;
$$;

create trigger clear_completed_return_tracking
after update of status, assigned_rider_id
on dastak_v1.return_missions
for each row execute function dastak_v1.clear_completed_return_tracking();

-- Extend only the rider-owned return projection. Coordinates are not added to
-- broadcasts and raw availability remains private.
alter function dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(uuid)
  rename to delivery_partner_snapshot_pre_launch_payment_pre_group_a;

create function dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(
  p_rider_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
  mission dastak_v1.return_missions%rowtype;
  customer_arrival jsonb;
  projected_stops jsonb;
begin
  result := dastak_v1_api.delivery_partner_snapshot_pre_launch_payment_pre_group_a(
    p_rider_id
  );
  if result -> 'returnMission' is null
    or result -> 'returnMission' = 'null'::jsonb then
    return result;
  end if;

  select value.* into mission
  from dastak_v1.return_missions value
  where value.id = (result #>> '{returnMission,id}')::uuid
    and value.assigned_rider_id = p_rider_id;
  if not found then
    return pg_catalog.jsonb_set(result, '{returnMission}', 'null'::jsonb);
  end if;

  customer_arrival := dastak_v1_api.return_arrival_eligibility(mission.id, null);
  select coalesce(pg_catalog.jsonb_agg(
    source.stop_value || pg_catalog.jsonb_build_object(
      'branch', (source.stop_value -> 'branch') || pg_catalog.jsonb_build_object(
        'location', case when branch.location is null then null else
          pg_catalog.jsonb_build_object(
            'latitude', extensions.st_y(branch.location),
            'longitude', extensions.st_x(branch.location)
          ) end
      ),
      'arrival', eligibility.value,
      'canArrive', (eligibility.value ->> 'eligible')::boolean
    ) order by stop.stop_sequence
  ), '[]'::jsonb) into projected_stops
  from pg_catalog.jsonb_array_elements(result #> '{returnMission,stops}')
    as source(stop_value)
  join dastak_v1.return_stops stop
    on stop.id = (source.stop_value ->> 'id')::uuid
  join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
  cross join lateral (
    select dastak_v1_api.return_arrival_eligibility(mission.id, stop.id) as value
  ) eligibility;

  result := pg_catalog.jsonb_set(
    result,
    '{returnMission}',
    (result -> 'returnMission') || pg_catalog.jsonb_build_object(
      'customerArrival', customer_arrival,
      'canArriveCustomer', (customer_arrival ->> 'eligible')::boolean,
      'stops', projected_stops
    )
  );
  return result;
end;
$$;

-- Pre-repair implementations are owner-only. This closes every service-role
-- bypass while allowing the security-definer wrappers to retain old behavior.
revoke all on function
  private.delivery_partner_active_work(uuid, text, uuid, uuid),
  private.delivery_partner_has_active_work(uuid, text, uuid, uuid),
  private.lock_delivery_partner_active_work(uuid),
  private.enforce_delivery_partner_active_work(),
  dastak_v1.enforce_return_arrival(),
  dastak_v1.clear_completed_return_tracking()
from public, anon, authenticated, service_role;

revoke all on function
  dastak_v1_api.dastak_v1_accept_delivery_offer_pre_group_a(uuid, uuid, text, text),
  dastak_v1_api.assign_return_rider_pre_group_a(uuid, uuid, uuid, bigint, text),
  private.accept_delivery_assignment_impl_pre_group_a(uuid, uuid, text, text),
  public.acknowledge_parcel_assignment_pre_group_a(uuid, uuid, text, text),
  dastak_v1_api.delivery_partner_snapshot_pre_launch_payment_pre_group_a(uuid)
from public, anon, authenticated, service_role;

revoke all on function
  dastak_v1_api.dastak_v1_accept_delivery_offer(uuid, uuid, text, text),
  private.accept_delivery_assignment_impl(uuid, uuid, text, text),
  public.acknowledge_parcel_assignment(uuid, uuid, text, text),
  dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(uuid),
  dastak_v1_api.publish_mission_location(uuid, uuid, double precision, double precision, double precision, timestamptz),
  dastak_v1_api.return_arrival_eligibility(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function
  dastak_v1_api.dastak_v1_accept_delivery_offer(uuid, uuid, text, text),
  private.accept_delivery_assignment_impl(uuid, uuid, text, text),
  public.acknowledge_parcel_assignment(uuid, uuid, text, text),
  dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(uuid),
  dastak_v1_api.publish_mission_location(uuid, uuid, double precision, double precision, double precision, timestamptz),
  dastak_v1_api.return_arrival_eligibility(uuid, uuid)
to service_role;

revoke all on function
  dastak_v1_api.assign_return_rider(uuid, uuid, uuid, bigint, text)
from public, anon, authenticated, service_role;
grant execute on function
  dastak_v1_api.assign_return_rider(uuid, uuid, uuid, bigint, text)
to authenticated;

comment on function private.delivery_partner_active_work(uuid, text, uuid, uuid) is
  'Authoritative cross-domain active delivery work predicate; owner-only.';
comment on function private.lock_delivery_partner_active_work(uuid) is
  'Serializes every active-work acquisition for one delivery partner.';
comment on function dastak_v1_api.return_arrival_eligibility(uuid, uuid) is
  'Server-authoritative fresh, accurate, within-50-metre eligibility for return customer or merchant arrival.';
