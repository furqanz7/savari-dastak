-- Dastak V1 Step 3: paid preparation, immutable Ready evidence and packages.

create type dastak_v1.package_status as enum (
  'DECLARED', 'READY', 'PICKED_UP', 'IN_TRANSIT', 'DELIVERED',
  'RECOVERY', 'RETURN_PENDING', 'RETURNED'
);

create type dastak_v1.package_custody_owner_type as enum (
  'MERCHANT_BRANCH', 'RIDER', 'CUSTOMER', 'RETURN_RIDER',
  'MERCHANT_RETURN', 'DASTAK_RECOVERY'
);

create type dastak_v1.fulfilment_evidence_type as enum (
  'MERCHANT_READY_PHOTO', 'MERCHANT_PROBLEM_PHOTO'
);

alter table dastak_v1.fulfilments
  add column estimated_ready_at timestamptz,
  add column actual_ready_at timestamptz,
  add column package_count integer;

alter table dastak_v1.fulfilments
  add constraint fulfilments_estimated_ready_after_start_check check (
    estimated_ready_at is null
    or (prep_started_at is not null and estimated_ready_at > prep_started_at)
  ),
  add constraint fulfilments_actual_ready_after_start_check check (
    actual_ready_at is null
    or (prep_started_at is not null and actual_ready_at >= prep_started_at)
  ),
  add constraint fulfilments_ready_timestamps_match_check check (
    ready_at is not distinct from actual_ready_at
  ),
  add constraint fulfilments_package_count_check check (
    package_count is null or package_count >= 1
  );

create table dastak_v1.packages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  fulfilment_id uuid not null references dastak_v1.fulfilments(id),
  package_number integer not null check (package_number >= 1),
  status dastak_v1.package_status not null default 'DECLARED',
  current_custody_owner_type dastak_v1.package_custody_owner_type not null
    default 'MERCHANT_BRANCH',
  current_custody_owner_id uuid not null,
  declared_by uuid not null references public.accounts(id),
  declared_at timestamptz not null default pg_catalog.now(),
  ready_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  unique (fulfilment_id, package_number),
  unique (id, fulfilment_id),
  check (
    (status = 'DECLARED' and ready_at is null and picked_up_at is null and delivered_at is null)
    or (status = 'READY' and ready_at is not null and picked_up_at is null and delivered_at is null)
    or (status in ('PICKED_UP', 'IN_TRANSIT') and ready_at is not null and picked_up_at is not null and delivered_at is null)
    or (status = 'DELIVERED' and ready_at is not null and picked_up_at is not null and delivered_at is not null)
    or status in ('RECOVERY', 'RETURN_PENDING', 'RETURNED')
  )
);

create index packages_order_idx on dastak_v1.packages (order_id, status);
create index packages_fulfilment_status_idx
  on dastak_v1.packages (fulfilment_id, status, package_number);
create index packages_declared_by_idx on dastak_v1.packages (declared_by);
create index packages_custody_idx
  on dastak_v1.packages (current_custody_owner_type, current_custody_owner_id, status);

create table dastak_v1.fulfilment_evidence (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  fulfilment_id uuid not null references dastak_v1.fulfilments(id),
  package_id uuid,
  evidence_type dastak_v1.fulfilment_evidence_type not null,
  object_path text not null unique check (
    pg_catalog.char_length(object_path) between 1 and 500
  ),
  content_type text not null check (content_type in ('image/jpeg', 'image/png', 'image/heic')),
  content_length_bytes bigint check (
    content_length_bytes is null
    or content_length_bytes between 1 and 10485760
  ),
  captured_by uuid not null references public.accounts(id),
  captured_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  foreign key (package_id, fulfilment_id)
    references dastak_v1.packages(id, fulfilment_id),
  check (
    evidence_type <> 'MERCHANT_READY_PHOTO'
    or captured_at is not null
  )
);

create index fulfilment_evidence_order_idx
  on dastak_v1.fulfilment_evidence (order_id, captured_at, id);
create index fulfilment_evidence_fulfilment_idx
  on dastak_v1.fulfilment_evidence (fulfilment_id, evidence_type, captured_at, id);
create index fulfilment_evidence_package_idx
  on dastak_v1.fulfilment_evidence (package_id, fulfilment_id);
create index fulfilment_evidence_captured_by_idx
  on dastak_v1.fulfilment_evidence (captured_by, captured_at);

create table dastak_v1.fulfilment_problem_reports (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  fulfilment_id uuid not null references dastak_v1.fulfilments(id),
  reported_by uuid not null references public.accounts(id),
  fulfilment_status_at_report dastak_v1.fulfilment_status not null,
  reason text not null check (pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 500),
  reported_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);

create index fulfilment_problem_reports_order_idx
  on dastak_v1.fulfilment_problem_reports (order_id, reported_at, id);
create index fulfilment_problem_reports_fulfilment_idx
  on dastak_v1.fulfilment_problem_reports (fulfilment_id, reported_at, id);
create index fulfilment_problem_reports_reported_by_idx
  on dastak_v1.fulfilment_problem_reports (reported_by, reported_at);

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values
  (
    'preparation.rider_match_threshold_seconds',
    'DURATION_SECONDS',
    'Locked V1 threshold at which every fulfilment may enter rider matching.',
    '300'::jsonb,
    '{"minimum":300,"maximum":300}'::jsonb,
    true,
    false
  ),
  (
    'preparation.merchant_ready_photo_required',
    'BOOLEAN',
    'Locked V1 requirement for in-app merchant Ready evidence.',
    'true'::jsonb,
    '{"allowedValues":[true]}'::jsonb,
    true,
    false
  );

create function dastak_v1.reject_step3_history_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Dastak V1 preparation history is append-only';
end;
$$;

create function dastak_v1.guard_package()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
  if old.ready_at is not null and new.ready_at is distinct from old.ready_at then
    raise exception 'package Ready timestamp cannot change';
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
  if new.package_count is not null and new.status <> 'PREPARING' and old.package_count is null then
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

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger packages_guard
before update on dastak_v1.packages
for each row execute function dastak_v1.guard_package();
create trigger packages_no_delete
before delete on dastak_v1.packages
for each row execute function dastak_v1.reject_step3_history_mutation();
create trigger fulfilment_evidence_immutable
before update or delete on dastak_v1.fulfilment_evidence
for each row execute function dastak_v1.reject_step3_history_mutation();
create trigger fulfilment_problem_reports_immutable
before update or delete on dastak_v1.fulfilment_problem_reports
for each row execute function dastak_v1.reject_step3_history_mutation();

alter table dastak_v1.packages enable row level security;
alter table dastak_v1.fulfilment_evidence enable row level security;
alter table dastak_v1.fulfilment_problem_reports enable row level security;

revoke all on table dastak_v1.packages from public, anon, authenticated;
revoke all on table dastak_v1.fulfilment_evidence from public, anon, authenticated;
revoke all on table dastak_v1.fulfilment_problem_reports from public, anon, authenticated;
grant select, insert, update on table dastak_v1.packages to service_role;
grant select, insert on table dastak_v1.fulfilment_evidence to service_role;
grant select, insert on table dastak_v1.fulfilment_problem_reports to service_role;

create policy dastak_v1_merchant_ready_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'merchant-ready'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
);

create policy dastak_v1_merchant_ready_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'merchant-ready'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
);

create function dastak_v1.fulfilment_rider_match_eligible_at(
  p_status dastak_v1.fulfilment_status,
  p_estimated_ready_at timestamptz,
  p_evaluated_at timestamptz
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select p_status in ('READY', 'PICKED_UP', 'COMPLETED')
    or (
      p_status = 'PREPARING'
      and p_estimated_ready_at is not null
      and p_estimated_ready_at <= p_evaluated_at + pg_catalog.make_interval(secs => 300)
    );
$$;

create function dastak_v1_api.order_rider_match_eligibility(
  p_order_id uuid,
  p_evaluated_at timestamptz
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with required as (
    select
      fulfilment.id,
      fulfilment.status,
      fulfilment.estimated_ready_at,
      dastak_v1.fulfilment_rider_match_eligible_at(
        fulfilment.status,
        fulfilment.estimated_ready_at,
        p_evaluated_at
      ) as satisfied
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = p_order_id
      and fulfilment.status <> 'RELEASED'
  )
  select pg_catalog.jsonb_build_object(
    'eligible', count(*) > 0 and pg_catalog.bool_and(required.satisfied),
    'evaluatedAt', p_evaluated_at,
    'thresholdSeconds', 300,
    'requiredFulfilmentCount', count(*),
    'satisfiedFulfilmentCount', count(*) filter (where required.satisfied),
    'nextEligibleAt', max(
      required.estimated_ready_at - pg_catalog.make_interval(secs => 300)
    ) filter (where required.status = 'PREPARING')
  )
  from required;
$$;

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
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_fulfilment.organization_id,
    'merchant.fulfilment.manage',
    v_fulfilment.branch_id
  ) then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_fulfilment.order_id;
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = v_fulfilment.branch_id;

  return pg_catalog.jsonb_build_object(
    'id', v_fulfilment.id,
    'orderId', v_order.id,
    'displayOrderNumber', v_order.display_order_number,
    'orderStatus', v_order.status,
    'status', v_fulfilment.status,
    'version', v_fulfilment.version,
    'branch', pg_catalog.jsonb_build_object(
      'id', v_branch.id,
      'displayName', v_branch.display_name
    ),
    'promisedPrepMinutes', v_fulfilment.promised_prep_minutes,
    'prepStartedAt', v_fulfilment.prep_started_at,
    'estimatedReadyAt', v_fulfilment.estimated_ready_at,
    'actualReadyAt', v_fulfilment.actual_ready_at,
    'secondsRemaining', case
      when v_fulfilment.status = 'PREPARING' then greatest(
        0,
        pg_catalog.ceil(
          extract(epoch from (v_fulfilment.estimated_ready_at - v_now))
        )::integer
      )
      else 0
    end,
    'runningLate', v_fulfilment.status = 'PREPARING'
      and v_now > v_fulfilment.estimated_ready_at,
    'lateSeconds', case
      when v_fulfilment.status = 'PREPARING'
        and v_now > v_fulfilment.estimated_ready_at then
        pg_catalog.floor(
          extract(epoch from (v_now - v_fulfilment.estimated_ready_at))
        )::integer
      else 0
    end,
    'packageCount', v_fulfilment.package_count,
    'packages', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', package.id,
        'packageNumber', package.package_number,
        'status', package.status,
        'custodyOwnerType', package.current_custody_owner_type,
        'declaredAt', package.declared_at,
        'readyAt', package.ready_at,
        'version', package.version
      ) order by package.package_number)
      from dastak_v1.packages package
      where package.fulfilment_id = v_fulfilment.id
    ), '[]'::jsonb),
    'evidence', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(
        pg_catalog.jsonb_build_object(
          'id', evidence.id,
          'packageId', evidence.package_id,
          'type', evidence.evidence_type,
          'objectPath', evidence.object_path,
          'contentType', evidence.content_type,
          'capturedAt', evidence.captured_at
        )
      ) order by evidence.captured_at, evidence.id)
      from dastak_v1.fulfilment_evidence evidence
      where evidence.fulfilment_id = v_fulfilment.id
    ), '[]'::jsonb),
    'problemReports', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', problem.id,
        'statusAtReport', problem.fulfilment_status_at_report,
        'reason', problem.reason,
        'reportedAt', problem.reported_at
      ) order by problem.reported_at, problem.id)
      from dastak_v1.fulfilment_problem_reports problem
      where problem.fulfilment_id = v_fulfilment.id
    ), '[]'::jsonb),
    'capacity', (
      select pg_catalog.jsonb_build_object(
        'status', slot.status,
        'heldAt', slot.held_at,
        'releasedAt', slot.released_at,
        'releaseReason', slot.release_reason
      )
      from dastak_v1.retail_capacity_slots slot
      where slot.fulfilment_id = v_fulfilment.id
    ),
    'riderMatchEligibility', dastak_v1_api.order_rider_match_eligibility(
      v_order.id, v_now
    ),
    'canDeclarePackages', v_fulfilment.status = 'PREPARING'
      and v_fulfilment.package_count is null,
    'canAddEvidence', v_fulfilment.status = 'PREPARING',
    'canMarkReady', v_fulfilment.status = 'PREPARING'
      and v_fulfilment.package_count is not null
      and exists (
        select 1
        from dastak_v1.fulfilment_evidence evidence
        where evidence.fulfilment_id = v_fulfilment.id
          and evidence.evidence_type = 'MERCHANT_READY_PHOTO'
      ),
    'readyIsIrreversible', true,
    'lines', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'orderLineId', order_line.id,
        'skuId', order_line.sku_id,
        'name', order_line.product_name_snapshot,
        'variant', order_line.variant_snapshot,
        'packSize', order_line.pack_size_snapshot,
        'quantity', fulfilment_line.confirmed_quantity
      ) order by order_line.created_at, order_line.id)
      from dastak_v1.fulfilment_lines fulfilment_line
      join dastak_v1.order_lines order_line
        on order_line.id = fulfilment_line.order_line_id
      where fulfilment_line.fulfilment_id = v_fulfilment.id
    ), '[]'::jsonb)
  );
end;
$$;

create function dastak_v1_api.list_merchant_fulfilments(
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
    where fulfilment.status in ('RESERVED_PREPAYMENT', 'PREPARING', 'READY')
      and dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id,
        fulfilment.organization_id,
        'merchant.fulfilment.manage',
        fulfilment.branch_id
      )
    order by fulfilment.committed_at desc, fulfilment.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
  ) visible;
$$;

create function dastak_v1_api.declare_fulfilment_packages(
  p_actor_id uuid,
  p_fulfilment_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_package_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'declareFulfilmentPackages';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200
    or p_package_count is null
    or p_package_count not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'invalid package declaration';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'fulfilmentId', p_fulfilment_id,
    'expectedVersion', p_expected_version,
    'packageCount', p_package_count
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select fulfilment.order_id into v_order_id
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_fulfilment.organization_id,
    'merchant.fulfilment.manage',
    v_fulfilment.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if v_fulfilment.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale fulfilment version';
  end if;
  if v_order.status <> 'PREPARING'
    or v_fulfilment.status <> 'PREPARING'
    or v_fulfilment.package_count is not null then
    raise exception using errcode = '55000',
      message = 'packages can only be declared once while the fulfilment is Preparing';
  end if;

  insert into dastak_v1.packages (
    order_id, fulfilment_id, package_number,
    current_custody_owner_type, current_custody_owner_id, declared_by
  )
  select
    v_order.id,
    v_fulfilment.id,
    package_number,
    'MERCHANT_BRANCH',
    v_fulfilment.branch_id,
    p_actor_id
  from pg_catalog.generate_series(1, p_package_count) package_number;

  update dastak_v1.fulfilments
  set package_count = p_package_count,
      version = version + 1
  where id = v_fulfilment.id
  returning * into v_fulfilment;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_fulfilment.id::text || ':PACKAGES_DECLARED:' || v_fulfilment.version::text,
    'FULFILMENT',
    v_fulfilment.id,
    v_fulfilment.version,
    'FULFILMENT_PACKAGES_DECLARED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment.id,
      'packageCount', p_package_count,
      'custodyOwnerType', 'MERCHANT_BRANCH'
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'FULFILMENT_PACKAGES_DECLARED',
    'fulfilment',
    v_fulfilment.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'branchId', v_fulfilment.branch_id,
      'packageCount', p_package_count,
      'idempotencyKey', p_idempotency_key
    )
  );

  v_response := dastak_v1_api.merchant_fulfilment_json(
    p_actor_id, v_fulfilment.id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_fulfilment.id
  );
  return v_response;
end;
$$;

create function dastak_v1_api.add_fulfilment_ready_evidence(
  p_actor_id uuid,
  p_fulfilment_id uuid,
  p_package_id uuid,
  p_object_path text,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'addFulfilmentReadyEvidence';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_evidence dastak_v1.fulfilment_evidence%rowtype;
  v_storage_metadata jsonb;
  v_content_type text;
  v_content_length bigint;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200
    or p_object_path is null
    or p_object_path !~ (
      '^merchant-ready/' || p_actor_id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
    ) then
    raise exception using errcode = '22023', message = 'invalid Ready evidence';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'fulfilmentId', p_fulfilment_id,
    'packageId', p_package_id,
    'objectPath', p_object_path,
    'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select fulfilment.order_id into v_order_id
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_fulfilment.organization_id,
    'merchant.fulfilment.manage',
    v_fulfilment.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if v_fulfilment.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale fulfilment version';
  end if;
  if v_order.status <> 'PREPARING' or v_fulfilment.status <> 'PREPARING' then
    raise exception using errcode = '55000',
      message = 'Ready evidence can only be added while Preparing';
  end if;
  if p_package_id is not null and not exists (
    select 1
    from dastak_v1.packages package
    where package.id = p_package_id
      and package.fulfilment_id = v_fulfilment.id
      and package.status = 'DECLARED'
  ) then
    raise exception using errcode = '22023',
      message = 'evidence package does not belong to this fulfilment';
  end if;

  select object.metadata into v_storage_metadata
  from storage.objects object
  where object.bucket_id = 'dastak-evidence'
    and object.name = p_object_path;
  if not found then
    raise exception using errcode = 'P0002', message = 'Ready evidence upload was not found';
  end if;
  v_content_type := coalesce(
    v_storage_metadata ->> 'mimetype',
    case
      when p_object_path ~ '\.(jpg|jpeg)$' then 'image/jpeg'
      when p_object_path ~ '\.png$' then 'image/png'
      when p_object_path ~ '\.heic$' then 'image/heic'
    end
  );
  if v_content_type not in ('image/jpeg', 'image/png', 'image/heic') then
    raise exception using errcode = '22023', message = 'Ready evidence must be an image';
  end if;
  if coalesce(v_storage_metadata ->> 'size', '') ~ '^[0-9]+$' then
    v_content_length := (v_storage_metadata ->> 'size')::bigint;
  end if;
  if v_content_length is not null and v_content_length not between 1 and 10485760 then
    raise exception using errcode = '22023', message = 'Ready evidence image is too large';
  end if;

  insert into dastak_v1.fulfilment_evidence (
    order_id, fulfilment_id, package_id, evidence_type,
    object_path, content_type, content_length_bytes, captured_by
  ) values (
    v_order.id,
    v_fulfilment.id,
    p_package_id,
    'MERCHANT_READY_PHOTO',
    p_object_path,
    v_content_type,
    v_content_length,
    p_actor_id
  ) returning * into v_evidence;

  update dastak_v1.fulfilments
  set version = version + 1
  where id = v_fulfilment.id
  returning * into v_fulfilment;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_evidence.id::text || ':MERCHANT_READY_EVIDENCE_CAPTURED:1',
    'FULFILMENT_EVIDENCE',
    v_evidence.id,
    1,
    'MERCHANT_READY_EVIDENCE_CAPTURED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment.id,
      'packageId', p_package_id,
      'evidenceId', v_evidence.id,
      'objectPath', p_object_path
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'MERCHANT_READY_EVIDENCE_CAPTURED',
    'fulfilment_evidence',
    v_evidence.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment.id,
      'packageId', p_package_id,
      'objectPath', p_object_path,
      'idempotencyKey', p_idempotency_key
    )
  );

  v_response := dastak_v1_api.merchant_fulfilment_json(
    p_actor_id, v_fulfilment.id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_fulfilment.id
  );
  return v_response;
end;
$$;

create function dastak_v1_api.mark_fulfilment_ready(
  p_actor_id uuid,
  p_fulfilment_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'markFulfilmentReady';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_package_count integer;
  v_released_capacity integer;
  v_eligibility jsonb;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'fulfilmentId', p_fulfilment_id,
    'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select fulfilment.order_id into v_order_id
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;

  -- Preparation commands lock order, fulfilment, packages, evidence, then capacity.
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_fulfilment.organization_id,
    'merchant.fulfilment.manage',
    v_fulfilment.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if v_fulfilment.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale fulfilment version';
  end if;
  if v_order.status <> 'PREPARING'
    or not exists (
      select 1
      from dastak_v1.payments payment
      where payment.order_id = v_order.id and payment.status = 'SUCCEEDED'
    ) then
    raise exception using errcode = '55000',
      message = 'order payment has not started preparation';
  end if;
  if v_fulfilment.status <> 'PREPARING' then
    raise exception using errcode = '55000',
      message = 'only a Preparing fulfilment can become Ready';
  end if;
  if v_fulfilment.package_count is null then
    raise exception using errcode = '55000',
      message = 'declare package count before marking Ready';
  end if;

  perform 1
  from dastak_v1.packages package
  where package.fulfilment_id = v_fulfilment.id
  order by package.id
  for update;
  select count(*) into v_package_count
  from dastak_v1.packages package
  where package.fulfilment_id = v_fulfilment.id
    and package.status = 'DECLARED'
    and package.current_custody_owner_type = 'MERCHANT_BRANCH'
    and package.current_custody_owner_id = v_fulfilment.branch_id;
  if v_package_count <> v_fulfilment.package_count then
    raise exception using errcode = '55000',
      message = 'every declared package must be present before Ready';
  end if;

  perform 1
  from dastak_v1.fulfilment_evidence evidence
  where evidence.fulfilment_id = v_fulfilment.id
  order by evidence.id
  for share;
  if not exists (
    select 1
    from dastak_v1.fulfilment_evidence evidence
    where evidence.fulfilment_id = v_fulfilment.id
      and evidence.evidence_type = 'MERCHANT_READY_PHOTO'
  ) then
    raise exception using errcode = '55000',
      message = 'merchant Ready evidence is required';
  end if;

  perform 1
  from dastak_v1.retail_capacity_slots slot
  where slot.fulfilment_id = v_fulfilment.id
  for update;

  update dastak_v1.packages
  set status = 'READY',
      ready_at = v_now,
      version = version + 1
  where fulfilment_id = v_fulfilment.id
    and status = 'DECLARED';

  update dastak_v1.fulfilments
  set status = 'READY',
      ready_at = v_now,
      actual_ready_at = v_now,
      version = version + 1
  where id = v_fulfilment.id
  returning * into v_fulfilment;

  if v_fulfilment.fulfilment_type = 'RETAIL' then
    update dastak_v1.retail_capacity_slots
    set status = 'RELEASED',
        released_at = v_now,
        release_reason = 'FULFILMENT_READY',
        version = version + 1
    where fulfilment_id = v_fulfilment.id
      and status = 'HELD';
    get diagnostics v_released_capacity = row_count;
    if v_released_capacity <> 1 then
      raise exception 'Ready must release exactly one retail capacity slot';
    end if;
  end if;

  v_eligibility := dastak_v1_api.order_rider_match_eligibility(v_order.id, v_now);
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_fulfilment.id::text || ':FULFILMENT_READY:' || v_fulfilment.version::text,
    'FULFILMENT',
    v_fulfilment.id,
    v_fulfilment.version,
    'FULFILMENT_READY',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment.id,
      'branchId', v_fulfilment.branch_id,
      'actualReadyAt', v_fulfilment.actual_ready_at,
      'packageCount', v_fulfilment.package_count,
      'capacityReleased', v_fulfilment.fulfilment_type = 'RETAIL',
      'orderRiderMatchEligible', (v_eligibility ->> 'eligible')::boolean
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'FULFILMENT_READY',
    'fulfilment',
    v_fulfilment.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'branchId', v_fulfilment.branch_id,
      'packageCount', v_fulfilment.package_count,
      'actualReadyAt', v_fulfilment.actual_ready_at,
      'idempotencyKey', p_idempotency_key,
      'riderMatchEligibility', v_eligibility
    )
  );

  v_response := dastak_v1_api.merchant_fulfilment_json(
    p_actor_id, v_fulfilment.id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_fulfilment.id
  );
  return v_response;
end;
$$;

create function dastak_v1_api.report_fulfilment_problem(
  p_actor_id uuid,
  p_fulfilment_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'reportFulfilmentProblem';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_problem dastak_v1.fulfilment_problem_reports%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  p_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200
    or pg_catalog.char_length(p_reason) not between 3 and 500 then
    raise exception using errcode = '22023', message = 'invalid fulfilment problem';
  end if;
  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'fulfilmentId', p_fulfilment_id,
    'reason', p_reason,
    'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select fulfilment.order_id into v_order_id
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_fulfilment.organization_id,
    'merchant.fulfilment.manage',
    v_fulfilment.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if v_fulfilment.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale fulfilment version';
  end if;
  if v_order.status <> 'PREPARING'
    or v_fulfilment.status not in ('PREPARING', 'READY') then
    raise exception using errcode = '55000',
      message = 'this fulfilment cannot accept a preparation problem report';
  end if;

  insert into dastak_v1.fulfilment_problem_reports (
    order_id, fulfilment_id, reported_by, fulfilment_status_at_report, reason
  ) values (
    v_order.id, v_fulfilment.id, p_actor_id, v_fulfilment.status, p_reason
  ) returning * into v_problem;
  update dastak_v1.fulfilments
  set version = version + 1
  where id = v_fulfilment.id
  returning * into v_fulfilment;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_fulfilment.id::text || ':FULFILMENT_EXCEPTION_REPORTED:' || v_fulfilment.version::text,
    'FULFILMENT',
    v_fulfilment.id,
    v_fulfilment.version,
    'FULFILMENT_EXCEPTION_REPORTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment.id,
      'problemReportId', v_problem.id,
      'statusPreserved', v_problem.fulfilment_status_at_report,
      'reason', p_reason
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'FULFILMENT_EXCEPTION_REPORTED',
    'fulfilment_problem_report',
    v_problem.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment.id,
      'statusPreserved', v_problem.fulfilment_status_at_report,
      'idempotencyKey', p_idempotency_key
    )
  );

  v_response := dastak_v1_api.merchant_fulfilment_json(
    p_actor_id, v_fulfilment.id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_fulfilment.id
  );
  return v_response;
end;
$$;

create function dastak_v1.start_preparation_after_payment_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_required_count integer;
begin
  if new.outcome <> 'SUCCEEDED' then
    return new;
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = new.order_id
  for update;
  if v_order.status <> 'PAID' then
    raise exception 'successful payment must first place its order in PAID';
  end if;

  perform 1
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = v_order.id
  order by fulfilment.id
  for update;
  select count(*) into v_required_count
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = v_order.id
    and fulfilment.status <> 'RELEASED';
  if v_required_count = 0 or exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = v_order.id
      and (
        fulfilment.status <> 'RESERVED_PREPAYMENT'
        or fulfilment.prep_started_at is not null
        or fulfilment.estimated_ready_at is not null
      )
  ) then
    raise exception 'payment cannot start an incomplete or already-started preparation set';
  end if;

  for v_fulfilment in
    update dastak_v1.fulfilments fulfilment
    set status = 'PREPARING',
        prep_started_at = v_now,
        estimated_ready_at = v_now + pg_catalog.make_interval(
          mins => fulfilment.promised_prep_minutes
        ),
        version = fulfilment.version + 1
    where fulfilment.order_id = v_order.id
      and fulfilment.status = 'RESERVED_PREPAYMENT'
    returning fulfilment.*
  loop
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, payload
    ) values (
      v_fulfilment.id::text || ':PREPARATION_STARTED:' || v_fulfilment.version::text,
      'FULFILMENT',
      v_fulfilment.id,
      v_fulfilment.version,
      'PREPARATION_STARTED',
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'fulfilmentId', v_fulfilment.id,
        'branchId', v_fulfilment.branch_id,
        'promisedPrepMinutes', v_fulfilment.promised_prep_minutes,
        'prepStartedAt', v_fulfilment.prep_started_at,
        'estimatedReadyAt', v_fulfilment.estimated_ready_at
      )
    );
  end loop;

  update dastak_v1.order_lines order_line
  set status = 'FULFILLING',
      version = order_line.version + 1
  where order_line.order_id = v_order.id
    and order_line.status = 'RESERVED';

  update dastak_v1.orders
  set status = 'PREPARING',
      version = version + 1
  where id = v_order.id
  returning * into v_order;

  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, reason, metadata
  ) values (
    v_order.id,
    'PAID',
    'PREPARING',
    v_order.version,
    'startPreparationAfterPayment',
    'All selected fulfilments started from the authoritative payment timestamp.',
    pg_catalog.jsonb_build_object(
      'paymentId', new.payment_id,
      'paymentAttemptId', new.payment_attempt_id,
      'providerEventId', new.provider_event_id,
      'requiredFulfilmentCount', v_required_count,
      'prepStartedAt', v_now
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_order.id::text || ':ORDER_PREPARATION_STARTED:' || v_order.version::text,
    'ORDER',
    v_order.id,
    v_order.version,
    'PREPARATION_STARTED',
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'requiredFulfilmentCount', v_required_count,
      'prepStartedAt', v_now,
      'status', 'PREPARING'
    )
  );
  insert into dastak_v1.audit_events (
    action, resource_type, resource_id, metadata
  ) values (
    'PREPARATION_STARTED',
    'order',
    v_order.id,
    pg_catalog.jsonb_build_object(
      'paymentId', new.payment_id,
      'paymentAttemptId', new.payment_attempt_id,
      'providerEventId', new.provider_event_id,
      'requiredFulfilmentCount', v_required_count,
      'prepStartedAt', v_now,
      'version', v_order.version
    )
  );
  return new;
end;
$$;

create trigger payment_provider_events_start_preparation
after insert on dastak_v1.payment_provider_events
for each row
when (new.outcome = 'SUCCEEDED')
execute function dastak_v1.start_preparation_after_payment_event();

create function dastak_v1_api.record_preparing_payment_duplicate(
  p_provider_event_id text,
  p_event_type text,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_amount_paise bigint,
  p_occurred_at timestamptz,
  p_request_digest text
)
returns table(handled boolean, response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_identity record;
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_attempt dastak_v1.payment_attempts%rowtype;
  v_response jsonb;
begin
  if p_provider_event_id is null
    or pg_catalog.char_length(p_provider_event_id) not between 1 and 200
    or p_event_type <> 'payment_captured'
    or p_provider_order_reference !~ '^order_[A-Za-z0-9]+$'
    or p_provider_payment_reference !~ '^pay_[A-Za-z0-9]+$'
    or p_amount_paise is null or p_amount_paise <= 0
    or p_occurred_at is null
    or p_request_digest !~ '^[0-9a-f]{64}$' then
    handled := false;
    response_body := null;
    response_status := null;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-razorpay-event:' || p_provider_event_id, 0
  ));
  if exists (
    select 1
    from dastak_v1.payment_provider_events event
    where event.provider = 'RAZORPAY'
      and event.provider_event_id = p_provider_event_id
  ) then
    handled := false;
    response_body := null;
    response_status := null;
    return next;
    return;
  end if;

  select attempt.order_id, attempt.payment_id, attempt.id as attempt_id
  into v_identity
  from dastak_v1.payment_attempts attempt
  where attempt.provider = 'RAZORPAY'
    and attempt.provider_order_reference = p_provider_order_reference;
  if not found then
    handled := false;
    response_body := null;
    response_status := null;
    return next;
    return;
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_identity.order_id
  for update;
  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.id = v_identity.payment_id
  for update;
  select attempt.* into v_attempt
  from dastak_v1.payment_attempts attempt
  where attempt.id = v_identity.attempt_id
  for update;

  if v_order.status <> 'PREPARING'
    or v_payment.status <> 'SUCCEEDED'
    or v_attempt.status <> 'SUCCEEDED'
    or v_payment.provider_payment_reference is distinct from p_provider_payment_reference
    or v_attempt.provider_payment_reference is distinct from p_provider_payment_reference
    or v_payment.amount_paise <> p_amount_paise then
    handled := false;
    response_body := null;
    response_status := null;
    return next;
    return;
  end if;

  v_response := pg_catalog.jsonb_build_object(
    'received', true,
    'processed', true,
    'duplicate', true,
    'orderId', v_order.id,
    'status', 'PREPARING'
  );
  insert into dastak_v1.payment_provider_events (
    provider, provider_event_id, event_type, order_id, payment_id,
    payment_attempt_id, provider_order_reference,
    provider_payment_reference, amount_paise, currency_code,
    occurred_at, request_digest, outcome, response_body
  ) values (
    'RAZORPAY',
    p_provider_event_id,
    p_event_type,
    v_order.id,
    v_payment.id,
    v_attempt.id,
    p_provider_order_reference,
    p_provider_payment_reference,
    p_amount_paise,
    'INR',
    p_occurred_at,
    p_request_digest,
    'DUPLICATE',
    v_response
  );
  handled := true;
  response_body := v_response;
  response_status := 200;
  return next;
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
declare
  v_duplicate record;
begin
  if p_event_type <> 'payment_captured' or p_provider_refund_reference is not null then
    return query select
      pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'payment_not_found',
          'message', 'The event does not belong to a Dastak V1 payment.'
        )
      ),
      404;
    return;
  end if;

  select duplicate.* into v_duplicate
  from dastak_v1_api.record_preparing_payment_duplicate(
    p_provider_event_id,
    p_event_type,
    p_provider_order_reference,
    p_provider_payment_reference,
    p_amount_paise,
    p_occurred_at,
    p_request_digest
  ) duplicate;
  if v_duplicate.handled then
    response_body := v_duplicate.response_body;
    response_status := v_duplicate.response_status;
    return next;
    return;
  end if;

  return query
  select *
  from dastak_v1_api.record_razorpay_payment_event(
    p_provider_event_id,
    p_event_type,
    p_provider_order_reference,
    p_provider_payment_reference,
    p_amount_paise,
    p_occurred_at,
    p_request_digest
  );
end;
$$;

alter function dastak_v1_api.order_json(uuid, uuid)
  rename to order_json_step2;

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
  v_order := dastak_v1_api.order_json_step2(p_order_id, p_customer_id);
  if v_order is null then
    return null;
  end if;
  if v_order ->> 'status' in ('PAID', 'PREPARING') then
    v_order := pg_catalog.jsonb_set(v_order, '{customerState}', '"PREPARING"'::jsonb, true);
    v_order := pg_catalog.jsonb_set(
      v_order,
      '{fulfilmentProgress}',
      '{"state":"PREPARING","title":"Preparing your order"}'::jsonb,
      true
    );
  end if;
  return v_order;
end;
$$;

alter function dastak_v1_api.merchant_opportunity_json(uuid, uuid)
  rename to merchant_opportunity_json_step2;

create function dastak_v1_api.merchant_opportunity_json(
  p_actor_id uuid,
  p_opportunity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_order_status dastak_v1.order_status;
  v_fulfilment_status dastak_v1.fulfilment_status;
begin
  v_result := dastak_v1_api.merchant_opportunity_json_step2(
    p_actor_id, p_opportunity_id
  );
  select customer_order.status, fulfilment.status
  into v_order_status, v_fulfilment_status
  from dastak_v1.merchant_opportunities opportunity
  join dastak_v1.orders customer_order on customer_order.id = opportunity.order_id
  left join dastak_v1.fulfilments fulfilment
    on fulfilment.source_opportunity_id = opportunity.id
  where opportunity.id = p_opportunity_id;

  if v_order_status = 'PREPARING' and v_fulfilment_status = 'PREPARING' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{reservationState}', '"PREPARING"'::jsonb, true
    );
    v_result := pg_catalog.jsonb_set(
      v_result, '{orderPaymentState}', '"PAID"'::jsonb, true
    );
  elsif v_order_status = 'PREPARING' and v_fulfilment_status = 'READY' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{reservationState}', '"READY_FOR_PICKUP"'::jsonb, true
    );
    v_result := pg_catalog.jsonb_set(
      v_result, '{orderPaymentState}', '"PAID"'::jsonb, true
    );
  end if;
  return v_result;
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_step2;

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
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  v_trace := dastak_v1_api.admin_execution_trace_step2(p_actor_id, p_order_id);
  return v_trace || pg_catalog.jsonb_build_object(
    'preparation', pg_catalog.jsonb_build_object(
      'riderMatchEligibility', dastak_v1_api.order_rider_match_eligibility(
        p_order_id, v_now
      ),
      'fulfilments', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', fulfilment.id,
          'organizationId', fulfilment.organization_id,
          'branchId', fulfilment.branch_id,
          'branchName', branch.display_name,
          'fulfilmentType', fulfilment.fulfilment_type,
          'status', fulfilment.status,
          'version', fulfilment.version,
          'promisedPrepMinutes', fulfilment.promised_prep_minutes,
          'prepStartedAt', fulfilment.prep_started_at,
          'estimatedReadyAt', fulfilment.estimated_ready_at,
          'actualReadyAt', fulfilment.actual_ready_at,
          'runningLate', fulfilment.status = 'PREPARING'
            and v_now > fulfilment.estimated_ready_at,
          'lateSeconds', case
            when fulfilment.status = 'PREPARING'
              and v_now > fulfilment.estimated_ready_at then
              pg_catalog.floor(extract(epoch from (
                v_now - fulfilment.estimated_ready_at
              )))::integer
            else 0
          end,
          'packageCount', fulfilment.package_count,
          'merchantEvidenceCount', (
            select count(*)
            from dastak_v1.fulfilment_evidence evidence
            where evidence.fulfilment_id = fulfilment.id
              and evidence.evidence_type = 'MERCHANT_READY_PHOTO'
          ),
          'capacity', (
            select pg_catalog.jsonb_build_object(
              'status', slot.status,
              'heldAt', slot.held_at,
              'releasedAt', slot.released_at,
              'releaseReason', slot.release_reason,
              'version', slot.version
            )
            from dastak_v1.retail_capacity_slots slot
            where slot.fulfilment_id = fulfilment.id
          )
        ) order by fulfilment.committed_at, fulfilment.id)
        from dastak_v1.fulfilments fulfilment
        join dastak_v1.merchant_branches branch on branch.id = fulfilment.branch_id
        where fulfilment.order_id = p_order_id
      ), '[]'::jsonb),
      'packages', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', package.id,
          'fulfilmentId', package.fulfilment_id,
          'packageNumber', package.package_number,
          'status', package.status,
          'custodyOwnerType', package.current_custody_owner_type,
          'custodyOwnerId', package.current_custody_owner_id,
          'declaredBy', package.declared_by,
          'declaredAt', package.declared_at,
          'readyAt', package.ready_at,
          'version', package.version
        ) order by package.fulfilment_id, package.package_number)
        from dastak_v1.packages package
        where package.order_id = p_order_id
      ), '[]'::jsonb),
      'evidence', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(
          pg_catalog.jsonb_build_object(
            'id', evidence.id,
            'fulfilmentId', evidence.fulfilment_id,
            'packageId', evidence.package_id,
            'type', evidence.evidence_type,
            'objectPath', evidence.object_path,
            'contentType', evidence.content_type,
            'capturedBy', evidence.captured_by,
            'capturedAt', evidence.captured_at
          )
        ) order by evidence.captured_at, evidence.id)
        from dastak_v1.fulfilment_evidence evidence
        where evidence.order_id = p_order_id
      ), '[]'::jsonb),
      'problems', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', problem.id,
          'fulfilmentId', problem.fulfilment_id,
          'statusAtReport', problem.fulfilment_status_at_report,
          'reason', problem.reason,
          'reportedBy', problem.reported_by,
          'reportedAt', problem.reported_at
        ) order by problem.reported_at, problem.id)
        from dastak_v1.fulfilment_problem_reports problem
        where problem.order_id = p_order_id
      ), '[]'::jsonb),
      'history', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'eventType', event.event_type,
          'aggregateType', event.aggregate_type,
          'aggregateId', event.aggregate_id,
          'aggregateVersion', event.aggregate_version,
          'payload', event.payload,
          'occurredAt', event.occurred_at
        ) order by event.occurred_at, event.id)
        from dastak_v1.domain_events_outbox event
        where (
          event.aggregate_type = 'ORDER' and event.aggregate_id = p_order_id
        ) or (
          event.payload ->> 'orderId' = p_order_id::text
          and event.event_type in (
            'PREPARATION_STARTED',
            'FULFILMENT_PACKAGES_DECLARED',
            'MERCHANT_READY_EVIDENCE_CAPTURED',
            'FULFILMENT_READY',
            'FULFILMENT_EXCEPTION_REPORTED'
          )
        )
      ), '[]'::jsonb)
    )
  );
end;
$$;

create function public.dastak_v1_merchant_fulfilments(p_limit integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.list_merchant_fulfilments(auth.uid(), p_limit);
$$;

create function public.dastak_v1_declare_fulfilment_packages(
  p_fulfilment_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_package_count integer
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.declare_fulfilment_packages(
    auth.uid(), p_fulfilment_id, p_idempotency_key,
    p_expected_version, p_package_count
  );
$$;

create function public.dastak_v1_add_fulfilment_ready_evidence(
  p_fulfilment_id uuid,
  p_package_id uuid,
  p_object_path text,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.add_fulfilment_ready_evidence(
    auth.uid(), p_fulfilment_id, p_package_id, p_object_path,
    p_idempotency_key, p_expected_version
  );
$$;

create function public.dastak_v1_mark_fulfilment_ready(
  p_fulfilment_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.mark_fulfilment_ready(
    auth.uid(), p_fulfilment_id, p_idempotency_key, p_expected_version
  );
$$;

create function public.dastak_v1_report_fulfilment_problem(
  p_fulfilment_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.report_fulfilment_problem(
    auth.uid(), p_fulfilment_id, p_reason,
    p_idempotency_key, p_expected_version
  );
$$;

revoke all on function dastak_v1.reject_step3_history_mutation() from public;
revoke all on function dastak_v1.guard_package() from public;
revoke all on function dastak_v1.start_preparation_after_payment_event() from public;
revoke all on function dastak_v1.fulfilment_rider_match_eligible_at(
  dastak_v1.fulfilment_status, timestamptz, timestamptz
) from public;
revoke all on function dastak_v1_api.order_rider_match_eligibility(uuid, timestamptz)
  from public;
revoke all on function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.list_merchant_fulfilments(uuid, integer)
  from public;
revoke all on function dastak_v1_api.declare_fulfilment_packages(
  uuid, uuid, text, bigint, integer
) from public;
revoke all on function dastak_v1_api.add_fulfilment_ready_evidence(
  uuid, uuid, uuid, text, text, bigint
) from public;
revoke all on function dastak_v1_api.mark_fulfilment_ready(
  uuid, uuid, text, bigint
) from public;
revoke all on function dastak_v1_api.report_fulfilment_problem(
  uuid, uuid, text, text, bigint
) from public;
revoke all on function dastak_v1_api.record_preparing_payment_duplicate(
  text, text, text, text, bigint, timestamptz, text
) from public;
revoke all on function dastak_v1_api.order_json_step2(uuid, uuid) from public;
revoke all on function dastak_v1_api.merchant_opportunity_json_step2(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.admin_execution_trace_step2(uuid, uuid)
  from public;
revoke all on function public.dastak_v1_merchant_fulfilments(integer)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_declare_fulfilment_packages(
  uuid, text, bigint, integer
) from public, anon, authenticated;
revoke all on function public.dastak_v1_add_fulfilment_ready_evidence(
  uuid, uuid, text, text, bigint
) from public, anon, authenticated;
revoke all on function public.dastak_v1_mark_fulfilment_ready(uuid, text, bigint)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_report_fulfilment_problem(
  uuid, text, text, bigint
) from public, anon, authenticated;

grant execute on function dastak_v1.fulfilment_rider_match_eligible_at(
  dastak_v1.fulfilment_status, timestamptz, timestamptz
) to service_role;
grant execute on function dastak_v1_api.order_rider_match_eligibility(uuid, timestamptz)
  to service_role;
grant execute on function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.list_merchant_fulfilments(uuid, integer)
  to authenticated, service_role;
grant execute on function dastak_v1_api.declare_fulfilment_packages(
  uuid, uuid, text, bigint, integer
) to service_role;
grant execute on function dastak_v1_api.add_fulfilment_ready_evidence(
  uuid, uuid, uuid, text, text, bigint
) to service_role;
grant execute on function dastak_v1_api.mark_fulfilment_ready(
  uuid, uuid, text, bigint
) to service_role;
grant execute on function dastak_v1_api.report_fulfilment_problem(
  uuid, uuid, text, text, bigint
) to service_role;
grant execute on function dastak_v1_api.record_preparing_payment_duplicate(
  text, text, text, text, bigint, timestamptz, text
) to service_role;
grant execute on function dastak_v1_api.order_json_step2(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.merchant_opportunity_json_step2(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.admin_execution_trace_step2(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.declare_fulfilment_packages(
  uuid, uuid, text, bigint, integer
) to authenticated;
grant execute on function dastak_v1_api.add_fulfilment_ready_evidence(
  uuid, uuid, uuid, text, text, bigint
) to authenticated;
grant execute on function dastak_v1_api.mark_fulfilment_ready(
  uuid, uuid, text, bigint
) to authenticated;
grant execute on function dastak_v1_api.report_fulfilment_problem(
  uuid, uuid, text, text, bigint
) to authenticated;
grant execute on function dastak_v1_api.order_json(uuid, uuid)
  to authenticated, service_role;
grant execute on function dastak_v1_api.merchant_opportunity_json(uuid, uuid)
  to authenticated, service_role;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.dastak_v1_merchant_fulfilments(integer)
  to authenticated;
grant execute on function public.dastak_v1_declare_fulfilment_packages(
  uuid, text, bigint, integer
) to authenticated;
grant execute on function public.dastak_v1_add_fulfilment_ready_evidence(
  uuid, uuid, text, text, bigint
) to authenticated;
grant execute on function public.dastak_v1_mark_fulfilment_ready(uuid, text, bigint)
  to authenticated;
grant execute on function public.dastak_v1_report_fulfilment_problem(
  uuid, text, text, bigint
) to authenticated;

comment on function public.dastak_v1_mark_fulfilment_ready(uuid, text, bigint) is
  'Atomically validates paid preparation, packages, immutable evidence, RBAC and version before irreversible Ready.';
