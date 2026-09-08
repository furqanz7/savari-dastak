-- Mission-scoped latest location, using the existing private availability row and
-- account broadcast channels. No route history or client-readable GPS table.
alter table private.delivery_partner_availability
  add column tracking_mission_id uuid references dastak_v1.delivery_missions(id),
  add column tracking_location extensions.geometry(Point,4326),
  add column tracking_accuracy_meters double precision,
  add column tracking_recorded_at timestamptz,
  add column tracking_received_at timestamptz,
  add column tracking_sequence bigint not null default 0;
create index delivery_partner_tracking_mission_idx
  on private.delivery_partner_availability(tracking_mission_id)
  where tracking_mission_id is not null;
alter table private.delivery_partner_availability add constraint tracking_sample_complete check (
  (tracking_mission_id is null and tracking_location is null and tracking_recorded_at is null
    and tracking_received_at is null and tracking_accuracy_meters is null)
  or (tracking_mission_id is not null and tracking_location is not null
    and tracking_recorded_at is not null and tracking_received_at is not null
    and tracking_accuracy_meters between 0 and 200));

alter table dastak_v1.verification_handoffs
  add column pin_verified_at timestamptz,
  add column pin_verified_by uuid references public.accounts(id);
create index verification_handoff_pin_actor_idx on dastak_v1.verification_handoffs(pin_verified_by);
alter table dastak_v1.verification_handoffs add constraint delivery_pin_verification_complete check (
  (pin_verified_at is null and pin_verified_by is null)
  or (pin_verified_at is not null and pin_verified_by is not null and handoff_type = 'RIDER_TO_CUSTOMER'));

-- This helper is private. Callers must bind the authenticated actor first.
create function dastak_v1_api.arrival_eligibility(p_mission_id uuid, p_stop_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  m dastak_v1.delivery_missions%rowtype;
  a private.delivery_partner_availability%rowtype;
  destination extensions.geometry;
  distance_m double precision;
  reason text := 'LOCATION_REQUIRED';
  valid_until timestamptz;
begin
  select * into m from dastak_v1.delivery_missions where id = p_mission_id;
  if p_stop_id is not null then
    select b.location into destination from dastak_v1.delivery_stops s
    join dastak_v1.merchant_branches b on b.id = s.branch_id
    where s.id = p_stop_id and s.mission_id = m.id and s.status = 'PENDING'
      and m.status in ('EN_ROUTE_TO_PICKUPS','PICKUP_IN_PROGRESS');
  elsif m.status = 'OUT_FOR_DELIVERY' then
    select extensions.st_setsrid(extensions.st_makepoint(
      (c.delivery_address->>'longitude')::double precision,
      (c.delivery_address->>'latitude')::double precision),4326)
    into destination from dastak_v1.order_context_snapshots c where c.order_id = m.order_id;
  end if;
  select * into a from private.delivery_partner_availability
  where account_id = m.assigned_rider_id and tracking_mission_id = m.id
    and tracking_recorded_at >= m.assigned_at;
  if destination is null then reason := 'DESTINATION_UNAVAILABLE';
  elsif a.tracking_location is not null then
    valid_until := least(a.tracking_recorded_at, a.tracking_received_at) + interval '30 seconds';
    distance_m := extensions.st_distance(a.tracking_location::extensions.geography,
      destination::extensions.geography);
    if valid_until <= pg_catalog.clock_timestamp() then reason := 'LOCATION_STALE';
    elsif a.tracking_accuracy_meters > 35 then reason := 'LOCATION_INACCURATE';
    elsif distance_m > 50 then reason := 'TOO_FAR';
    else reason := 'ELIGIBLE'; end if;
  end if;
  return pg_catalog.jsonb_build_object('eligible', reason = 'ELIGIBLE', 'reason', reason,
    'distanceMeters', distance_m, 'radiusMeters', 50, 'validUntil', valid_until);
end;
$$;

-- Trigger-level enforcement also covers old clients and alternate command paths.
create function dastak_v1.enforce_delivery_arrival() returns trigger
language plpgsql security definer set search_path = '' as $$
declare eligibility jsonb;
begin
  if tg_table_name = 'delivery_stops' then
    if new.status = 'ARRIVED' and old.status = 'PENDING' then
      eligibility := dastak_v1_api.arrival_eligibility(new.mission_id,new.id);
    end if;
  elsif new.status = 'ARRIVED' and old.status = 'OUT_FOR_DELIVERY' then
    eligibility := dastak_v1_api.arrival_eligibility(new.id,null);
  end if;
  if eligibility is not null and not (eligibility->>'eligible')::boolean then
    raise exception using errcode = 'P0001', message = 'ARRIVAL_LOCATION_REQUIRED',
      detail = 'A fresh, accurate rider location within 50 metres is required.';
  end if;
  return new;
end;
$$;
create trigger delivery_arrival_proximity before update on dastak_v1.delivery_missions
  for each row execute function dastak_v1.enforce_delivery_arrival();
create trigger pickup_arrival_proximity before update on dastak_v1.delivery_stops
  for each row execute function dastak_v1.enforce_delivery_arrival();

create function dastak_v1.enforce_delivery_handoff_sequence() returns trigger
language plpgsql security definer set search_path = '' as $$
declare h dastak_v1.verification_handoffs%rowtype; m dastak_v1.delivery_missions%rowtype;
begin
  if tg_table_name = 'verification_handoffs' then
    if old.pin_verified_at is not null and (new.pin_verified_at is distinct from old.pin_verified_at
      or new.pin_verified_by is distinct from old.pin_verified_by) then
      raise exception 'verified delivery PIN is immutable';
    end if;
    if new.pin_verified_at is not null and old.pin_verified_at is null then
      select * into m from dastak_v1.delivery_missions where id = new.mission_id;
      if m.status <> 'ARRIVED' or m.assigned_rider_id is distinct from new.pin_verified_by
        or old.status <> 'ACTIVE' or new.pin_verified_at < m.arrived_customer_at then
        raise exception 'DELIVERY_ARRIVAL_REQUIRED';
      end if;
    end if;
  else
    select * into h from dastak_v1.verification_handoffs
      where mission_id = new.mission_id and handoff_type = 'RIDER_TO_CUSTOMER';
    select * into m from dastak_v1.delivery_missions where id = new.mission_id;
    if h.pin_verified_at is null or h.pin_verified_by is distinct from m.assigned_rider_id
      or m.status <> 'ARRIVED' then raise exception 'DELIVERY_PIN_REQUIRED'; end if;
    if tg_table_name = 'delivery_evidence' then
      if new.captured_at < h.pin_verified_at or new.captured_by is distinct from h.pin_verified_by then
        raise exception 'DELIVERY_PIN_REQUIRED';
      end if;
    else
      if not exists (select 1 from dastak_v1.delivery_evidence e
        where e.verification_handoff_id = h.id and e.captured_by = h.pin_verified_by
          and e.captured_at >= h.pin_verified_at and e.captured_at <= new.attempted_at
          and dastak_v1_api.delivery_evidence_covers_packages(e.id,m.id,m.assigned_rider_id)) then
        raise exception 'DELIVERY_PHOTO_REQUIRED';
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger delivery_pin_sequence before update on dastak_v1.verification_handoffs
  for each row execute function dastak_v1.enforce_delivery_handoff_sequence();
create trigger delivery_photo_sequence before insert on dastak_v1.delivery_evidence
  for each row execute function dastak_v1.enforce_delivery_handoff_sequence();
create trigger delivery_collection_sequence before insert on dastak_v1.launch_payment_collection_attempts
  for each row execute function dastak_v1.enforce_delivery_handoff_sequence();

-- No location coordinates in broadcasts. Snapshot authorization is rechecked on
-- every refresh, including merchant branch permission and changed assignments.
create function dastak_v1_api.broadcast_delivery_tracking(p_order_id uuid, p_sequence bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare recipient uuid;
begin
  for recipient in
    select customer_id from dastak_v1.orders where id = p_order_id
    union
    select u.account_id from dastak_v1.fulfilments f
    join dastak_v1.merchant_branches b on b.id = f.branch_id
    join dastak_v1.merchant_users u on u.organization_id = b.organization_id and u.status = 'ACTIVE'
    where f.order_id = p_order_id and f.status <> 'RELEASED'
      and dastak_v1_api.actor_has_merchant_permission(u.account_id,b.organization_id,
        'merchant.fulfilment.manage',b.id)
  loop
    perform private.send_order_change(recipient,'merchant_order',p_order_id,p_sequence);
  end loop;
end;
$$;

create function dastak_v1_api.delivery_tracking_json(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m dastak_v1.delivery_missions%rowtype; a private.delivery_partner_availability%rowtype;
  rider_name text;
begin
  select * into m from dastak_v1.delivery_missions where order_id = p_order_id
    and assigned_rider_id is not null
    and status in ('ASSIGNED','EN_ROUTE_TO_PICKUPS','PICKUP_IN_PROGRESS','ALL_PACKAGES_PICKED_UP',
      'OUT_FOR_DELIVERY','ARRIVED','DELIVERY_RECOVERY') order by created_at desc limit 1;
  if not found then return null; end if;
  select display_name into rider_name from public.accounts where id = m.assigned_rider_id;
  select * into a from private.delivery_partner_availability where account_id = m.assigned_rider_id
    and tracking_mission_id = m.id and tracking_recorded_at >= m.assigned_at;
  return pg_catalog.jsonb_build_object('missionId',m.id,'phase',m.status,
    'riderName',coalesce(nullif(rider_name,''),'Delivery partner'),'transportType',m.assigned_transport_type,
    'location',case when a.tracking_location is null then null else pg_catalog.jsonb_build_object(
      'latitude',extensions.st_y(a.tracking_location),'longitude',extensions.st_x(a.tracking_location)) end,
    'recordedAt',a.tracking_recorded_at,'receivedAt',a.tracking_received_at,
    'accuracyMeters',a.tracking_accuracy_meters,'sequence',a.tracking_sequence,
    'liveUntil',least(a.tracking_recorded_at,a.tracking_received_at) + interval '30 seconds',
    'serverTime',pg_catalog.now());
end;
$$;

create function dastak_v1_api.publish_mission_location(p_account_id uuid,p_mission_id uuid,
  p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_recorded_at timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m dastak_v1.delivery_missions%rowtype; a private.delivery_partner_availability%rowtype;
  now_at timestamptz := pg_catalog.clock_timestamp();
begin
  if not exists(select 1 from private.account_memberships membership
    join private.delivery_partner_profiles profile on profile.account_id=membership.account_id
    where membership.account_id=p_account_id and membership.role='dastak_partner'
      and membership.approved_at is not null
      and (membership.suspended_until is null or membership.suspended_until <= now_at)) then
    raise exception using errcode='42501',message='MISSION_NOT_ASSIGNED';
  end if;
  if p_latitude is null or not (p_latitude between -90 and 90)
    or p_longitude is null or not (p_longitude between -180 and 180)
    or p_accuracy is null or not (p_accuracy between 0 and 200)
    or p_recorded_at is null or p_recorded_at > now_at + interval '5 seconds'
    or p_recorded_at < now_at - interval '60 seconds' then
    raise exception using errcode = '22023', message = 'INVALID_LOCATION_SAMPLE';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dastak-v1-rider:'||p_account_id::text,0));
  select * into m from dastak_v1.delivery_missions where id = p_mission_id
    and assigned_rider_id = p_account_id for update;
  if not found then raise exception using errcode = '42501', message = 'MISSION_NOT_ASSIGNED'; end if;
  if m.status not in ('ASSIGNED','EN_ROUTE_TO_PICKUPS','PICKUP_IN_PROGRESS','ALL_PACKAGES_PICKED_UP',
    'OUT_FOR_DELIVERY','ARRIVED','DELIVERY_RECOVERY') then
    return pg_catalog.jsonb_build_object('currentMission',null,'offer',null);
  end if;
  if p_recorded_at < m.assigned_at then raise exception 'LOCATION_BEFORE_ASSIGNMENT'; end if;
  -- Availability expires independently. Tracking must continue for the active job.
  insert into private.delivery_partner_availability(account_id) values(p_account_id)
    on conflict(account_id) do nothing;
  select * into a from private.delivery_partner_availability where account_id = p_account_id for update;
  if a.tracking_mission_id is distinct from m.id or (p_recorded_at > a.tracking_recorded_at
    and now_at >= a.tracking_received_at + interval '2 seconds') then
    update private.delivery_partner_availability set tracking_mission_id=m.id,
      tracking_location=extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326),
      tracking_accuracy_meters=p_accuracy,tracking_recorded_at=p_recorded_at,tracking_received_at=now_at,
      tracking_sequence=tracking_sequence+1 where account_id=p_account_id returning * into a;
    -- Keep operational liveness current without pretending that GPS is progress.
    if m.rider_last_contact_at is null or m.rider_last_contact_at < now_at - interval '60 seconds' then
      update dastak_v1.delivery_missions set rider_last_contact_at=now_at,version=version+1 where id=m.id;
    end if;
    perform dastak_v1_api.broadcast_delivery_tracking(m.order_id,a.tracking_sequence);
  end if;
  return pg_catalog.jsonb_build_object('currentMission',dastak_v1_api.rider_mission_json(p_account_id,m.id),
    'offer',null);
end;
$$;
create function public.dastak_v1_publish_mission_location(p_account_id uuid,p_mission_id uuid,
  p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_recorded_at timestamptz)
returns jsonb language sql security invoker set search_path = '' as $$
  select dastak_v1_api.publish_mission_location(p_account_id,p_mission_id,p_latitude,p_longitude,p_accuracy,p_recorded_at);
$$;

-- Clear the last sample when custody assignment ends or moves to another rider.
create function dastak_v1.clear_completed_delivery_tracking() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.assigned_rider_id is distinct from old.assigned_rider_id
    or new.status in ('DELIVERED','CANCELLED','RECOVERED_RETURNED','REASSIGNING','SEARCHING_RIDER') then
    update private.delivery_partner_availability set tracking_mission_id=null,tracking_location=null,
      tracking_accuracy_meters=null,tracking_recorded_at=null,tracking_received_at=null
    where tracking_mission_id=new.id;
  end if;
  return new;
end;
$$;
create trigger clear_completed_delivery_tracking after update of status,assigned_rider_id
  on dastak_v1.delivery_missions for each row execute function dastak_v1.clear_completed_delivery_tracking();

-- Same-state liveness updates must not be mistaken for a lifecycle transition.
CREATE OR REPLACE FUNCTION dastak_v1.guard_delivery_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    (old.status in ('SEARCHING_RIDER', 'ASSIGNED', 'EN_ROUTE_TO_PICKUPS',
      'PICKUP_IN_PROGRESS', 'REASSIGNING') and new.status = 'CANCELLED'
      and old.first_package_picked_up_at is null
      and dastak_v1_api.order_cancellation_active(new.order_id))
    or (old.status = 'SEARCHING_RIDER' and new.status in ('ASSIGNED', 'CANCELLED'))
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
  if new.status = 'OUT_FOR_DELIVERY' and new.status is distinct from old.status and (
    old.status not in ('ALL_PACKAGES_PICKED_UP', 'DELIVERY_RECOVERY')
    or new.all_packages_picked_up_at is null or new.out_for_delivery_at is null
  ) then
    raise exception 'OUT_FOR_DELIVERY requires every pickup and an authoritative timestamp';
  end if;
  if new.status = 'ARRIVED' and new.status is distinct from old.status and (
    old.status not in ('OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY')
    or new.arrived_customer_at is null
  ) then
    raise exception 'ARRIVED requires the final-delivery stage';
  end if;
  if new.status = 'DELIVERED' and new.status is distinct from old.status and (
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
$function$

;

-- Separate PIN verification from irreversible completion; retain existing locks,
-- attempt limits, package custody, financial ledger and outbox transitions.
CREATE OR REPLACE FUNCTION dastak_v1_api.dastak_v1_advance_final_delivery(p_account_id uuid, p_mission_id uuid, p_action text, p_object_path text, p_verification_code text, p_idempotency_key text, p_request_digest text)
 RETURNS TABLE(response_body jsonb, response_status integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_command text := 'advanceFinalDeliveryV1:' || coalesce(p_action, 'INVALID');
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
  v_evidence dastak_v1.delivery_evidence%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_package_count integer;
  v_updated_count integer;
  v_attempt_limit integer;
  v_failed_attempts integer;
  v_storage_metadata jsonb;
  v_content_type text;
  v_content_length bigint;
begin
  if p_account_id is null or p_mission_id is null
    or p_action not in (
      'START_FINAL_DELIVERY', 'ARRIVE_CUSTOMER',
      'ADD_DELIVERY_EVIDENCE', 'VERIFY_DELIVERY', 'VERIFY_CUSTOMER_PIN', 'COMPLETE_DELIVERY'
    )
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or (
      p_action = 'ADD_DELIVERY_EVIDENCE' and (
        p_object_path is null
        or p_object_path !~ (
          '^rider-delivery/' || p_account_id::text
          || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
        )
      )
    )
    or (p_action <> 'ADD_DELIVERY_EVIDENCE' and p_object_path is not null)
    or (
      p_action in ('VERIFY_DELIVERY','VERIFY_CUSTOMER_PIN')
      and (p_verification_code is null or p_verification_code !~ '^[0-9]{6}$')
    )
    or (p_action not in ('VERIFY_DELIVERY','VERIFY_CUSTOMER_PIN') and p_verification_code is not null) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The final-delivery action is invalid.'
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
        'code', 'mission_not_found',
        'message', 'This delivery mission is unavailable.'
      )
    );
    response_status := 404;
  else
    select customer_order.* into v_order
    from dastak_v1.orders customer_order
    where customer_order.id = v_mission.order_id
    for update;
    perform 1
    from dastak_v1.packages package
    where package.order_id = v_order.id
    order by package.id
    for update;
    select handoff.* into v_handoff
    from dastak_v1.verification_handoffs handoff
    where handoff.mission_id = v_mission.id
      and handoff.order_id = v_order.id
      and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
    for update;
    select count(*) into v_package_count
    from dastak_v1.packages package
    where package.order_id = v_order.id;

    if p_action = 'START_FINAL_DELIVERY' then
      perform dastak_v1_api.delivery_verification_attempt_limit();
      if v_mission.status <> 'ALL_PACKAGES_PICKED_UP'
        or v_order.status <> 'PICKUP_IN_PROGRESS' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'Final delivery cannot start from this mission state.'
          )
        );
        response_status := 409;
      elsif v_handoff.id is not null then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_already_started',
            'message', 'The parent-order delivery handoff already exists.'
          )
        );
        response_status := 409;
      elsif v_package_count < 1
        or exists (
          select 1
          from dastak_v1.packages package
          where package.order_id = v_order.id
            and (
              package.status <> 'PICKED_UP'
              or package.current_custody_owner_type <> 'RIDER'
              or package.current_custody_owner_id is distinct from p_account_id
            )
        )
        or exists (
          select 1
          from dastak_v1.fulfilments fulfilment
          where fulfilment.order_id = v_order.id
            and fulfilment.status <> 'PICKED_UP'
        )
        or exists (
          select 1
          from dastak_v1.delivery_stops stop
          where stop.mission_id = v_mission.id
            and stop.status <> 'COMPLETED'
        ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_incomplete_custody',
            'message', 'Every required package must be in the assigned rider custody.'
          )
        );
        response_status := 409;
      else
        v_handoff.id := gen_random_uuid();
        insert into dastak_v1.verification_handoffs (
          id, order_id, mission_id, fulfilment_id, handoff_type, status,
          code_version, code_digest, activated_at
        ) values (
          v_handoff.id, v_order.id, v_mission.id, null,
          'RIDER_TO_CUSTOMER', 'ACTIVE', 1,
          private.dastak_v1_handoff_digest(private.dastak_v1_handoff_code(
            v_handoff.id, 'RIDER_TO_CUSTOMER', 1
          )),
          v_now
        ) returning * into v_handoff;
        perform pg_catalog.set_config(
          'dastak_v1.final_delivery_verification_id', v_handoff.id::text, true
        );
        update dastak_v1.packages package
        set status = 'IN_TRANSIT', version = package.version + 1
        where package.order_id = v_order.id
          and package.status = 'PICKED_UP'
          and package.current_custody_owner_type = 'RIDER'
          and package.current_custody_owner_id = p_account_id;
        get diagnostics v_updated_count = row_count;
        if v_updated_count <> v_package_count then
          raise exception 'final delivery package transition was not complete';
        end if;
        update dastak_v1.delivery_missions mission
        set status = 'OUT_FOR_DELIVERY', out_for_delivery_at = v_now,
            version = mission.version + 1
        where mission.id = v_mission.id
        returning * into v_mission;
        update dastak_v1.orders customer_order
        set status = 'OUT_FOR_DELIVERY', version = customer_order.version + 1
        where customer_order.id = v_order.id
        returning * into v_order;
        insert into dastak_v1.order_state_journal (
          order_id, from_status, to_status, order_version,
          command_name, reason, metadata
        ) values (
          v_order.id, 'PICKUP_IN_PROGRESS', 'OUT_FOR_DELIVERY', v_order.version,
          'startFinalDelivery',
          'Every required package is in the assigned rider custody.',
          pg_catalog.jsonb_build_object(
            'missionId', v_mission.id,
            'handoffId', v_handoff.id,
            'packageCount', v_package_count,
            'allPackagesPickedUpAt', v_mission.all_packages_picked_up_at
          )
        );
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_mission.id::text || ':ALL_PACKAGES_PICKED_UP:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'ALL_PACKAGES_PICKED_UP', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'missionId', v_mission.id,
            'packageCount', v_package_count,
            'pickedUpAt', v_mission.all_packages_picked_up_at
          )
        ), (
          v_order.id::text || ':ORDER_OUT_FOR_DELIVERY:' || v_order.version::text,
          'ORDER', v_order.id, v_order.version,
          'ORDER_OUT_FOR_DELIVERY', p_account_id,
          pg_catalog.jsonb_build_object(
            'missionId', v_mission.id,
            'handoffId', v_handoff.id,
            'packageCount', v_package_count,
            'outForDeliveryAt', v_mission.out_for_delivery_at
          )
        );
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'ORDER_OUT_FOR_DELIVERY', 'order', v_order.id,
          pg_catalog.jsonb_build_object(
            'missionId', v_mission.id,
            'handoffId', v_handoff.id,
            'packageCount', v_package_count
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;

    elsif p_action = 'ARRIVE_CUSTOMER' then
      if v_mission.status <> 'OUT_FOR_DELIVERY'
        or v_order.status <> 'OUT_FOR_DELIVERY'
        or v_handoff.id is null
        or v_handoff.status not in ('ACTIVE', 'BLOCKED') then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'Customer arrival is unavailable for this mission.'
          )
        );
        response_status := 409;
      else
        update dastak_v1.delivery_missions mission
        set status = 'ARRIVED', arrived_customer_at = v_now,
            version = mission.version + 1
        where mission.id = v_mission.id
        returning * into v_mission;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_mission.id::text || ':RIDER_ARRIVED_CUSTOMER:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'RIDER_ARRIVED_CUSTOMER', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'missionId', v_mission.id,
            'arrivedAt', v_mission.arrived_customer_at
          )
        );
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'RIDER_ARRIVED_CUSTOMER', 'delivery_mission', v_mission.id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'arrivedAt', v_mission.arrived_customer_at
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;

    elsif p_action = 'ADD_DELIVERY_EVIDENCE' then
      if v_mission.status <> 'ARRIVED'
        or v_order.status <> 'OUT_FOR_DELIVERY'
        or v_handoff.id is null
        or v_handoff.status not in ('ACTIVE', 'BLOCKED') then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'Delivery evidence can be captured only after customer arrival.'
          )
        );
        response_status := 409;
      elsif v_package_count < 1 or exists (
        select 1
        from dastak_v1.packages package
        where package.order_id = v_order.id
          and (
            package.status <> 'IN_TRANSIT'
            or package.current_custody_owner_type <> 'RIDER'
            or package.current_custody_owner_id is distinct from p_account_id
          )
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_incomplete_custody',
            'message', 'Every required package must remain in assigned Rider custody.'
          )
        );
        response_status := 409;
      elsif exists (
        select 1 from dastak_v1.delivery_evidence evidence
        where evidence.object_path = p_object_path
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_evidence_already_recorded',
            'message', 'This immutable evidence object was already recorded.'
          )
        );
        response_status := 409;
      else
        select object.metadata into v_storage_metadata
        from storage.objects object
        where object.bucket_id = 'dastak-evidence'
          and object.name = p_object_path
          and (
            object.owner_id = p_account_id::text
            or object.owner = p_account_id
          );
        if not found then
          response_body := pg_catalog.jsonb_build_object(
            'error', pg_catalog.jsonb_build_object(
              'code', 'delivery_evidence_upload_missing',
              'message', 'The rider package photo upload was not found.'
            )
          );
          response_status := 409;
        else
          v_content_type := coalesce(
            v_storage_metadata ->> 'mimetype',
            case
              when p_object_path ~ '\.(jpg|jpeg)$' then 'image/jpeg'
              when p_object_path ~ '\.png$' then 'image/png'
              when p_object_path ~ '\.heic$' then 'image/heic'
            end
          );
          if v_content_type not in ('image/jpeg', 'image/png', 'image/heic') then
            response_body := pg_catalog.jsonb_build_object(
              'error', pg_catalog.jsonb_build_object(
                'code', 'delivery_evidence_invalid',
                'message', 'Delivery evidence must be an image.'
              )
            );
            response_status := 400;
          else
            if coalesce(v_storage_metadata ->> 'size', '') ~ '^[0-9]+$' then
              v_content_length := (v_storage_metadata ->> 'size')::bigint;
            end if;
            if v_content_length is not null
              and v_content_length not between 1 and 10485760 then
              response_body := pg_catalog.jsonb_build_object(
                'error', pg_catalog.jsonb_build_object(
                  'code', 'delivery_evidence_invalid',
                  'message', 'Delivery evidence must be an image up to 10 MB.'
                )
              );
              response_status := 400;
            else
              insert into dastak_v1.delivery_evidence (
                order_id, mission_id, verification_handoff_id, evidence_type,
                object_path, content_type, content_length_bytes,
                captured_by, captured_at
              ) values (
                v_order.id, v_mission.id, v_handoff.id,
                'RIDER_PRE_DELIVERY_PHOTO', p_object_path, v_content_type,
                v_content_length, p_account_id, v_now
              ) returning * into v_evidence;
              insert into dastak_v1.delivery_evidence_packages (
                evidence_id, package_id, order_id, mission_id, linked_at
              )
              select v_evidence.id, package.id, v_order.id, v_mission.id, v_now
              from dastak_v1.packages package
              where package.order_id = v_order.id
              order by package.id;
              get diagnostics v_updated_count = row_count;
              if v_updated_count <> v_package_count then
                raise exception 'delivery evidence package context was not complete';
              end if;
              insert into dastak_v1.domain_events_outbox (
                event_key, aggregate_type, aggregate_id, aggregate_version,
                event_type, actor_id, payload
              ) values (
                v_evidence.id::text || ':RIDER_PRE_DELIVERY_EVIDENCE_CAPTURED:1',
                'DELIVERY_EVIDENCE', v_evidence.id, 1,
                'RIDER_PRE_DELIVERY_EVIDENCE_CAPTURED', p_account_id,
                pg_catalog.jsonb_build_object(
                  'orderId', v_order.id,
                  'missionId', v_mission.id,
                  'handoffId', v_handoff.id,
                  'evidenceId', v_evidence.id,
                  'packageCount', v_package_count,
                  'capturedAt', v_evidence.captured_at
                )
              );
              insert into dastak_v1.audit_events (
                actor_id, action, resource_type, resource_id, metadata
              ) values (
                p_account_id, 'RIDER_PRE_DELIVERY_EVIDENCE_CAPTURED',
                'delivery_evidence', v_evidence.id,
                pg_catalog.jsonb_build_object(
                  'orderId', v_order.id,
                  'missionId', v_mission.id,
                  'handoffId', v_handoff.id,
                  'packageCount', v_package_count,
                  'objectPath', p_object_path
                )
              );
              response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
              response_status := 200;
            end if;
          end if;
        end if;
      end if;

    elsif p_action in ('VERIFY_DELIVERY','VERIFY_CUSTOMER_PIN','COMPLETE_DELIVERY') then
      if v_handoff.id is null
        or v_mission.status in (
          'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
          'ALL_PACKAGES_PICKED_UP'
        ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_code_inactive',
            'message', 'The parent-order delivery code is not active.'
          )
        );
        response_status := 409;
      elsif v_handoff.status = 'CONSUMED' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_code_consumed',
            'message', 'This delivery code was already consumed.'
          )
        );
        response_status := 409;
      elsif v_handoff.status = 'OVERRIDDEN' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_handoff_overridden',
            'message', 'Operations already completed this exceptional handoff.'
          )
        );
        response_status := 409;
      elsif v_handoff.status = 'BLOCKED' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_code_blocked',
            'message', 'Normal verification is blocked. Report the problem to Operations.'
          )
        );
        response_status := 409;
      elsif v_mission.status <> 'ARRIVED'
        or v_order.status <> 'OUT_FOR_DELIVERY'
        or v_handoff.status <> 'ACTIVE' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'This delivery cannot be verified now.'
          )
        );
        response_status := 409;
      elsif v_package_count < 1 or exists (
        select 1
        from dastak_v1.packages package
        where package.order_id = v_order.id
          and (
            package.status <> 'IN_TRANSIT'
            or package.current_custody_owner_type <> 'RIDER'
            or package.current_custody_owner_id is distinct from p_account_id
          )
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_incomplete_custody',
            'message', 'Every required package must remain in assigned Rider custody.'
          )
        );
        response_status := 409;
      elsif p_action <> 'VERIFY_CUSTOMER_PIN' and v_handoff.pin_verified_at is null then
        response_body := pg_catalog.jsonb_build_object('error',pg_catalog.jsonb_build_object(
          'code','delivery_pin_required','message','Verify the customer PIN before completing delivery.'));
        response_status := 409;
      elsif p_action <> 'VERIFY_CUSTOMER_PIN' and not exists (
        select 1
        from dastak_v1.delivery_evidence evidence
        where evidence.mission_id = v_mission.id
          and evidence.verification_handoff_id = v_handoff.id
          and evidence.captured_by = p_account_id
          and dastak_v1_api.delivery_evidence_covers_packages(
            evidence.id, v_mission.id, p_account_id
          )
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_evidence_required',
            'message', 'Capture the required package photo before customer handoff.'
          )
        );
        response_status := 409;
      elsif p_action = 'VERIFY_CUSTOMER_PIN' and v_handoff.pin_verified_at is null
        and v_handoff.code_digest <> private.dastak_v1_handoff_digest(
        p_verification_code
      ) then
        v_attempt_limit := dastak_v1_api.delivery_verification_attempt_limit();
        v_failed_attempts := v_handoff.failed_attempts + 1;
        update dastak_v1.verification_handoffs handoff
        set failed_attempts = v_failed_attempts,
            status = case when v_failed_attempts >= v_attempt_limit
              then 'BLOCKED' else handoff.status end,
            blocked_at = case when v_failed_attempts >= v_attempt_limit
              then v_now else null end,
            version = handoff.version + 1
        where handoff.id = v_handoff.id
        returning * into v_handoff;
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'DELIVERY_CODE_REJECTED',
          'verification_handoff', v_handoff.id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'missionId', v_mission.id,
            'failedAttempts', v_failed_attempts,
            'blocked', v_failed_attempts >= v_attempt_limit
          )
        );
        if v_failed_attempts >= v_attempt_limit then
          insert into dastak_v1.domain_events_outbox (
            event_key, aggregate_type, aggregate_id, aggregate_version,
            event_type, actor_id, payload
          ) values (
            v_handoff.id::text || ':FINAL_DELIVERY_VERIFICATION_BLOCKED:'
              || v_handoff.version::text,
            'VERIFICATION_HANDOFF', v_handoff.id, v_handoff.version,
            'FINAL_DELIVERY_VERIFICATION_BLOCKED', p_account_id,
            pg_catalog.jsonb_build_object(
              'orderId', v_order.id,
              'missionId', v_mission.id,
              'failedAttempts', v_failed_attempts
            )
          );
        end if;
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', case when v_failed_attempts >= v_attempt_limit
              then 'delivery_code_blocked' else 'delivery_code_invalid' end,
            'message', case when v_failed_attempts >= v_attempt_limit
              then 'Normal verification is blocked. Report the problem to Operations.'
              else 'The delivery code is incorrect.' end
          )
        );
        response_status := 409;
      elsif p_action = 'VERIFY_CUSTOMER_PIN' then
        if v_handoff.pin_verified_at is null then
          update dastak_v1.verification_handoffs
            set pin_verified_at=v_now,pin_verified_by=p_account_id,version=version+1 where id=v_handoff.id;
          insert into dastak_v1.audit_events(actor_id,action,resource_type,resource_id,metadata)
            values(p_account_id,'DELIVERY_PIN_VERIFIED','verification_handoff',v_handoff.id,
              pg_catalog.jsonb_build_object('orderId',v_order.id,'missionId',v_mission.id));
          perform dastak_v1_api.broadcast_delivery_tracking(v_order.id,v_mission.version);
        end if;
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      else
        update dastak_v1.verification_handoffs handoff
        set status = 'CONSUMED', consumed_at = v_now,
            consumed_by = p_account_id, version = handoff.version + 1
        where handoff.id = v_handoff.id
        returning * into v_handoff;
        response_body := dastak_v1_api.complete_final_delivery_locked(
          p_account_id, v_mission.id, v_handoff.id, 'CONSUMED', v_now
        );
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
$function$

;
-- Enriched projections remain behind the established ownership/branch checks.
alter function dastak_v1_api.order_json(uuid,uuid) rename to order_json_pre_tracking;
create function dastak_v1_api.order_json(p_order_id uuid,p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb; h dastak_v1.verification_handoffs%rowtype;
begin
  result := dastak_v1_api.order_json_pre_tracking(p_order_id,p_customer_id);
  if auth.role()='authenticated' or pg_catalog.current_setting('role',true)='authenticated' then
    perform dastak_v1_api.assert_authenticated_actor(p_customer_id);
  end if;
  if result is null then return null; end if;
  -- Explicit check even when an underlying projection's behavior changes.
  if not exists(select 1 from dastak_v1.orders where id=p_order_id and customer_id=p_customer_id) then
    raise exception using errcode='42501',message='order not found';
  end if;
  result := result || pg_catalog.jsonb_build_object('tracking',dastak_v1_api.delivery_tracking_json(p_order_id));
  select * into h from dastak_v1.verification_handoffs where order_id=p_order_id and handoff_type='RIDER_TO_CUSTOMER'
    order by created_at desc limit 1;
  if result->'delivery' is not null and result->'delivery' <> 'null'::jsonb then
    result := pg_catalog.jsonb_set(result,'{delivery}',(result->'delivery')
      || pg_catalog.jsonb_build_object('pinVerified',h.pin_verified_at is not null));
  end if;
  return result;
end;
$$;

alter function dastak_v1_api.merchant_fulfilment_json(uuid,uuid) rename to merchant_fulfilment_json_pre_tracking;
create function dastak_v1_api.merchant_fulfilment_json(p_actor_id uuid,p_fulfilment_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb; f dastak_v1.fulfilments%rowtype; b dastak_v1.merchant_branches%rowtype;
begin
  result := dastak_v1_api.merchant_fulfilment_json_pre_tracking(p_actor_id,p_fulfilment_id);
  if auth.role()='authenticated' or pg_catalog.current_setting('role',true)='authenticated' then
    perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  end if;
  if result is null then return null; end if;
  select * into f from dastak_v1.fulfilments where id=p_fulfilment_id;
  select * into b from dastak_v1.merchant_branches where id=f.branch_id;
  if not dastak_v1_api.actor_has_merchant_permission(p_actor_id,b.organization_id,'merchant.fulfilment.manage',b.id) then
    raise exception using errcode='42501',message='fulfilment not found';
  end if;
  return result || pg_catalog.jsonb_build_object('tracking',dastak_v1_api.delivery_tracking_json(f.order_id));
end;
$$;

create function dastak_v1_api.delivery_photo_ready(p_mission_id uuid,p_rider_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from dastak_v1.verification_handoffs h
    join dastak_v1.delivery_evidence e on e.verification_handoff_id=h.id
    where h.mission_id=p_mission_id and h.handoff_type='RIDER_TO_CUSTOMER'
      and h.pin_verified_by=p_rider_id and e.captured_by=p_rider_id and e.captured_at >= h.pin_verified_at
      and dastak_v1_api.delivery_evidence_covers_packages(e.id,p_mission_id,p_rider_id));
$$;

alter function dastak_v1_api.rider_mission_json(uuid,uuid) rename to rider_mission_json_pre_tracking;
create function dastak_v1_api.rider_mission_json(p_rider_id uuid,p_mission_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb; h dastak_v1.verification_handoffs%rowtype; m dastak_v1.delivery_missions%rowtype;
  photo_ready boolean; collection jsonb; collected boolean;
begin
  result := dastak_v1_api.rider_mission_json_pre_tracking(p_rider_id,p_mission_id);
  select * into m from dastak_v1.delivery_missions where id=p_mission_id and assigned_rider_id=p_rider_id;
  if not found then raise exception using errcode='42501',message='mission not found'; end if;
  select * into h from dastak_v1.verification_handoffs where mission_id=p_mission_id and handoff_type='RIDER_TO_CUSTOMER';
  photo_ready := dastak_v1_api.delivery_photo_ready(p_mission_id,p_rider_id);
  collection := dastak_v1_api.launch_collection_mission_json(p_mission_id,p_rider_id);
  collected := exists(select 1 from dastak_v1.launch_payment_collection_attempts
    where mission_id=p_mission_id and outcome='COLLECTED')
    or exists(select 1 from dastak_v1.payments where order_id=m.order_id and status='SUCCEEDED');
  result := pg_catalog.jsonb_set(result,'{pickupStops}',coalesce((
    select pg_catalog.jsonb_agg(stop || pg_catalog.jsonb_build_object(
      'arrival',dastak_v1_api.arrival_eligibility(p_mission_id,(stop->>'id')::uuid)) order by ord)
    from pg_catalog.jsonb_array_elements(result->'pickupStops') with ordinality as stops(stop,ord)
  ),'[]'::jsonb));
  return result || pg_catalog.jsonb_build_object(
    'customerArrival',dastak_v1_api.arrival_eligibility(p_mission_id,null),
    'canVerifyCustomerPIN',m.status='ARRIVED' and h.status='ACTIVE' and h.pin_verified_at is null,
    'canCompleteDelivery',m.status='ARRIVED' and h.status='ACTIVE' and h.pin_verified_at is not null
      and photo_ready and collected,
    'canVerifyDelivery',false,
    'canCaptureDeliveryEvidence',m.status='ARRIVED' and h.status='ACTIVE'
      and h.pin_verified_at is not null and not photo_ready,
    'finalVerification',case when h.id is null then null else
      (result->'finalVerification') || pg_catalog.jsonb_build_object(
        'pinVerified',h.pin_verified_at is not null,'evidencePresent',photo_ready) end,
    'launchCollection',collection);
end;
$$;

-- Do not unlock collection in any projection before the PIN and package photo.
CREATE OR REPLACE FUNCTION dastak_v1_api.launch_collection_mission_json(p_mission_id uuid, p_rider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_commitment dastak_v1.launch_payment_commitments%rowtype;
  v_latest dastak_v1.launch_payment_collection_attempts%rowtype;
  v_provider_paid boolean;
begin
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
    and mission.assigned_rider_id = p_rider_id;
  if v_mission.id is null then return null; end if;

  select commitment.* into v_commitment
  from dastak_v1.launch_payment_commitments commitment
  where commitment.order_id = v_mission.order_id;
  select exists (
    select 1 from dastak_v1.payments payment
    where payment.order_id = v_mission.order_id and payment.status = 'SUCCEEDED'
  ) into v_provider_paid;
  if v_commitment.id is not null then
    select attempt.* into v_latest
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.commitment_id = v_commitment.id
    order by attempt.attempted_at desc, attempt.id desc
    limit 1;
  end if;

  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'required', v_commitment.id is not null and v_latest.outcome is distinct from 'COLLECTED',
    'state', case
      when v_provider_paid then 'NOT_REQUIRED'
      when v_latest.outcome = 'COLLECTED' then 'PAYMENT_COLLECTED'
      when v_latest.outcome = 'FAILED' then 'COLLECTION_RETRY_NEEDED'
      when v_commitment.id is not null then 'PAYMENT_DUE_AT_DELIVERY'
      else 'NOT_REQUIRED'
    end,
    'amountPaise', v_commitment.amount_paise,
    'currencyCode', v_commitment.currency_code,
    'methods', case when v_commitment.id is null then '[]'::jsonb
      else '["CASH","UPI"]'::jsonb end,
    'canRecord', v_commitment.id is not null
      and v_latest.outcome is distinct from 'COLLECTED'
      and v_mission.status = 'ARRIVED'
      and dastak_v1_api.delivery_photo_ready(v_mission.id,p_rider_id),
    'lastOutcome', v_latest.outcome,
    'lastMethod', v_latest.method,
    'failureReason', case when v_latest.outcome = 'FAILED' then v_latest.failure_reason end,
    'attemptedAt', v_latest.attempted_at,
    'collectedAt', v_latest.collected_at
  ));
end;
$function$

;

-- Successful consumption is always after PIN/photo. The established completion
-- command independently enforces successful collection and balanced accounting.
create function dastak_v1.enforce_delivery_consumption() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.handoff_type='RIDER_TO_CUSTOMER' and new.status='CONSUMED' and old.status<>'CONSUMED' then
    if new.pin_verified_at is null or not dastak_v1_api.delivery_photo_ready(new.mission_id,new.pin_verified_by) then
      raise exception 'DELIVERY_HANDOFF_SEQUENCE_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;
create trigger delivery_consumption_sequence before update on dastak_v1.verification_handoffs
  for each row execute function dastak_v1.enforce_delivery_consumption();

revoke all on function dastak_v1_api.arrival_eligibility(uuid,uuid),
  dastak_v1_api.broadcast_delivery_tracking(uuid,bigint),dastak_v1_api.delivery_tracking_json(uuid),
  dastak_v1_api.delivery_photo_ready(uuid,uuid),dastak_v1.enforce_delivery_arrival(),
  dastak_v1.enforce_delivery_handoff_sequence(),dastak_v1.enforce_delivery_consumption(),
  dastak_v1.clear_completed_delivery_tracking()
  from public,anon,authenticated,service_role;
revoke all on function dastak_v1_api.publish_mission_location(uuid,uuid,double precision,double precision,double precision,timestamptz),
  public.dastak_v1_publish_mission_location(uuid,uuid,double precision,double precision,double precision,timestamptz)
  from public,anon,authenticated;
grant execute on function dastak_v1_api.publish_mission_location(uuid,uuid,double precision,double precision,double precision,timestamptz),
  public.dastak_v1_publish_mission_location(uuid,uuid,double precision,double precision,double precision,timestamptz)
  to service_role;
revoke all on function dastak_v1_api.order_json(uuid,uuid),dastak_v1_api.merchant_fulfilment_json(uuid,uuid),
  dastak_v1_api.rider_mission_json(uuid,uuid) from public,anon,authenticated;
-- The domain wrappers execute as owner; Edge snapshot handlers retain only their existing executor access.
grant execute on function dastak_v1_api.order_json(uuid,uuid),dastak_v1_api.merchant_fulfilment_json(uuid,uuid),
  dastak_v1_api.rider_mission_json(uuid,uuid) to service_role;
notify pgrst,'reload schema';
grant execute on function dastak_v1_api.order_json(uuid,uuid),
  dastak_v1_api.merchant_fulfilment_json(uuid,uuid) to authenticated;
revoke execute on function dastak_v1_api.order_json_pre_tracking(uuid,uuid),
  dastak_v1_api.merchant_fulfilment_json_pre_tracking(uuid,uuid) from authenticated;
