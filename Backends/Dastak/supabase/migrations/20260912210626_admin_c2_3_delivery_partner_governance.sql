-- Admin C2.3: governed Delivery Partner suspension/reactivation. Rider
-- governance remains independent from application approval, account personas,
-- availability and the Group A cross-domain active-work invariant.

alter table private.delivery_partner_profiles
  add column governance_status text not null default 'ACTIVE'
    check (governance_status in ('ACTIVE', 'SUSPENDED')),
  add column governance_version bigint not null default 1
    check (governance_version > 0),
  add column suspended_at timestamptz,
  add column suspended_by uuid references public.accounts(id),
  add column suspension_reason text
    check (suspension_reason is null or pg_catalog.char_length(suspension_reason) between 3 and 500),
  add constraint delivery_partner_governance_suspension_complete check (
    (governance_status = 'ACTIVE'
      and suspended_at is null
      and suspended_by is null
      and suspension_reason is null)
    or
    (governance_status = 'SUSPENDED'
      and suspended_at is not null
      and suspended_by is not null
      and suspension_reason is not null)
  );

create index delivery_partner_profiles_governance_page_idx
  on private.delivery_partner_profiles(updated_at desc, account_id desc);
create index delivery_partner_profiles_suspended_idx
  on private.delivery_partner_profiles(updated_at desc, account_id desc)
  where governance_status = 'SUSPENDED';

create or replace function dastak_v1_api.assert_delivery_partner_governance_admin(
  p_actor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.delivery_partners.manage'
  );
  if dastak_v1_api.admin_role_for_actor(p_actor_id) is null then
    raise exception using
      errcode = '42501',
      message = 'active Admin assignment required';
  end if;
end;
$$;

revoke all on function dastak_v1_api.assert_delivery_partner_governance_admin(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.delivery_partner_governance_is_active(
  p_rider_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select profile.governance_status = 'ACTIVE'
    from private.delivery_partner_profiles profile
    where profile.account_id = p_rider_id
  ), false)
$$;

revoke all on function private.delivery_partner_governance_is_active(uuid)
  from public, anon, authenticated, service_role;

-- Every active-work acquisition remains protected by Group A and additionally
-- observes rider governance while holding that exact same rider-scoped lock.
create or replace function private.enforce_delivery_partner_governance_assignment()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rider_id uuid;
  v_becomes_active boolean := false;
begin
  if tg_table_schema = 'dastak_v1' and tg_table_name = 'delivery_missions' then
    v_rider_id := new.assigned_rider_id;
    v_becomes_active := v_rider_id is not null and new.status in (
      'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
      'DELIVERY_RECOVERY'
    );
  elsif tg_table_schema = 'dastak_v1' and tg_table_name = 'return_missions' then
    v_rider_id := new.assigned_rider_id;
    v_becomes_active := v_rider_id is not null
      and new.status not in ('COMPLETED', 'CANCELLED');
  elsif tg_table_schema = 'private' and tg_table_name = 'delivery_assignment_attempts' then
    v_rider_id := new.partner_account_id;
    v_becomes_active := new.status = 'accepted';
  elsif tg_table_schema = 'private' and tg_table_name = 'parcel_assignment_attempts' then
    v_rider_id := new.partner_account_id;
    v_becomes_active := new.status = 'acknowledged';
  end if;

  if v_becomes_active then
    perform private.lock_delivery_partner_active_work(v_rider_id);
    if exists (
      select 1
      from private.delivery_partner_profiles profile
      where profile.account_id = v_rider_id
        and profile.governance_status = 'SUSPENDED'
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'RIDER_GOVERNANCE_SUSPENDED',
        detail = 'The Delivery Partner is governance-suspended and cannot acquire work.';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_delivery_partner_governance_assignment()
  from public, anon, authenticated, service_role;

drop trigger if exists aaa_delivery_missions_rider_governance
  on dastak_v1.delivery_missions;
create trigger aaa_delivery_missions_rider_governance
before insert or update of assigned_rider_id, status
on dastak_v1.delivery_missions
for each row execute function private.enforce_delivery_partner_governance_assignment();

drop trigger if exists aaa_return_missions_rider_governance
  on dastak_v1.return_missions;
create trigger aaa_return_missions_rider_governance
before insert or update of assigned_rider_id, status
on dastak_v1.return_missions
for each row execute function private.enforce_delivery_partner_governance_assignment();

drop trigger if exists aaa_legacy_assignments_rider_governance
  on private.delivery_assignment_attempts;
create trigger aaa_legacy_assignments_rider_governance
before insert or update of partner_account_id, status
on private.delivery_assignment_attempts
for each row execute function private.enforce_delivery_partner_governance_assignment();

drop trigger if exists aaa_parcel_assignments_rider_governance
  on private.parcel_assignment_attempts;
create trigger aaa_parcel_assignments_rider_governance
before insert or update of partner_account_id, status
on private.parcel_assignment_attempts
for each row execute function private.enforce_delivery_partner_governance_assignment();

-- Availability is serialized with suspension. This is a database boundary,
-- not a UI-only gate, and therefore also protects service-role callers.
create or replace function private.enforce_delivery_partner_governance_availability()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if new.status = 'online' then
    -- UPDATE has already locked this availability row before a row trigger
    -- runs. A blocking advisory-lock acquisition here could therefore
    -- deadlock with suspension, which takes the rider lock before forcing
    -- this row offline. Fail closed and let the ordinary reconciliation path
    -- retry after the governance command commits.
    if not pg_catalog.pg_try_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'dastak:delivery-partner-active-work:' || new.account_id::text,
        0
      )
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'RIDER_GOVERNANCE_SUSPENDED',
        detail = 'Delivery Partner governance is being updated; reconcile before going online.';
    end if;
    if not private.delivery_partner_governance_is_active(new.account_id) then
      raise exception using
        errcode = 'P0001',
        message = 'RIDER_GOVERNANCE_SUSPENDED',
        detail = 'A governance-suspended Delivery Partner cannot become available.';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_delivery_partner_governance_availability()
  from public, anon, authenticated, service_role;

drop trigger if exists aaa_delivery_partner_availability_governance
  on private.delivery_partner_availability;
create trigger aaa_delivery_partner_availability_governance
before insert or update of status, available_until
on private.delivery_partner_availability
for each row execute function private.enforce_delivery_partner_governance_availability();

create or replace function dastak_v1_api.admin_delivery_partner_governance_page(
  p_actor_id uuid,
  p_query text default null,
  p_rider_id uuid default null,
  p_status text default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_rider_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := nullif(pg_catalog.btrim(coalesce(p_query, '')), '');
  v_status text := nullif(pg_catalog.upper(pg_catalog.btrim(coalesce(p_status, ''))), '');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_rows jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_delivery_partner_governance_admin(p_actor_id);
  if v_query is not null and pg_catalog.char_length(v_query) > 100 then
    raise exception using errcode = '22023', message = 'Delivery Partner governance search is too long';
  end if;
  if v_status is not null and v_status not in ('ACTIVE', 'SUSPENDED') then
    raise exception using errcode = '22023', message = 'invalid Delivery Partner governance status';
  end if;
  if (p_after_updated_at is null) <> (p_after_rider_id is null) then
    raise exception using errcode = '22023', message = 'complete Delivery Partner governance cursor required';
  end if;

  with governed as materialized (
    select
      profile.account_id as rider_id,
      coalesce(nullif(pg_catalog.btrim(account.display_name), ''), 'Delivery Partner') as display_name,
      case
        when account.phone_number is null then null
        when pg_catalog.char_length(account.phone_number) <= 4 then account.phone_number
        else '•••• ' || pg_catalog.right(account.phone_number, 4)
      end as masked_phone_number,
      account.account_state::text as account_state,
      application.id as application_id,
      application.status as application_status,
      application.submitted_at,
      application.reviewed_at,
      application.verification_version,
      application.identity_evidence_object_path is not null as has_identity_evidence,
      application.vehicle_evidence_object_path is not null as has_vehicle_evidence,
      profile.delivery_method,
      profile.governance_status,
      profile.governance_version,
      profile.suspended_at,
      profile.suspension_reason,
      case
        when profile.governance_status = 'ACTIVE'
          and availability.status = 'online'
          and availability.available_until > pg_catalog.statement_timestamp()
        then 'ONLINE'
        else 'OFFLINE'
      end as availability_status,
      availability.state_version as availability_version,
      availability.available_until,
      availability.last_seen_at,
      availability.updated_at as availability_updated_at,
      zone.id as service_zone_id,
      zone.name as service_zone_name,
      availability.tracking_received_at,
      work.work_domain,
      work.work_id,
      work_state.updated_at as work_updated_at,
      greatest(
        profile.updated_at,
        application.updated_at,
        coalesce(availability.updated_at, '-infinity'::timestamptz),
        coalesce(work_state.updated_at, '-infinity'::timestamptz)
      ) as row_updated_at
    from private.delivery_partner_profiles profile
    join public.accounts account on account.id = profile.account_id
    join private.delivery_partner_applications application
      on application.id = profile.approved_application_id
      and application.account_id = profile.account_id
    left join private.delivery_partner_availability availability
      on availability.account_id = profile.account_id
    left join public.service_zones zone on zone.id = availability.service_zone_id
    left join lateral (
      select active.work_domain, active.work_id
      from private.delivery_partner_active_work(profile.account_id) active
      limit 1
    ) work on true
    left join lateral (
      select candidate.updated_at
      from (
        select mission.updated_at
        from dastak_v1.delivery_missions mission
        where work.work_domain = 'DASTAK_V1' and mission.id = work.work_id
        union all
        select mission.updated_at
        from dastak_v1.return_missions mission
        where work.work_domain = 'RETURN' and mission.id = work.work_id
        union all
        select assignment.updated_at
        from private.delivery_assignment_attempts assignment
        where work.work_domain = 'LEGACY_COURIER' and assignment.id = work.work_id
        union all
        select assignment.updated_at
        from private.parcel_assignment_attempts assignment
        where work.work_domain = 'PARCEL' and assignment.id = work.work_id
      ) candidate
      limit 1
    ) work_state on true
    where (p_rider_id is null or profile.account_id = p_rider_id)
      and (v_status is null or profile.governance_status = v_status)
      and (
        v_query is null
        or profile.account_id::text = pg_catalog.lower(v_query)
        or application.id::text = pg_catalog.lower(v_query)
        or account.display_name ilike '%' || v_query || '%'
        or account.phone_number = v_query
      )
      and (
        p_after_updated_at is null
        or (greatest(
              profile.updated_at,
              application.updated_at,
              coalesce(availability.updated_at, '-infinity'::timestamptz),
              coalesce(work_state.updated_at, '-infinity'::timestamptz)
            ), profile.account_id) < (p_after_updated_at, p_after_rider_id)
      )
    order by row_updated_at desc, rider_id desc
    limit v_limit + 1
  ), selected as (
    select * from governed
    order by row_updated_at desc, rider_id desc
    limit v_limit
  )
  select
    coalesce((select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'rider', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
          'accountId', row.rider_id,
          'displayName', row.display_name,
          'maskedPhoneNumber', row.masked_phone_number,
          'accountState', row.account_state
        )),
        'approval', pg_catalog.jsonb_build_object(
          'applicationId', row.application_id,
          'status', row.application_status,
          'submittedAt', row.submitted_at,
          'reviewedAt', row.reviewed_at,
          'verificationVersion', row.verification_version,
          'hasIdentityEvidence', row.has_identity_evidence,
          'hasVehicleEvidence', row.has_vehicle_evidence
        ),
        'transportMethod', row.delivery_method,
        'governance', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
          'status', row.governance_status,
          'version', row.governance_version,
          'suspendedAt', row.suspended_at,
          'reason', row.suspension_reason
        )),
        'availability', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
          'status', row.availability_status,
          'version', coalesce(row.availability_version, 0),
          'availableUntil', row.available_until,
          'lastSeenAt', row.last_seen_at,
          'serviceZone', case when row.service_zone_id is null then null else
            pg_catalog.jsonb_build_object('id', row.service_zone_id, 'name', row.service_zone_name)
          end,
          'trackingReceivedAt', row.tracking_received_at
        )),
        'activeWork', case when row.work_id is null then null else
          pg_catalog.jsonb_build_object('domain', row.work_domain, 'id', row.work_id)
        end,
        'updatedAt', row.row_updated_at
      ) order by row.row_updated_at desc, row.rider_id desc
    ) from selected row), '[]'::jsonb),
    (select pg_catalog.count(*) > v_limit from governed),
    case when (select pg_catalog.count(*) > v_limit from governed) then (
      select pg_catalog.jsonb_build_object(
        'updatedAt', row.row_updated_at,
        'riderId', row.rider_id
      )
      from selected row
      order by row.row_updated_at, row.rider_id
      limit 1
    ) else null end
  into v_rows, v_has_more, v_next_cursor;

  return pg_catalog.jsonb_build_object(
    'deliveryPartners', v_rows,
    'hasMore', v_has_more,
    'nextCursor', v_next_cursor
  );
end;
$$;

create or replace function dastak_v1_api.set_delivery_partner_governance_status(
  p_actor_id uuid,
  p_rider_id uuid,
  p_status text,
  p_expected_governance_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'setDeliveryPartnerGovernanceStatus';
  v_target text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_status, '')));
  v_profile private.delivery_partner_profiles%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
  v_from_status text;
  v_availability_version bigint;
begin
  perform dastak_v1_api.assert_delivery_partner_governance_admin(p_actor_id);
  if p_rider_id is null
    or v_target not in ('ACTIVE', 'SUSPENDED')
    or p_expected_governance_version is null or p_expected_governance_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid Delivery Partner governance command required';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'riderId', p_rider_id,
    'status', v_target,
    'expectedGovernanceVersion', p_expected_governance_version,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key), 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  perform private.lock_delivery_partner_active_work(p_rider_id);
  select profile.* into v_profile
  from private.delivery_partner_profiles profile
  where profile.account_id = p_rider_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Delivery Partner profile not found';
  end if;
  if v_profile.governance_version <> p_expected_governance_version then
    raise exception using errcode = '40001', message = 'stale Delivery Partner governance version';
  end if;
  if (v_target = 'SUSPENDED' and v_profile.governance_status <> 'ACTIVE')
    or (v_target = 'ACTIVE' and v_profile.governance_status <> 'SUSPENDED') then
    raise exception using errcode = '55000', message = 'Delivery Partner governance transition is not available';
  end if;

  if v_target = 'SUSPENDED' then
    if exists (
      select 1
      from private.delivery_partner_active_work(p_rider_id)
    ) then
      raise exception using
        errcode = '55000',
        message = 'RIDER_ACTIVE_WORK_REQUIRES_RELEASE',
        detail = 'Use the existing recovery or release workflow before suspending this rider.';
    end if;
  end if;

  v_from_status := v_profile.governance_status;
  update private.delivery_partner_profiles profile
  set governance_status = v_target,
      governance_version = profile.governance_version + 1,
      suspended_at = case when v_target = 'SUSPENDED' then pg_catalog.now() else null end,
      suspended_by = case when v_target = 'SUSPENDED' then p_actor_id else null end,
      suspension_reason = case when v_target = 'SUSPENDED' then pg_catalog.btrim(p_reason) else null end,
      updated_at = pg_catalog.now()
  where profile.account_id = p_rider_id
  returning profile.* into v_profile;

  if v_target = 'SUSPENDED' then
    update private.delivery_partner_availability availability
    set status = 'offline',
        location = null,
        service_zone_id = null,
        available_until = null,
        tracking_mission_id = null,
        tracking_return_mission_id = null,
        tracking_location = null,
        tracking_accuracy_meters = null,
        tracking_recorded_at = null,
        tracking_received_at = null,
        tracking_sequence = 0,
        state_version = availability.state_version + 1,
        updated_at = pg_catalog.now()
    where availability.account_id = p_rider_id
    returning availability.state_version into v_availability_version;
  else
    select availability.state_version into v_availability_version
    from private.delivery_partner_availability availability
    where availability.account_id = p_rider_id;
  end if;

  insert into dastak_v1.audit_events(
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    case when v_target = 'SUSPENDED'
      then 'DELIVERY_PARTNER_SUSPENDED'
      else 'DELIVERY_PARTNER_REACTIVATED' end,
    'delivery_partner', p_rider_id,
    pg_catalog.jsonb_build_object(
      'accountId', p_rider_id,
      'transportMethod', v_profile.delivery_method,
      'reason', pg_catalog.btrim(p_reason),
      'scope', v_profile.delivery_method,
      'outcome', 'governance version ' || p_expected_governance_version::text
        || ' -> ' || v_profile.governance_version::text,
      'fromStatus', v_from_status,
      'toStatus', v_target,
      'fromVersion', p_expected_governance_version,
      'version', v_profile.governance_version,
      'availabilityVersion', v_availability_version
    )
  );

  v_response := pg_catalog.jsonb_build_object(
    'riderId', p_rider_id,
    'status', v_profile.governance_status,
    'governanceVersion', v_profile.governance_version,
    'availabilityStatus', 'OFFLINE',
    'availabilityVersion', coalesce(v_availability_version, 0),
    'updatedAt', v_profile.updated_at
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_rider_id
  );
  return v_response;
end;
$$;

create or replace function public.dastak_v1_admin_delivery_partner_governance_page(
  p_query text default null,
  p_rider_id uuid default null,
  p_status text default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_rider_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_delivery_partner_governance_page(
    auth.uid(), p_query, p_rider_id, p_status, p_limit,
    p_after_updated_at, p_after_rider_id
  )
$$;

create or replace function public.dastak_v1_admin_set_delivery_partner_status(
  p_rider_id uuid,
  p_status text,
  p_expected_governance_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.set_delivery_partner_governance_status(
    auth.uid(), p_rider_id, p_status, p_expected_governance_version,
    p_reason, p_idempotency_key
  )
$$;

revoke all on function dastak_v1_api.admin_delivery_partner_governance_page(
  uuid,text,uuid,text,integer,timestamptz,uuid
) from public, anon;
revoke all on function dastak_v1_api.set_delivery_partner_governance_status(
  uuid,uuid,text,bigint,text,text
) from public, anon;
grant execute on function dastak_v1_api.admin_delivery_partner_governance_page(
  uuid,text,uuid,text,integer,timestamptz,uuid
) to authenticated, service_role;
grant execute on function dastak_v1_api.set_delivery_partner_governance_status(
  uuid,uuid,text,bigint,text,text
) to authenticated, service_role;

revoke all on function public.dastak_v1_admin_delivery_partner_governance_page(
  text,uuid,text,integer,timestamptz,uuid
) from public, anon;
revoke all on function public.dastak_v1_admin_set_delivery_partner_status(
  uuid,text,bigint,text,text
) from public, anon;
grant execute on function public.dastak_v1_admin_delivery_partner_governance_page(
  text,uuid,text,integer,timestamptz,uuid
) to authenticated, service_role;
grant execute on function public.dastak_v1_admin_set_delivery_partner_status(
  uuid,text,bigint,text,text
) to authenticated, service_role;

comment on function public.dastak_v1_admin_delivery_partner_governance_page(
  text,uuid,text,integer,timestamptz,uuid
) is 'Caller-bound, active-Admin Delivery Partner governance projection with bounded keyset pagination.';
comment on function public.dastak_v1_admin_set_delivery_partner_status(
  uuid,text,bigint,text,text
) is 'Governed, versioned and idempotent Delivery Partner suspension/reactivation using the global rider work lock.';

-- Realtime carries invalidation only; no rider identity or evidence data is
-- published in the private Admin channel payload.
create or replace function private.send_admin_change(
  p_workspaces text[],
  p_entity_id uuid default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspaces text[];
begin
  select pg_catalog.array_agg(candidate.workspace order by candidate.workspace)
  into v_workspaces
  from (
    select distinct workspace
    from pg_catalog.unnest(p_workspaces) workspace
    where workspace = any (array[
      'operations', 'liveOrders', 'adminAccess', 'commandCenter',
      'merchantApprovals', 'deliveryApprovals', 'systemHealth',
      'operationalSafety', 'royaltyPayouts', 'network', 'catalogue',
      'auditHistory', 'merchantGovernance', 'deliveryPartnerGovernance'
    ]::text[])
  ) candidate;
  if coalesce(pg_catalog.cardinality(v_workspaces), 0) = 0 then return; end if;
  perform realtime.send(
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'workspaces', v_workspaces, 'entityId', p_entity_id
    )),
    'admin_changed', 'admin-control', true
  );
end;
$$;

revoke all on function private.send_admin_change(text[], uuid)
  from public, anon, authenticated, service_role;

drop trigger if exists zzz_admin_delivery_partner_profiles_governance_realtime
  on private.delivery_partner_profiles;
create trigger zzz_admin_delivery_partner_profiles_governance_realtime
after insert or update or delete on private.delivery_partner_profiles
for each row execute function private.broadcast_admin_change(
  'deliveryPartnerGovernance', 'network', 'commandCenter'
);

drop trigger if exists zzz_admin_delivery_partner_availability_governance_realtime
  on private.delivery_partner_availability;
create trigger zzz_admin_delivery_partner_availability_governance_realtime
after insert or update or delete on private.delivery_partner_availability
for each row execute function private.broadcast_admin_change(
  'deliveryPartnerGovernance', 'operationalSafety', 'commandCenter'
);

drop trigger if exists zzz_admin_delivery_missions_rider_governance_realtime
  on dastak_v1.delivery_missions;
create trigger zzz_admin_delivery_missions_rider_governance_realtime
after insert or update or delete on dastak_v1.delivery_missions
for each row execute function private.broadcast_admin_change(
  'deliveryPartnerGovernance'
);

drop trigger if exists zzz_admin_return_missions_rider_governance_realtime
  on dastak_v1.return_missions;
create trigger zzz_admin_return_missions_rider_governance_realtime
after insert or update or delete on dastak_v1.return_missions
for each row execute function private.broadcast_admin_change(
  'deliveryPartnerGovernance'
);

drop trigger if exists zzz_admin_legacy_assignments_rider_governance_realtime
  on private.delivery_assignment_attempts;
create trigger zzz_admin_legacy_assignments_rider_governance_realtime
after insert or update or delete on private.delivery_assignment_attempts
for each row execute function private.broadcast_admin_change(
  'deliveryPartnerGovernance'
);

drop trigger if exists zzz_admin_parcel_assignments_rider_governance_realtime
  on private.parcel_assignment_attempts;
create trigger zzz_admin_parcel_assignments_rider_governance_realtime
after insert or update or delete on private.parcel_assignment_attempts
for each row execute function private.broadcast_admin_change(
  'deliveryPartnerGovernance'
);
