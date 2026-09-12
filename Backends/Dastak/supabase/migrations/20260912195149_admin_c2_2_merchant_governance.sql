-- Admin C2.2: governed Merchant organization and branch management.
-- Governance eligibility remains separate from the merchant-controlled
-- open/closed state and from the existing operational-pause control.

create index if not exists merchant_organizations_governance_page_idx
  on dastak_v1.merchant_organizations (updated_at desc, id desc);
create index if not exists merchant_branches_governance_page_idx
  on dastak_v1.merchant_branches (updated_at desc, id desc);

create or replace function dastak_v1_api.assert_merchant_governance_admin(
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
    p_actor_id, 'platform.merchants.manage'
  );
  if dastak_v1_api.admin_role_for_actor(p_actor_id) is null then
    raise exception using
      errcode = '42501',
      message = 'active Admin assignment required';
  end if;
end;
$$;

revoke all on function dastak_v1_api.assert_merchant_governance_admin(uuid)
  from public, anon, authenticated, service_role;

create or replace function dastak_v1_api.branch_active_pickup_return_count(
  p_branch_id uuid
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.count(*)::integer
  from (
    select 'delivery:' || stop.mission_id::text as work_key
    from dastak_v1.delivery_stops stop
    join dastak_v1.delivery_missions mission on mission.id = stop.mission_id
    where stop.branch_id = p_branch_id
      and stop.status <> 'COMPLETED'
      and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
    union
    select 'return:' || stop.return_id::text
    from dastak_v1.return_stops stop
    join dastak_v1.return_missions mission
      on mission.id = stop.return_mission_id
    where stop.branch_id = p_branch_id
      and stop.status <> 'COMPLETED'
      and mission.status not in ('COMPLETED', 'CANCELLED')
    union
    select 'return:' || package.return_id::text
    from dastak_v1.return_packages package
    where package.destination_branch_id = p_branch_id
      and package.status <> 'MERCHANT_RETURN_CUSTODY'
  ) work;
$$;

revoke all on function dastak_v1_api.branch_active_pickup_return_count(uuid)
  from public, anon, authenticated, service_role;

create or replace function dastak_v1_api.organization_active_pickup_return_count(
  p_organization_id uuid
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.count(*)::integer
  from (
    select 'delivery:' || stop.mission_id::text as work_key
    from dastak_v1.delivery_stops stop
    join dastak_v1.delivery_missions mission on mission.id = stop.mission_id
    join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
    where branch.organization_id = p_organization_id
      and stop.status <> 'COMPLETED'
      and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
    union
    select 'return:' || stop.return_id::text
    from dastak_v1.return_stops stop
    join dastak_v1.return_missions mission
      on mission.id = stop.return_mission_id
    join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
    where branch.organization_id = p_organization_id
      and stop.status <> 'COMPLETED'
      and mission.status not in ('COMPLETED', 'CANCELLED')
    union
    select 'return:' || package.return_id::text
    from dastak_v1.return_packages package
    join dastak_v1.merchant_branches branch
      on branch.id = package.destination_branch_id
    where branch.organization_id = p_organization_id
      and package.status <> 'MERCHANT_RETURN_CUSTODY'
  ) work;
$$;

revoke all on function dastak_v1_api.organization_active_pickup_return_count(uuid)
  from public, anon, authenticated, service_role;

-- Serialize new committed Merchant work against governance status changes.
-- Existing work remains free to advance after suspension; only acquisition of
-- a new non-terminal fulfilment is gated here.
create or replace function dastak_v1_api.guard_new_fulfilment_governance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_status dastak_v1.merchant_status;
  v_branch_status dastak_v1.branch_status;
begin
  if new.status in ('COMPLETED', 'RELEASED')
    or (tg_op = 'UPDATE'
      and old.status not in ('COMPLETED', 'RELEASED')
      and new.organization_id = old.organization_id
      and new.branch_id = old.branch_id) then
    return new;
  end if;

  select organization.status into v_organization_status
  from dastak_v1.merchant_organizations organization
  where organization.id = new.organization_id
  for share;
  select branch.status into v_branch_status
  from dastak_v1.merchant_branches branch
  where branch.id = new.branch_id
    and branch.organization_id = new.organization_id
  for share;
  if v_organization_status <> 'ACTIVE' or v_branch_status <> 'ACTIVE' then
    raise exception using
      errcode = '55000',
      message = 'merchant governance status does not permit new fulfilments';
  end if;
  return new;
end;
$$;

revoke all on function dastak_v1_api.guard_new_fulfilment_governance()
  from public, anon, authenticated, service_role;

drop trigger if exists aaa_guard_new_fulfilment_governance
  on dastak_v1.fulfilments;
create trigger aaa_guard_new_fulfilment_governance
before insert or update of organization_id, branch_id, status
on dastak_v1.fulfilments
for each row execute function dastak_v1_api.guard_new_fulfilment_governance();

-- Lock destination branches while new pickup/return work is attached. A
-- correction that owns the branch row therefore completes first (new work uses
-- the new destination), or waits and then observes the active work and aborts.
create or replace function dastak_v1_api.serialize_new_branch_route_work()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_id uuid;
begin
  if tg_table_name = 'return_packages' then
    v_branch_id := new.destination_branch_id;
  else
    v_branch_id := new.branch_id;
  end if;
  perform 1
  from dastak_v1.merchant_branches branch
  where branch.id = v_branch_id
  for share;
  return new;
end;
$$;

revoke all on function dastak_v1_api.serialize_new_branch_route_work()
  from public, anon, authenticated, service_role;

drop trigger if exists aaa_serialize_delivery_stop_destination
  on dastak_v1.delivery_stops;
create trigger aaa_serialize_delivery_stop_destination
before insert or update of branch_id on dastak_v1.delivery_stops
for each row execute function dastak_v1_api.serialize_new_branch_route_work();

drop trigger if exists aaa_serialize_return_stop_destination
  on dastak_v1.return_stops;
create trigger aaa_serialize_return_stop_destination
before insert or update of branch_id on dastak_v1.return_stops
for each row execute function dastak_v1_api.serialize_new_branch_route_work();

drop trigger if exists aaa_serialize_return_package_destination
  on dastak_v1.return_packages;
create trigger aaa_serialize_return_package_destination
before insert or update of destination_branch_id on dastak_v1.return_packages
for each row execute function dastak_v1_api.serialize_new_branch_route_work();

create or replace function dastak_v1_api.admin_merchant_governance_page(
  p_actor_id uuid,
  p_query text default null,
  p_organization_id uuid default null,
  p_branch_id uuid default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_row_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := nullif(pg_catalog.btrim(coalesce(p_query, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_rows jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_merchant_governance_admin(p_actor_id);
  if v_query is not null and pg_catalog.char_length(v_query) > 100 then
    raise exception using errcode = '22023', message = 'merchant governance search is too long';
  end if;
  if (p_after_updated_at is null) <> (p_after_row_id is null) then
    raise exception using errcode = '22023', message = 'complete merchant governance cursor required';
  end if;

  with governed as materialized (
    select
      organization.id as organization_id,
      organization.display_name as organization_display_name,
      organization.legal_name as organization_legal_name,
      organization.merchant_type,
      organization.status as organization_status,
      organization.version as organization_version,
      branch.id as branch_id,
      branch.display_name as branch_display_name,
      branch.status as branch_status,
      branch.version as branch_version,
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'line1', coalesce(branch.address_snapshot ->> 'line1', branch.address_snapshot ->> 'addressLine1'),
        'line2', coalesce(branch.address_snapshot ->> 'line2', branch.address_snapshot ->> 'addressLine2'),
        'city', branch.address_snapshot ->> 'city',
        'state', branch.address_snapshot ->> 'state',
        'postalCode', branch.address_snapshot ->> 'postalCode',
        'countryCode', branch.address_snapshot ->> 'countryCode'
      )) as normalized_address,
      case when branch.location is null then null
        else extensions.st_y(branch.location) end as latitude,
      case when branch.location is null then null
        else extensions.st_x(branch.location) end as longitude,
      branch.service_zone_id,
      zone.name as service_zone_name,
      branch.capacity_limit,
      state.is_open,
      state.accepting_orders,
      state.version as operational_state_version,
      coalesce(fulfilment_count.active_count, 0)::integer
        as branch_active_non_terminal_fulfilment_count,
      coalesce(organization_fulfilment_count.active_count, 0)::integer
        as organization_active_non_terminal_fulfilment_count,
      dastak_v1_api.branch_active_pickup_return_count(branch.id)
        as branch_active_pickup_return_work_count,
      dastak_v1_api.organization_active_pickup_return_count(organization.id)
        as organization_active_pickup_return_work_count,
      pause.id as pause_id,
      coalesce(pause.active, false) as pause_active,
      pause.reason as pause_reason,
      pause.version as pause_version,
      pause.updated_at as pause_updated_at,
      greatest(organization.updated_at, branch.updated_at,
        coalesce(state.updated_at, '-infinity'::timestamptz),
        coalesce(pause.updated_at, '-infinity'::timestamptz)) as row_updated_at,
      branch.id as row_id
    from dastak_v1.merchant_organizations organization
    join dastak_v1.merchant_branches branch
      on branch.organization_id = organization.id
    left join public.service_zones zone on zone.id = branch.service_zone_id
    left join dastak_v1.branch_operational_states state
      on state.branch_id = branch.id
    left join dastak_v1.operational_pause_controls pause
      on pause.scope = 'MERCHANT_BRANCH'
      and pause.branch_id = branch.id
    left join lateral (
      select pg_catalog.count(*) as active_count
      from dastak_v1.fulfilments fulfilment
      where fulfilment.branch_id = branch.id
        and fulfilment.status not in ('COMPLETED', 'RELEASED')
    ) fulfilment_count on true
    left join lateral (
      select pg_catalog.count(*) as active_count
      from dastak_v1.fulfilments fulfilment
      where fulfilment.organization_id = organization.id
        and fulfilment.status not in ('COMPLETED', 'RELEASED')
    ) organization_fulfilment_count on true
    where (p_organization_id is null or organization.id = p_organization_id)
      and (p_branch_id is null or branch.id = p_branch_id)
      and (
        v_query is null
        or organization.id::text = pg_catalog.lower(v_query)
        or branch.id::text = pg_catalog.lower(v_query)
        or organization.display_name ilike '%' || v_query || '%'
        or organization.legal_name ilike '%' || v_query || '%'
        or branch.display_name ilike '%' || v_query || '%'
      )
      and (
        p_after_updated_at is null
        or (greatest(organization.updated_at, branch.updated_at,
              coalesce(state.updated_at, '-infinity'::timestamptz),
              coalesce(pause.updated_at, '-infinity'::timestamptz)), branch.id)
          < (p_after_updated_at, p_after_row_id)
      )
    order by row_updated_at desc, row_id desc
    limit v_limit + 1
  ), selected as (
    select * from governed
    order by row_updated_at desc, row_id desc
    limit v_limit
  )
  select
    coalesce((select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'organization', pg_catalog.jsonb_build_object(
          'id', row.organization_id,
          'displayName', row.organization_display_name,
          'legalName', row.organization_legal_name,
          'merchantType', row.merchant_type,
          'status', row.organization_status,
          'version', row.organization_version,
          'activeNonTerminalFulfilmentCount', row.organization_active_non_terminal_fulfilment_count,
          'activePickupReturnWorkCount', row.organization_active_pickup_return_work_count
        ),
        'branch', pg_catalog.jsonb_build_object(
          'id', row.branch_id,
          'displayName', row.branch_display_name,
          'status', row.branch_status,
          'version', row.branch_version,
          'normalizedAddress', row.normalized_address,
          'latitude', row.latitude,
          'longitude', row.longitude,
          'serviceZone', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'id', row.service_zone_id,
            'name', row.service_zone_name
          )),
          'capacityLimit', row.capacity_limit,
          'operationalState', pg_catalog.jsonb_build_object(
            'isOpen', coalesce(row.is_open, false),
            'acceptingOrders', coalesce(row.accepting_orders, false),
            'version', row.operational_state_version
          ),
          'activeNonTerminalFulfilmentCount', row.branch_active_non_terminal_fulfilment_count,
          'activePickupReturnWorkCount', row.branch_active_pickup_return_work_count,
          'operationalPause', case when row.pause_id is null then null else
            pg_catalog.jsonb_build_object(
              'id', row.pause_id,
              'active', row.pause_active,
              'reason', row.pause_reason,
              'version', row.pause_version,
              'updatedAt', row.pause_updated_at
            ) end
        ),
        'updatedAt', row.row_updated_at
      ) order by row.row_updated_at desc, row.row_id desc
    ) from selected row), '[]'::jsonb),
    (select pg_catalog.count(*) > v_limit from governed),
    case when (select pg_catalog.count(*) > v_limit from governed) then (
      select pg_catalog.jsonb_build_object(
        'updatedAt', row.row_updated_at,
        'rowId', row.row_id
      )
      from selected row
      order by row.row_updated_at, row.row_id
      limit 1
    ) else null end
  into v_rows, v_has_more, v_next_cursor;

  return pg_catalog.jsonb_build_object(
    'merchants', v_rows,
    'hasMore', v_has_more,
    'nextCursor', v_next_cursor,
    'serviceZones', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', zone.id, 'name', zone.name
      ) order by zone.name, zone.id)
      from public.service_zones zone
      where zone.active
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function dastak_v1_api.set_merchant_organization_governance_status(
  p_actor_id uuid,
  p_organization_id uuid,
  p_status text,
  p_expected_version bigint,
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
  v_command constant text := 'setMerchantOrganizationGovernanceStatus';
  v_target dastak_v1.merchant_status;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
  v_from_status text;
begin
  perform dastak_v1_api.assert_merchant_governance_admin(p_actor_id);
  begin
    v_target := pg_catalog.upper(pg_catalog.btrim(p_status))::dastak_v1.merchant_status;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid merchant organization governance status';
  end;
  if v_target not in ('ACTIVE', 'SUSPENDED')
    or p_organization_id is null
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid merchant organization governance command required';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'organizationId', p_organization_id, 'status', v_target,
    'expectedVersion', p_expected_version,
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

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'merchant-governance-organization:' || p_organization_id::text, 0
  ));
  select organization.* into v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'merchant organization not found';
  end if;
  if v_organization.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale merchant organization version';
  end if;
  if (v_target = 'SUSPENDED' and v_organization.status <> 'ACTIVE')
    or (v_target = 'ACTIVE' and v_organization.status <> 'SUSPENDED') then
    raise exception using errcode = '55000', message = 'merchant organization governance transition is not available';
  end if;

  if v_target = 'SUSPENDED' and (
    exists (
      select 1 from dastak_v1.fulfilments fulfilment
      where fulfilment.organization_id = p_organization_id
        and fulfilment.status not in ('COMPLETED', 'RELEASED')
    ) or dastak_v1_api.organization_active_pickup_return_count(p_organization_id) > 0
  ) then
    raise exception using
      errcode = '55000',
      message = 'ACTIVE_FULFILMENTS_REQUIRE_RESOLUTION';
  end if;

  v_from_status := v_organization.status::text;
  update dastak_v1.merchant_organizations organization
  set status = v_target,
      updated_at = pg_catalog.now(),
      version = organization.version + 1
  where organization.id = p_organization_id
  returning organization.* into v_organization;

  insert into dastak_v1.audit_events(
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    case when v_target = 'SUSPENDED'
      then 'MERCHANT_ORGANIZATION_SUSPENDED'
      else 'MERCHANT_ORGANIZATION_REACTIVATED' end,
    'merchant_organization', p_organization_id,
    pg_catalog.jsonb_build_object(
      'reason', pg_catalog.btrim(p_reason),
      'fromStatus', v_from_status,
      'toStatus', v_target,
      'fromVersion', p_expected_version,
      'version', v_organization.version
    )
  );

  v_response := pg_catalog.jsonb_build_object(
    'organizationId', p_organization_id,
    'status', v_organization.status,
    'version', v_organization.version,
    'updatedAt', v_organization.updated_at
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_organization_id
  );
  return v_response;
end;
$$;

create or replace function dastak_v1_api.set_merchant_branch_governance_status(
  p_actor_id uuid,
  p_branch_id uuid,
  p_status text,
  p_expected_version bigint,
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
  v_command constant text := 'setMerchantBranchGovernanceStatus';
  v_target dastak_v1.branch_status;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
  v_from_status text;
begin
  perform dastak_v1_api.assert_merchant_governance_admin(p_actor_id);
  begin
    v_target := pg_catalog.upper(pg_catalog.btrim(p_status))::dastak_v1.branch_status;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid merchant branch governance status';
  end;
  if v_target not in ('ACTIVE', 'SUSPENDED')
    or p_branch_id is null
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid merchant branch governance command required';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'branchId', p_branch_id, 'status', v_target,
    'expectedVersion', p_expected_version,
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

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'merchant-governance-branch:' || p_branch_id::text, 0
  ));
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'merchant branch not found';
  end if;
  if v_branch.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale merchant branch version';
  end if;
  if (v_target = 'SUSPENDED' and v_branch.status <> 'ACTIVE')
    or (v_target = 'ACTIVE' and v_branch.status <> 'SUSPENDED') then
    raise exception using errcode = '55000', message = 'merchant branch governance transition is not available';
  end if;

  v_from_status := v_branch.status::text;
  update dastak_v1.merchant_branches branch
  set status = v_target,
      updated_at = pg_catalog.now(),
      version = branch.version + 1
  where branch.id = p_branch_id
  returning branch.* into v_branch;

  insert into dastak_v1.audit_events(
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    case when v_target = 'SUSPENDED'
      then 'MERCHANT_BRANCH_SUSPENDED'
      else 'MERCHANT_BRANCH_REACTIVATED' end,
    'merchant_branch', p_branch_id,
    pg_catalog.jsonb_build_object(
      'organizationId', v_branch.organization_id,
      'branchId', p_branch_id,
      'reason', pg_catalog.btrim(p_reason),
      'fromStatus', v_from_status,
      'toStatus', v_target,
      'fromVersion', p_expected_version,
      'version', v_branch.version
    )
  );

  v_response := pg_catalog.jsonb_build_object(
    'organizationId', v_branch.organization_id,
    'branchId', p_branch_id,
    'status', v_branch.status,
    'version', v_branch.version,
    'updatedAt', v_branch.updated_at
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_branch_id
  );
  return v_response;
end;
$$;

create or replace function dastak_v1_api.correct_merchant_branch_details(
  p_actor_id uuid,
  p_branch_id uuid,
  p_changes jsonb,
  p_expected_version bigint,
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
  v_command constant text := 'correctMerchantBranchDetails';
  v_branch dastak_v1.merchant_branches%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
  v_unknown_keys text[];
  v_display_name text;
  v_address jsonb;
  v_address_patch jsonb := '{}'::jsonb;
  v_latitude double precision;
  v_longitude double precision;
  v_location extensions.geometry(Point, 4326);
  v_service_zone_id uuid;
  v_capacity_limit integer;
  v_changed_fields text[] := '{}'::text[];
  v_route_critical boolean := false;
  v_before_summary jsonb;
  v_after_summary jsonb;
begin
  perform dastak_v1_api.assert_merchant_governance_admin(p_actor_id);
  if p_branch_id is null
    or p_changes is null or pg_catalog.jsonb_typeof(p_changes) <> 'object'
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid merchant branch correction required';
  end if;
  select pg_catalog.array_agg(key order by key) into v_unknown_keys
  from pg_catalog.jsonb_object_keys(p_changes) key
  where key not in ('displayName', 'address', 'latitude', 'longitude', 'serviceZoneId', 'capacityLimit');
  if v_unknown_keys is not null or p_changes = '{}'::jsonb then
    raise exception using errcode = '22023', message = 'merchant branch correction contains unsupported fields';
  end if;
  if (p_changes ? 'latitude') <> (p_changes ? 'longitude') then
    raise exception using errcode = '22023', message = 'latitude and longitude must be reviewed together';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'branchId', p_branch_id, 'changes', p_changes,
    'expectedVersion', p_expected_version,
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

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'merchant-governance-branch:' || p_branch_id::text, 0
  ));
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'merchant branch not found';
  end if;
  if v_branch.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale merchant branch version';
  end if;
  if v_branch.status not in ('ACTIVE', 'SUSPENDED') then
    raise exception using errcode = '55000', message = 'merchant branch is not governance eligible';
  end if;

  v_display_name := v_branch.display_name;
  v_address := v_branch.address_snapshot;
  v_location := v_branch.location;
  v_service_zone_id := v_branch.service_zone_id;
  v_capacity_limit := v_branch.capacity_limit;
  v_before_summary := pg_catalog.jsonb_build_object(
    'displayName', v_branch.display_name,
    'normalizedAddress', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'line1', coalesce(v_branch.address_snapshot ->> 'line1', v_branch.address_snapshot ->> 'addressLine1'),
      'line2', coalesce(v_branch.address_snapshot ->> 'line2', v_branch.address_snapshot ->> 'addressLine2'),
      'city', v_branch.address_snapshot ->> 'city',
      'state', v_branch.address_snapshot ->> 'state',
      'postalCode', v_branch.address_snapshot ->> 'postalCode',
      'countryCode', v_branch.address_snapshot ->> 'countryCode'
    )),
    'latitude', case when v_branch.location is null then null else extensions.st_y(v_branch.location) end,
    'longitude', case when v_branch.location is null then null else extensions.st_x(v_branch.location) end,
    'serviceZoneId', v_branch.service_zone_id,
    'capacityLimit', v_branch.capacity_limit
  );

  if p_changes ? 'displayName' then
    if pg_catalog.jsonb_typeof(p_changes -> 'displayName') <> 'string' then
      raise exception using errcode = '22023', message = 'invalid branch display name';
    end if;
    v_display_name := pg_catalog.btrim(p_changes ->> 'displayName');
    if pg_catalog.char_length(v_display_name) not between 1 and 100 then
      raise exception using errcode = '22023', message = 'invalid branch display name';
    end if;
    if v_display_name is distinct from v_branch.display_name then
      v_changed_fields := pg_catalog.array_append(v_changed_fields, 'displayName');
    end if;
  end if;

  if p_changes ? 'address' then
    if pg_catalog.jsonb_typeof(p_changes -> 'address') <> 'object' then
      raise exception using errcode = '22023', message = 'invalid normalized pickup address';
    end if;
    if exists (
      select 1 from pg_catalog.jsonb_object_keys(p_changes -> 'address') key
      where key not in ('line1', 'line2', 'city', 'state', 'postalCode', 'countryCode')
    ) then
      raise exception using errcode = '22023', message = 'normalized pickup address contains unsupported fields';
    end if;
    if pg_catalog.char_length(pg_catalog.btrim(coalesce(p_changes #>> '{address,line1}', ''))) not between 3 and 200
      or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_changes #>> '{address,countryCode}', ''))) <> 2 then
      raise exception using errcode = '22023', message = 'normalized pickup address is incomplete';
    end if;
    v_address_patch := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'line1', pg_catalog.btrim(p_changes #>> '{address,line1}'),
      'line2', nullif(pg_catalog.btrim(coalesce(p_changes #>> '{address,line2}', '')), ''),
      'city', nullif(pg_catalog.btrim(coalesce(p_changes #>> '{address,city}', '')), ''),
      'state', nullif(pg_catalog.btrim(coalesce(p_changes #>> '{address,state}', '')), ''),
      'postalCode', nullif(pg_catalog.btrim(coalesce(p_changes #>> '{address,postalCode}', '')), ''),
      'countryCode', pg_catalog.upper(pg_catalog.btrim(p_changes #>> '{address,countryCode}'))
    ));
    v_address := (v_address - 'line1' - 'line2' - 'addressLine1' - 'addressLine2'
      - 'city' - 'state' - 'postalCode' - 'countryCode') || v_address_patch;
    if v_address is distinct from v_branch.address_snapshot then
      v_changed_fields := pg_catalog.array_append(v_changed_fields, 'normalizedAddress');
      v_route_critical := true;
    end if;
  end if;

  if p_changes ? 'latitude' then
    if pg_catalog.jsonb_typeof(p_changes -> 'latitude') <> 'number'
      or pg_catalog.jsonb_typeof(p_changes -> 'longitude') <> 'number' then
      raise exception using errcode = '22023', message = 'invalid branch coordinates';
    end if;
    begin
      v_latitude := (p_changes ->> 'latitude')::double precision;
      v_longitude := (p_changes ->> 'longitude')::double precision;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception using errcode = '22023', message = 'invalid branch coordinates';
    end;
    if v_latitude is null or v_longitude is null
      or v_latitude not between -90 and 90 or v_longitude not between -180 and 180 then
      raise exception using errcode = '22023', message = 'invalid branch coordinates';
    end if;
    v_location := extensions.st_setsrid(
      extensions.st_makepoint(v_longitude, v_latitude), 4326
    );
    v_address := v_address || pg_catalog.jsonb_build_object(
      'latitude', v_latitude, 'longitude', v_longitude
    );
    if v_branch.location is null
      or not extensions.st_equals(v_location, v_branch.location) then
      v_changed_fields := pg_catalog.array_append(v_changed_fields, 'coordinates');
      v_route_critical := true;
    end if;
  end if;

  if p_changes ? 'serviceZoneId' then
    if pg_catalog.jsonb_typeof(p_changes -> 'serviceZoneId') <> 'string' then
      raise exception using errcode = '22023', message = 'invalid service zone';
    end if;
    begin
      v_service_zone_id := (p_changes ->> 'serviceZoneId')::uuid;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'invalid service zone';
    end;
    if v_service_zone_id is distinct from v_branch.service_zone_id then
      v_changed_fields := pg_catalog.array_append(v_changed_fields, 'serviceZone');
      v_route_critical := true;
    end if;
  end if;

  if p_changes ? 'capacityLimit' then
    if pg_catalog.jsonb_typeof(p_changes -> 'capacityLimit') <> 'number' then
      raise exception using errcode = '22023', message = 'invalid branch capacity';
    end if;
    begin
      v_capacity_limit := (p_changes ->> 'capacityLimit')::integer;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception using errcode = '22023', message = 'invalid branch capacity';
    end;
    if v_capacity_limit is null or v_capacity_limit not between 1 and 500 then
      raise exception using errcode = '22023', message = 'invalid branch capacity';
    end if;
    if v_capacity_limit is distinct from v_branch.capacity_limit then
      v_changed_fields := pg_catalog.array_append(v_changed_fields, 'capacityLimit');
    end if;
  end if;

  if pg_catalog.cardinality(v_changed_fields) = 0 then
    raise exception using errcode = '55000', message = 'merchant branch correction does not change reviewed values';
  end if;
  if v_location is null or v_service_zone_id is null or not exists (
    select 1 from public.service_zones zone
    where zone.id = v_service_zone_id
      and zone.active
      and extensions.st_covers(zone.boundary, v_location)
  ) then
    raise exception using errcode = '22023', message = 'branch location must remain inside the active service zone';
  end if;
  if v_route_critical
    and dastak_v1_api.branch_active_pickup_return_count(p_branch_id) > 0 then
    raise exception using errcode = '55000', message = 'ACTIVE_PICKUP_OR_RETURN_WORK';
  end if;

  update dastak_v1.merchant_branches branch
  set display_name = v_display_name,
      address_snapshot = v_address,
      location = v_location,
      service_zone_id = v_service_zone_id,
      capacity_limit = v_capacity_limit,
      updated_at = pg_catalog.now(),
      version = branch.version + 1
  where branch.id = p_branch_id
  returning branch.* into v_branch;

  v_after_summary := pg_catalog.jsonb_build_object(
    'displayName', v_branch.display_name,
    'normalizedAddress', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'line1', coalesce(v_branch.address_snapshot ->> 'line1', v_branch.address_snapshot ->> 'addressLine1'),
      'line2', coalesce(v_branch.address_snapshot ->> 'line2', v_branch.address_snapshot ->> 'addressLine2'),
      'city', v_branch.address_snapshot ->> 'city',
      'state', v_branch.address_snapshot ->> 'state',
      'postalCode', v_branch.address_snapshot ->> 'postalCode',
      'countryCode', v_branch.address_snapshot ->> 'countryCode'
    )),
    'latitude', extensions.st_y(v_branch.location),
    'longitude', extensions.st_x(v_branch.location),
    'serviceZoneId', v_branch.service_zone_id,
    'capacityLimit', v_branch.capacity_limit
  );

  insert into dastak_v1.audit_events(
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'MERCHANT_BRANCH_DETAILS_CORRECTED',
    'merchant_branch', p_branch_id,
    pg_catalog.jsonb_build_object(
      'organizationId', v_branch.organization_id,
      'branchId', p_branch_id,
      'reason', pg_catalog.btrim(p_reason),
      'changedFields', pg_catalog.array_to_string(v_changed_fields, ', '),
      'outcome', 'Changed: ' || pg_catalog.array_to_string(v_changed_fields, ', '),
      'before', v_before_summary,
      'after', v_after_summary,
      'fromVersion', p_expected_version,
      'version', v_branch.version
    )
  );

  v_response := pg_catalog.jsonb_build_object(
    'organizationId', v_branch.organization_id,
    'branchId', p_branch_id,
    'displayName', v_branch.display_name,
    'status', v_branch.status,
    'version', v_branch.version,
    'changedFields', pg_catalog.to_jsonb(v_changed_fields),
    'updatedAt', v_branch.updated_at
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_branch_id
  );
  return v_response;
end;
$$;

create or replace function public.dastak_v1_admin_merchant_governance_page(
  p_query text default null,
  p_organization_id uuid default null,
  p_branch_id uuid default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_row_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_merchant_governance_page(
    auth.uid(), p_query, p_organization_id, p_branch_id, p_limit,
    p_after_updated_at, p_after_row_id
  )
$$;

create or replace function public.dastak_v1_admin_set_merchant_organization_status(
  p_organization_id uuid,
  p_status text,
  p_expected_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.set_merchant_organization_governance_status(
    auth.uid(), p_organization_id, p_status, p_expected_version,
    p_reason, p_idempotency_key
  )
$$;

create or replace function public.dastak_v1_admin_set_merchant_branch_status(
  p_branch_id uuid,
  p_status text,
  p_expected_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.set_merchant_branch_governance_status(
    auth.uid(), p_branch_id, p_status, p_expected_version,
    p_reason, p_idempotency_key
  )
$$;

create or replace function public.dastak_v1_admin_correct_merchant_branch_details(
  p_branch_id uuid,
  p_changes jsonb,
  p_expected_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.correct_merchant_branch_details(
    auth.uid(), p_branch_id, p_changes, p_expected_version,
    p_reason, p_idempotency_key
  )
$$;

revoke all on function dastak_v1_api.admin_merchant_governance_page(
  uuid,text,uuid,uuid,integer,timestamptz,uuid
) from public, anon;
revoke all on function dastak_v1_api.set_merchant_organization_governance_status(
  uuid,uuid,text,bigint,text,text
) from public, anon;
revoke all on function dastak_v1_api.set_merchant_branch_governance_status(
  uuid,uuid,text,bigint,text,text
) from public, anon;
revoke all on function dastak_v1_api.correct_merchant_branch_details(
  uuid,uuid,jsonb,bigint,text,text
) from public, anon;
grant execute on function dastak_v1_api.admin_merchant_governance_page(
  uuid,text,uuid,uuid,integer,timestamptz,uuid
) to authenticated, service_role;
grant execute on function dastak_v1_api.set_merchant_organization_governance_status(
  uuid,uuid,text,bigint,text,text
) to authenticated, service_role;
grant execute on function dastak_v1_api.set_merchant_branch_governance_status(
  uuid,uuid,text,bigint,text,text
) to authenticated, service_role;
grant execute on function dastak_v1_api.correct_merchant_branch_details(
  uuid,uuid,jsonb,bigint,text,text
) to authenticated, service_role;

revoke all on function public.dastak_v1_admin_merchant_governance_page(
  text,uuid,uuid,integer,timestamptz,uuid
) from public, anon;
revoke all on function public.dastak_v1_admin_set_merchant_organization_status(
  uuid,text,bigint,text,text
) from public, anon;
revoke all on function public.dastak_v1_admin_set_merchant_branch_status(
  uuid,text,bigint,text,text
) from public, anon;
revoke all on function public.dastak_v1_admin_correct_merchant_branch_details(
  uuid,jsonb,bigint,text,text
) from public, anon;
grant execute on function public.dastak_v1_admin_merchant_governance_page(
  text,uuid,uuid,integer,timestamptz,uuid
) to authenticated, service_role;
grant execute on function public.dastak_v1_admin_set_merchant_organization_status(
  uuid,text,bigint,text,text
) to authenticated, service_role;
grant execute on function public.dastak_v1_admin_set_merchant_branch_status(
  uuid,text,bigint,text,text
) to authenticated, service_role;
grant execute on function public.dastak_v1_admin_correct_merchant_branch_details(
  uuid,jsonb,bigint,text,text
) to authenticated, service_role;

comment on function public.dastak_v1_admin_merchant_governance_page(
  text,uuid,uuid,integer,timestamptz,uuid
) is 'Caller-bound, active-Admin Merchant governance projection with bounded keyset pagination.';
comment on function public.dastak_v1_admin_set_merchant_organization_status(
  uuid,text,bigint,text,text
) is 'Governed, versioned and idempotent Merchant organization suspension/reactivation.';
comment on function public.dastak_v1_admin_set_merchant_branch_status(
  uuid,text,bigint,text,text
) is 'Governed, versioned and idempotent Merchant branch suspension/reactivation.';
comment on function public.dastak_v1_admin_correct_merchant_branch_details(
  uuid,jsonb,bigint,text,text
) is 'Governed route-critical Merchant branch correction with active-custody protection.';

-- Extend the existing private Admin invalidation lane without exposing
-- Merchant data in realtime payloads.
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
      'auditHistory', 'merchantGovernance'
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

drop trigger if exists zzz_admin_merchant_organizations_realtime
  on dastak_v1.merchant_organizations;
create trigger zzz_admin_merchant_organizations_realtime
after insert or update or delete on dastak_v1.merchant_organizations
for each row execute function private.broadcast_admin_change(
  'merchantGovernance', 'commandCenter', 'network'
);

drop trigger if exists zzz_admin_merchant_branches_realtime
  on dastak_v1.merchant_branches;
create trigger zzz_admin_merchant_branches_realtime
after insert or update or delete on dastak_v1.merchant_branches
for each row execute function private.broadcast_admin_change(
  'merchantGovernance', 'commandCenter', 'network', 'operationalSafety'
);

drop trigger if exists zzz_admin_fulfilments_realtime on dastak_v1.fulfilments;
create trigger zzz_admin_fulfilments_realtime
after insert or update or delete on dastak_v1.fulfilments
for each row execute function private.broadcast_admin_change(
  'operations', 'liveOrders', 'commandCenter', 'merchantGovernance'
);

drop trigger if exists zzz_admin_delivery_stops_governance_realtime
  on dastak_v1.delivery_stops;
create trigger zzz_admin_delivery_stops_governance_realtime
after insert or update or delete on dastak_v1.delivery_stops
for each row execute function private.broadcast_admin_change('merchantGovernance');

drop trigger if exists zzz_admin_return_stops_governance_realtime
  on dastak_v1.return_stops;
create trigger zzz_admin_return_stops_governance_realtime
after insert or update or delete on dastak_v1.return_stops
for each row execute function private.broadcast_admin_change('merchantGovernance');

drop trigger if exists zzz_admin_return_packages_governance_realtime
  on dastak_v1.return_packages;
create trigger zzz_admin_return_packages_governance_realtime
after insert or update or delete on dastak_v1.return_packages
for each row execute function private.broadcast_admin_change('merchantGovernance');

drop trigger if exists zzz_admin_operational_pause_realtime
  on dastak_v1.operational_pause_controls;
create trigger zzz_admin_operational_pause_realtime
after insert or update or delete on dastak_v1.operational_pause_controls
for each row execute function private.broadcast_admin_change(
  'operationalSafety', 'commandCenter', 'merchantGovernance'
);
