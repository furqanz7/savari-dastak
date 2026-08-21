-- Dastak V1 Wave 1 retail matching. This migration stays inside the additive
-- V1 domain; legacy commerce remains read-only history.

create type dastak_v1.matching_wave as enum ('WAVE_1', 'WAVE_2');
create type dastak_v1.matching_attempt_status as enum (
  'OPEN', 'WON', 'EXPIRED', 'CANCELLED'
);
create type dastak_v1.merchant_opportunity_status as enum (
  'OFFERED', 'SELECTED', 'DECLINED', 'EXPIRED', 'LOST', 'INVALIDATED'
);
create type dastak_v1.fulfilment_type as enum ('RETAIL', 'FOOD', 'RECOVERY');
create type dastak_v1.fulfilment_status as enum (
  'RESERVED_PREPAYMENT', 'PREPARING', 'READY', 'PICKED_UP', 'COMPLETED', 'RELEASED'
);
create type dastak_v1.inventory_hold_status as enum ('HELD', 'RELEASED');
create type dastak_v1.capacity_slot_status as enum ('HELD', 'RELEASED');

-- A branch has to opt into receiving work. Missing state is fail-closed.
create table dastak_v1.branch_operational_states (
  branch_id uuid primary key references dastak_v1.merchant_branches(id),
  is_open boolean not null default false,
  accepting_orders boolean not null default false,
  updated_by uuid not null references public.accounts(id),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create index branch_operational_states_updated_by_idx
  on dastak_v1.branch_operational_states (updated_by);

create table dastak_v1.matching_attempts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  wave dastak_v1.matching_wave not null,
  status dastak_v1.matching_attempt_status not null default 'OPEN',
  started_at timestamptz not null,
  expires_at timestamptz,
  winner_opportunity_id uuid,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (order_id, wave),
  check (
    (wave = 'WAVE_1' and expires_at is not null and expires_at > started_at)
    or wave = 'WAVE_2'
  ),
  check (
    (status = 'OPEN' and closed_at is null and winner_opportunity_id is null)
    or (status = 'WON' and closed_at is not null and winner_opportunity_id is not null)
    or (status in ('EXPIRED', 'CANCELLED') and closed_at is not null and winner_opportunity_id is null)
  )
);

create index matching_attempts_status_deadline_idx
  on dastak_v1.matching_attempts (status, expires_at, id);

create table dastak_v1.matching_candidate_evaluations (
  matching_attempt_id uuid not null references dastak_v1.matching_attempts(id),
  order_id uuid not null references dastak_v1.orders(id),
  organization_id uuid not null references dastak_v1.merchant_organizations(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  eligible boolean not null,
  exclusion_reasons text[] not null default '{}'::text[],
  eligibility_snapshot jsonb not null check (jsonb_typeof(eligibility_snapshot) = 'object'),
  evaluated_at timestamptz not null default now(),
  primary key (matching_attempt_id, branch_id),
  check (
    (eligible and cardinality(exclusion_reasons) = 0)
    or (not eligible and cardinality(exclusion_reasons) > 0)
  )
);

create index matching_candidate_evaluations_order_idx
  on dastak_v1.matching_candidate_evaluations (order_id, eligible);
create index matching_candidate_evaluations_organization_idx
  on dastak_v1.matching_candidate_evaluations (organization_id);
create index matching_candidate_evaluations_branch_idx
  on dastak_v1.matching_candidate_evaluations (branch_id);

create table dastak_v1.merchant_opportunities (
  id uuid primary key default gen_random_uuid(),
  matching_attempt_id uuid not null references dastak_v1.matching_attempts(id),
  order_id uuid not null references dastak_v1.orders(id),
  organization_id uuid not null references dastak_v1.merchant_organizations(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  status dastak_v1.merchant_opportunity_status not null default 'OFFERED',
  started_at timestamptz not null,
  expires_at timestamptz not null check (expires_at > started_at),
  promised_prep_minutes integer check (promised_prep_minutes > 0),
  responded_by uuid references public.accounts(id),
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (matching_attempt_id, branch_id),
  check (
    (status = 'OFFERED' and responded_by is null and responded_at is null and promised_prep_minutes is null)
    or (status = 'SELECTED' and responded_by is not null and responded_at is not null and promised_prep_minutes is not null)
    or (status = 'DECLINED' and responded_by is not null and responded_at is not null and promised_prep_minutes is null)
    or (status in ('EXPIRED', 'LOST', 'INVALIDATED') and promised_prep_minutes is null)
  )
);

create index merchant_opportunities_order_idx
  on dastak_v1.merchant_opportunities (order_id, status);
create index merchant_opportunities_organization_idx
  on dastak_v1.merchant_opportunities (organization_id, status);
create index merchant_opportunities_branch_idx
  on dastak_v1.merchant_opportunities (branch_id, status, expires_at);
create index merchant_opportunities_responded_by_idx
  on dastak_v1.merchant_opportunities (responded_by);
create unique index merchant_opportunities_selected_attempt_uidx
  on dastak_v1.merchant_opportunities (matching_attempt_id)
  where status = 'SELECTED';

alter table dastak_v1.matching_attempts
  add constraint matching_attempts_winner_opportunity_fk
  foreign key (winner_opportunity_id)
  references dastak_v1.merchant_opportunities(id);

create index matching_attempts_winner_opportunity_idx
  on dastak_v1.matching_attempts (winner_opportunity_id);

create table dastak_v1.merchant_opportunity_lines (
  opportunity_id uuid not null references dastak_v1.merchant_opportunities(id),
  order_line_id uuid not null references dastak_v1.order_lines(id),
  sku_id uuid not null references dastak_v1.skus(id),
  product_name_snapshot text not null,
  variant_snapshot text,
  pack_size_snapshot text,
  requested_quantity integer not null check (requested_quantity > 0),
  created_at timestamptz not null default now(),
  primary key (opportunity_id, order_line_id)
);

create index merchant_opportunity_lines_order_line_idx
  on dastak_v1.merchant_opportunity_lines (order_line_id);
create index merchant_opportunity_lines_sku_idx
  on dastak_v1.merchant_opportunity_lines (sku_id);

create table dastak_v1.fulfilments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  organization_id uuid not null references dastak_v1.merchant_organizations(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  source_opportunity_id uuid not null unique references dastak_v1.merchant_opportunities(id),
  fulfilment_type dastak_v1.fulfilment_type not null,
  status dastak_v1.fulfilment_status not null,
  promised_prep_minutes integer not null check (promised_prep_minutes > 0),
  committed_at timestamptz not null,
  prep_started_at timestamptz,
  ready_at timestamptz,
  released_at timestamptz,
  release_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  check (
    (status = 'RELEASED' and released_at is not null and release_reason is not null)
    or (status <> 'RELEASED' and released_at is null and release_reason is null)
  ),
  check (prep_started_at is null or prep_started_at >= committed_at),
  check (ready_at is null or prep_started_at is not null)
);

create index fulfilments_order_idx
  on dastak_v1.fulfilments (order_id, status);
create index fulfilments_organization_idx
  on dastak_v1.fulfilments (organization_id, status);
create index fulfilments_branch_idx
  on dastak_v1.fulfilments (branch_id, status);

create table dastak_v1.fulfilment_lines (
  fulfilment_id uuid not null references dastak_v1.fulfilments(id),
  order_line_id uuid not null references dastak_v1.order_lines(id),
  confirmed_quantity integer not null check (confirmed_quantity > 0),
  created_at timestamptz not null default now(),
  primary key (fulfilment_id, order_line_id)
);

create index fulfilment_lines_order_line_idx
  on dastak_v1.fulfilment_lines (order_line_id);

-- These rows record exact units physically confirmed at merchant acceptance.
-- They are reservations, not a continuous merchant inventory counter.
create table dastak_v1.inventory_holds (
  id uuid primary key default gen_random_uuid(),
  fulfilment_id uuid not null references dastak_v1.fulfilments(id),
  order_line_id uuid not null references dastak_v1.order_lines(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  held_quantity integer not null check (held_quantity > 0),
  status dastak_v1.inventory_hold_status not null default 'HELD',
  held_at timestamptz not null,
  released_at timestamptz,
  release_reason text,
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (fulfilment_id, order_line_id),
  check (
    (status = 'HELD' and released_at is null and release_reason is null)
    or (status = 'RELEASED' and released_at is not null and release_reason is not null)
  )
);

create index inventory_holds_fulfilment_idx
  on dastak_v1.inventory_holds (fulfilment_id, status);
create index inventory_holds_order_line_idx
  on dastak_v1.inventory_holds (order_line_id, status);
create index inventory_holds_branch_idx
  on dastak_v1.inventory_holds (branch_id, status);
create unique index inventory_holds_active_line_uidx
  on dastak_v1.inventory_holds (order_line_id)
  where status = 'HELD';

create table dastak_v1.retail_capacity_slots (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  fulfilment_id uuid not null unique references dastak_v1.fulfilments(id),
  status dastak_v1.capacity_slot_status not null default 'HELD',
  held_at timestamptz not null,
  released_at timestamptz,
  release_reason text,
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  check (
    (status = 'HELD' and released_at is null and release_reason is null)
    or (status = 'RELEASED' and released_at is not null and release_reason is not null)
  )
);

create index retail_capacity_slots_branch_idx
  on dastak_v1.retail_capacity_slots (branch_id, status);

insert into dastak_v1.setting_definitions (
  setting_key,
  value_type,
  description,
  default_value,
  validation_rules,
  protected,
  requires_explicit_value
) values
  (
    'matching.retail_radius_meters',
    'INTEGER',
    'Maximum branch-to-customer reach for retail matching.',
    null,
    '{"minimum":1}'::jsonb,
    true,
    true
  ),
  (
    'retail.prep_time_options_minutes',
    'JSON',
    'Allowed promised preparation-time choices for retail branches.',
    null,
    '{}'::jsonb,
    true,
    true
  );

create function dastak_v1_api.effective_setting_json(
  p_setting_key text,
  p_branch_id uuid default null,
  p_organization_id uuid default null,
  p_service_zone_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select setting.setting_value
      from dastak_v1.platform_settings setting
      where setting.setting_key = p_setting_key
        and (
          setting.scope_type = 'GLOBAL'
          or (setting.scope_type = 'SERVICE_ZONE' and setting.scope_id = p_service_zone_id)
          or (
            setting.scope_type = 'MERCHANT_ORGANIZATION'
            and setting.scope_id = p_organization_id
          )
          or (setting.scope_type = 'MERCHANT_BRANCH' and setting.scope_id = p_branch_id)
        )
      order by case setting.scope_type
        when 'MERCHANT_BRANCH' then 4
        when 'MERCHANT_ORGANIZATION' then 3
        when 'SERVICE_ZONE' then 2
        else 1
      end desc
      limit 1
    ),
    (
      select definition.default_value
      from dastak_v1.setting_definitions definition
      where definition.setting_key = p_setting_key
    )
  );
$$;

create function dastak_v1.is_valid_positive_integer_options(p_options jsonb)
returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_option jsonb;
begin
  if pg_catalog.jsonb_typeof(p_options) <> 'array'
    or pg_catalog.jsonb_array_length(p_options) = 0 then
    return false;
  end if;

  for v_option in
    select value from pg_catalog.jsonb_array_elements(p_options)
  loop
    if pg_catalog.jsonb_typeof(v_option) <> 'number'
      or v_option #>> '{}' !~ '^[1-9][0-9]*$'
      or (v_option #>> '{}')::numeric > 2147483647 then
      return false;
    end if;
  end loop;

  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

-- Wave 1 merchant operations never inherit legacy platform-owner access.
-- Platform intervention must use a separate, named and audited command.
create function dastak_v1_api.actor_has_wave1_merchant_permission(
  p_actor_id uuid,
  p_organization_id uuid,
  p_permission_key text,
  p_branch_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor_id is not null
    and exists (
      select 1
      from dastak_v1.merchant_users merchant_user
      join dastak_v1.merchant_organizations organization
        on organization.id = merchant_user.organization_id
        and organization.status = 'ACTIVE'
      join dastak_v1.merchant_permission_grants permission_grant
        on permission_grant.merchant_user_id = merchant_user.id
        and permission_grant.organization_id = merchant_user.organization_id
      join dastak_v1.permission_bundles bundle
        on bundle.id = permission_grant.bundle_id
        and bundle.scope = 'MERCHANT'
        and bundle.active
      join dastak_v1.permission_bundle_permissions bundle_permission
        on bundle_permission.bundle_id = permission_grant.bundle_id
      where merchant_user.account_id = p_actor_id
        and merchant_user.organization_id = p_organization_id
        and merchant_user.status = 'ACTIVE'
        and permission_grant.revoked_at is null
        and bundle_permission.permission_key = p_permission_key
        and (
          permission_grant.branch_id is null
          or permission_grant.branch_id = p_branch_id
        )
        and (
          p_branch_id is null
          or exists (
            select 1
            from dastak_v1.merchant_branches branch
            where branch.id = p_branch_id
              and branch.organization_id = p_organization_id
          )
        )
    );
$$;

create function dastak_v1_api.wave1_branch_configuration(
  p_branch_id uuid,
  p_organization_id uuid,
  p_service_zone_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_radius jsonb;
  v_prep_options jsonb;
  v_radius_meters integer;
begin
  v_radius := dastak_v1_api.effective_setting_json(
    'matching.retail_radius_meters',
    p_branch_id,
    p_organization_id,
    p_service_zone_id
  );
  v_prep_options := dastak_v1_api.effective_setting_json(
    'retail.prep_time_options_minutes',
    p_branch_id,
    p_organization_id,
    p_service_zone_id
  );

  if not dastak_v1.validate_setting_value(
    'matching.retail_radius_meters',
    v_radius
  ) or (v_radius #>> '{}')::numeric > 2147483647 then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = pg_catalog.format(
        'Required Wave 1 setting matching.retail_radius_meters is missing or invalid for branch %s.',
        p_branch_id
      ),
      hint = 'Configure valid Wave 1 reachability before opening matching.';
  end if;

  if not dastak_v1.is_valid_positive_integer_options(v_prep_options) then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = pg_catalog.format(
        'Required Wave 1 setting retail.prep_time_options_minutes is missing or invalid for branch %s.',
        p_branch_id
      ),
      hint = 'Configure valid Wave 1 preparation options before opening matching.';
  end if;

  v_radius_meters := (v_radius #>> '{}')::integer;

  return pg_catalog.jsonb_build_object(
    'retailRadiusMeters', v_radius_meters,
    'prepTimeOptionsMinutes', v_prep_options
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = pg_catalog.format(
        'Required Wave 1 reachability or preparation configuration is invalid for branch %s.',
        p_branch_id
      ),
      hint = 'Configure valid Wave 1 reachability and preparation settings before opening matching.';
end;
$$;

create function dastak_v1.guard_branch_operational_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.branch_id is distinct from old.branch_id then
      raise exception 'branch operational-state identity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'branch operational-state version must increment exactly once';
    end if;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_matching_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.wave is distinct from old.wave
    or new.started_at is distinct from old.started_at
    or new.expires_at is distinct from old.expires_at
    or new.created_at is distinct from old.created_at then
    raise exception 'matching-attempt identity and authoritative window cannot change';
  end if;

  if new.version <> old.version + 1 then
    raise exception 'matching-attempt version must increment exactly once';
  end if;

  if new.status is distinct from old.status
    and not (
      old.status = 'OPEN'
      and new.status in ('WON', 'EXPIRED', 'CANCELLED')
    ) then
    raise exception 'invalid matching-attempt transition: % -> %', old.status, new.status;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_merchant_opportunity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.matching_attempt_id is distinct from old.matching_attempt_id
    or new.order_id is distinct from old.order_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.started_at is distinct from old.started_at
    or new.expires_at is distinct from old.expires_at
    or new.created_at is distinct from old.created_at then
    raise exception 'merchant-opportunity identity and authoritative window cannot change';
  end if;

  if new.version <> old.version + 1 then
    raise exception 'merchant-opportunity version must increment exactly once';
  end if;

  if new.status is distinct from old.status
    and not (
      old.status = 'OFFERED'
      and new.status in ('SELECTED', 'DECLINED', 'EXPIRED', 'LOST', 'INVALIDATED')
    ) then
    raise exception 'invalid merchant-opportunity transition: % -> %', old.status, new.status;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_fulfilment()
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

  if new.status is distinct from old.status
    and not (
      (old.status = 'RESERVED_PREPAYMENT' and new.status in ('PREPARING', 'RELEASED'))
      or (old.status = 'PREPARING' and new.status = 'READY')
      or (old.status = 'READY' and new.status = 'PICKED_UP')
      or (old.status = 'PICKED_UP' and new.status = 'COMPLETED')
    ) then
    raise exception 'invalid fulfilment transition: % -> %', old.status, new.status;
  end if;

  if new.status = 'PREPARING' and new.prep_started_at is null then
    raise exception 'PREPARING fulfilment requires prep_started_at';
  end if;
  if new.status = 'READY' and new.ready_at is null then
    raise exception 'READY fulfilment requires ready_at';
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_inventory_hold()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.order_line_id is distinct from old.order_line_id
    or new.branch_id is distinct from old.branch_id
    or new.held_quantity is distinct from old.held_quantity
    or new.held_at is distinct from old.held_at then
    raise exception 'physical inventory-hold identity and quantity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'inventory-hold version must increment exactly once';
  end if;
  if new.status is distinct from old.status
    and not (old.status = 'HELD' and new.status = 'RELEASED') then
    raise exception 'invalid inventory-hold transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_retail_capacity_slot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.branch_id is distinct from old.branch_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.held_at is distinct from old.held_at then
    raise exception 'retail capacity-slot identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'retail capacity-slot version must increment exactly once';
  end if;
  if new.status is distinct from old.status
    and not (old.status = 'HELD' and new.status = 'RELEASED') then
    raise exception 'invalid retail capacity-slot transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger branch_operational_states_guard
before update on dastak_v1.branch_operational_states
for each row execute function dastak_v1.guard_branch_operational_state();
create trigger branch_operational_states_no_delete
before delete on dastak_v1.branch_operational_states
for each row execute function dastak_v1.reject_delete();

create trigger matching_attempts_guard
before update on dastak_v1.matching_attempts
for each row execute function dastak_v1.guard_matching_attempt();
create trigger matching_attempts_no_delete
before delete on dastak_v1.matching_attempts
for each row execute function dastak_v1.reject_delete();

create trigger matching_candidate_evaluations_immutable
before update or delete on dastak_v1.matching_candidate_evaluations
for each row execute function dastak_v1.reject_mutation();

create trigger merchant_opportunities_guard
before update on dastak_v1.merchant_opportunities
for each row execute function dastak_v1.guard_merchant_opportunity();
create trigger merchant_opportunities_no_delete
before delete on dastak_v1.merchant_opportunities
for each row execute function dastak_v1.reject_delete();

create trigger merchant_opportunity_lines_immutable
before update or delete on dastak_v1.merchant_opportunity_lines
for each row execute function dastak_v1.reject_mutation();

create trigger fulfilments_guard
before update on dastak_v1.fulfilments
for each row execute function dastak_v1.guard_fulfilment();
create trigger fulfilments_no_delete
before delete on dastak_v1.fulfilments
for each row execute function dastak_v1.reject_delete();

create trigger fulfilment_lines_immutable
before update or delete on dastak_v1.fulfilment_lines
for each row execute function dastak_v1.reject_mutation();

create trigger inventory_holds_guard
before update on dastak_v1.inventory_holds
for each row execute function dastak_v1.guard_inventory_hold();
create trigger inventory_holds_no_delete
before delete on dastak_v1.inventory_holds
for each row execute function dastak_v1.reject_delete();

create trigger retail_capacity_slots_guard
before update on dastak_v1.retail_capacity_slots
for each row execute function dastak_v1.guard_retail_capacity_slot();
create trigger retail_capacity_slots_no_delete
before delete on dastak_v1.retail_capacity_slots
for each row execute function dastak_v1.reject_delete();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'branch_operational_states',
    'matching_attempts',
    'matching_candidate_evaluations',
    'merchant_opportunities',
    'merchant_opportunity_lines',
    'fulfilments',
    'fulfilment_lines',
    'inventory_holds',
    'retail_capacity_slots'
  ] loop
    execute pg_catalog.format(
      'alter table dastak_v1.%I enable row level security',
      v_table
    );
  end loop;
end;
$$;

revoke all on all tables in schema dastak_v1
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema dastak_v1
  from public, anon, authenticated, service_role;
grant select on all tables in schema dastak_v1 to service_role;

create function dastak_v1_api.evaluate_wave1_candidate(
  p_order_id uuid,
  p_branch_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_operating dastak_v1.branch_operational_states%rowtype;
  v_zone public.service_zones%rowtype;
  v_address jsonb;
  v_customer_location extensions.geometry(Point, 4326);
  v_radius_meters integer;
  v_prep_options jsonb;
  v_configuration jsonb;
  v_distance_meters numeric;
  v_retail_line_count integer;
  v_selected_line_count integer;
  v_held_capacity integer;
  v_reasons text[] := '{}'::text[];
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;

  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id;

  if not found or v_order.id is null then
    raise exception using errcode = 'P0002', message = 'order or branch not found';
  end if;

  select organization.* into v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;

  select state.* into v_operating
  from dastak_v1.branch_operational_states state
  where state.branch_id = v_branch.id;

  if v_branch.service_zone_id is not null then
    select zone.* into v_zone
    from public.service_zones zone
    where zone.id = v_branch.service_zone_id;
  end if;

  select context_snapshot.delivery_address into v_address
  from dastak_v1.order_context_snapshots context_snapshot
  where context_snapshot.order_id = v_order.id;

  if pg_catalog.jsonb_typeof(v_address -> 'latitude') = 'number'
    and pg_catalog.jsonb_typeof(v_address -> 'longitude') = 'number' then
    v_customer_location := extensions.st_setsrid(
      extensions.st_makepoint(
        (v_address ->> 'longitude')::double precision,
        (v_address ->> 'latitude')::double precision
      ),
      4326
    );
  end if;

  select count(*) into v_retail_line_count
  from dastak_v1.order_lines order_line
  where order_line.order_id = v_order.id
    and order_line.line_type = 'RETAIL_SKU';

  select count(*) into v_selected_line_count
  from dastak_v1.order_lines order_line
  where order_line.order_id = v_order.id
    and order_line.line_type = 'RETAIL_SKU'
    and exists (
      select 1
      from dastak_v1.merchant_sku_selections selection
      where selection.branch_id = v_branch.id
        and selection.sku_id = order_line.sku_id
        and selection.state = 'SELECTED'
    );

  select count(*) into v_held_capacity
  from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = v_branch.id
    and slot.status = 'HELD';

  if v_organization.status is distinct from 'ACTIVE' then
    v_reasons := pg_catalog.array_append(v_reasons, 'ORGANIZATION_NOT_ACTIVE');
  end if;
  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    v_reasons := pg_catalog.array_append(v_reasons, 'NOT_RETAIL');
  end if;
  if v_branch.status is distinct from 'ACTIVE' then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_NOT_ACTIVE');
  end if;
  if v_operating.branch_id is null or not v_operating.is_open then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_CLOSED');
  end if;
  if v_operating.branch_id is null or not v_operating.accepting_orders then
    v_reasons := pg_catalog.array_append(v_reasons, 'NOT_ACCEPTING_ORDERS');
  end if;
  if v_branch.service_zone_id is null or v_zone.id is null or not v_zone.active then
    v_reasons := pg_catalog.array_append(v_reasons, 'SERVICE_ZONE_UNAVAILABLE');
  end if;
  if v_customer_location is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'CUSTOMER_LOCATION_MISSING');
  end if;
  if v_branch.location is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_LOCATION_MISSING');
  end if;
  if v_organization.status = 'ACTIVE'
    and v_organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
    and v_branch.status = 'ACTIVE'
    and v_operating.branch_id is not null
    and v_operating.is_open
    and v_operating.accepting_orders
    and v_zone.id is not null
    and v_zone.active then
    v_configuration := dastak_v1_api.wave1_branch_configuration(
      v_branch.id,
      v_branch.organization_id,
      v_branch.service_zone_id
    );
    v_radius_meters := (v_configuration ->> 'retailRadiusMeters')::integer;
    v_prep_options := v_configuration -> 'prepTimeOptionsMinutes';
  end if;

  if v_zone.id is not null and v_zone.active and v_customer_location is not null
    and not extensions.st_covers(v_zone.boundary, v_customer_location) then
    v_reasons := pg_catalog.array_append(v_reasons, 'CUSTOMER_OUTSIDE_SERVICE_ZONE');
  end if;
  if v_zone.id is not null and v_zone.active and v_branch.location is not null
    and not extensions.st_covers(v_zone.boundary, v_branch.location) then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_OUTSIDE_SERVICE_ZONE');
  end if;

  if v_customer_location is not null and v_branch.location is not null then
    v_distance_meters := extensions.st_distance(
      v_branch.location::extensions.geography,
      v_customer_location::extensions.geography
    );
    if v_radius_meters is not null and v_distance_meters > v_radius_meters then
      v_reasons := pg_catalog.array_append(v_reasons, 'OUTSIDE_RETAIL_RADIUS');
    end if;
  end if;

  if v_held_capacity >= v_branch.capacity_limit then
    v_reasons := pg_catalog.array_append(v_reasons, 'AT_CAPACITY');
  end if;
  if v_retail_line_count = 0 then
    v_reasons := pg_catalog.array_append(v_reasons, 'EMPTY_RETAIL_BASKET');
  elsif v_selected_line_count <> v_retail_line_count then
    v_reasons := pg_catalog.array_append(v_reasons, 'INCOMPLETE_CATALOGUE_COVERAGE');
  end if;

  return pg_catalog.jsonb_build_object(
    'eligible', pg_catalog.cardinality(v_reasons) = 0,
    'exclusionReasons', pg_catalog.to_jsonb(v_reasons),
    'retailLineCount', v_retail_line_count,
    'selectedLineCount', v_selected_line_count,
    'heldCapacity', v_held_capacity,
    'capacityLimit', v_branch.capacity_limit,
    'retailRadiusMeters', v_radius_meters,
    'prepTimeOptionsMinutes', v_prep_options,
    'distanceMeters', case
      when v_distance_meters is null then null
      else pg_catalog.round(v_distance_meters)
    end,
    'serviceZoneId', v_branch.service_zone_id,
    'evaluatedAt', pg_catalog.clock_timestamp()
  );
end;
$$;

create function dastak_v1_api.start_wave1(
  p_order_id uuid,
  p_actor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_attempt_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_timeout_seconds integer;
  v_expires_at timestamptz;
  v_candidate_count integer;
  v_opportunity_count integer;
begin
  -- All Wave 1, expiry and cancellation commands lock the parent order first.
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  select attempt.id into v_attempt_id
  from dastak_v1.matching_attempts attempt
  where attempt.order_id = v_order.id
    and attempt.wave = 'WAVE_1';

  if v_attempt_id is not null then
    return v_attempt_id;
  end if;

  if v_order.status <> 'MATCHING'
    or v_order.order_type not in ('RETAIL_ONLY', 'MIXED') then
    raise exception using errcode = '55000', message = 'order is not eligible to start retail matching';
  end if;

  v_timeout_seconds := (
    dastak_v1_api.effective_setting_json('matching.wave1_timeout_seconds') #>> '{}'
  )::integer;
  if v_timeout_seconds is distinct from 180 then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Protected Wave 1 timeout must be exactly 180 seconds.',
      hint = 'Restore matching.wave1_timeout_seconds to the locked V1 baseline.';
  end if;
  v_expires_at := v_now + pg_catalog.make_interval(secs => v_timeout_seconds);

  -- Required operational configuration is validated before an attempt opens.
  -- Missing configuration is a system failure, never candidate ineligibility.
  perform dastak_v1_api.wave1_branch_configuration(
    branch.id,
    branch.organization_id,
    branch.service_zone_id
  )
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
  join dastak_v1.branch_operational_states operating
    on operating.branch_id = branch.id
  join public.service_zones zone
    on zone.id = branch.service_zone_id
  where organization.status = 'ACTIVE'
    and organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
    and branch.status = 'ACTIVE'
    and operating.is_open
    and operating.accepting_orders
    and zone.active
  order by branch.id;

  insert into dastak_v1.matching_attempts (
    order_id,
    wave,
    status,
    started_at,
    expires_at
  ) values (
    v_order.id,
    'WAVE_1',
    'OPEN',
    v_now,
    v_expires_at
  )
  returning id into v_attempt_id;

  insert into dastak_v1.matching_candidate_evaluations (
    matching_attempt_id,
    order_id,
    organization_id,
    branch_id,
    eligible,
    exclusion_reasons,
    eligibility_snapshot,
    evaluated_at
  )
  select
    v_attempt_id,
    v_order.id,
    branch.organization_id,
    branch.id,
    (evaluation.snapshot ->> 'eligible')::boolean,
    array(
      select pg_catalog.jsonb_array_elements_text(
        evaluation.snapshot -> 'exclusionReasons'
      )
    ),
    evaluation.snapshot,
    v_now
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
  cross join lateral (
    select dastak_v1_api.evaluate_wave1_candidate(
      v_order.id,
      branch.id
    ) as snapshot
  ) evaluation
  where organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
  order by branch.id;

  get diagnostics v_candidate_count = row_count;

  insert into dastak_v1.merchant_opportunities (
    matching_attempt_id,
    order_id,
    organization_id,
    branch_id,
    status,
    started_at,
    expires_at
  )
  select
    evaluation.matching_attempt_id,
    evaluation.order_id,
    evaluation.organization_id,
    evaluation.branch_id,
    'OFFERED',
    v_now,
    v_expires_at
  from dastak_v1.matching_candidate_evaluations evaluation
  where evaluation.matching_attempt_id = v_attempt_id
    and evaluation.eligible
  order by evaluation.branch_id;

  get diagnostics v_opportunity_count = row_count;

  insert into dastak_v1.merchant_opportunity_lines (
    opportunity_id,
    order_line_id,
    sku_id,
    product_name_snapshot,
    variant_snapshot,
    pack_size_snapshot,
    requested_quantity
  )
  select
    opportunity.id,
    order_line.id,
    order_line.sku_id,
    order_line.product_name_snapshot,
    order_line.variant_snapshot,
    order_line.pack_size_snapshot,
    order_line.quantity
  from dastak_v1.merchant_opportunities opportunity
  join dastak_v1.order_lines order_line
    on order_line.order_id = opportunity.order_id
    and order_line.line_type = 'RETAIL_SKU'
  where opportunity.matching_attempt_id = v_attempt_id
  order by opportunity.id, order_line.created_at, order_line.id;

  -- Business state and notification intent are committed together. Delivery
  -- workers publish these PENDING events asynchronously after commit.
  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_attempt_id::text || ':WAVE_1_STARTED:1',
    'MATCHING_ATTEMPT',
    v_attempt_id,
    1,
    'WAVE_1_STARTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt_id,
      'orderId', v_order.id,
      'startedAt', v_now,
      'expiresAt', v_expires_at,
      'eligibleOpportunityCount', v_opportunity_count
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  )
  select
    opportunity.id::text || ':MERCHANT_OPPORTUNITY_OFFERED:1',
    'MERCHANT_OPPORTUNITY',
    opportunity.id,
    1,
    'MERCHANT_OPPORTUNITY_OFFERED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'opportunityId', opportunity.id,
      'orderId', opportunity.order_id,
      'organizationId', opportunity.organization_id,
      'branchId', opportunity.branch_id,
      'expiresAt', opportunity.expires_at
    )
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.matching_attempt_id = v_attempt_id;

  insert into dastak_v1.audit_events (
    actor_id,
    action,
    resource_type,
    resource_id,
    metadata
  ) values (
    p_actor_id,
    'WAVE_1_STARTED',
    'matching_attempt',
    v_attempt_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'candidateCount', v_candidate_count,
      'opportunityCount', v_opportunity_count,
      'startedAt', v_now,
      'expiresAt', v_expires_at
    )
  );

  return v_attempt_id;
end;
$$;

create function dastak_v1.start_wave1_after_order_matching()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'MATCHING'
    and old.status is distinct from new.status
    and new.order_type in ('RETAIL_ONLY', 'MIXED') then
    perform dastak_v1_api.start_wave1(new.id, new.customer_id);
  end if;
  return new;
end;
$$;

create trigger orders_start_wave1
after update of status on dastak_v1.orders
for each row execute function dastak_v1.start_wave1_after_order_matching();

create function dastak_v1_api.assert_authenticated_actor(p_actor_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_actor_id is null or p_actor_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
end;
$$;

create function dastak_v1_api.set_branch_operational_state(
  p_actor_id uuid,
  p_branch_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_is_open boolean,
  p_accepting_orders boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'setBranchOperationalState';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_state dastak_v1.branch_operational_states%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);

  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'branchId', p_branch_id,
      'expectedVersion', p_expected_version,
      'isOpen', p_is_open,
      'acceptingOrders', p_accepting_orders
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'branch not found';
  end if;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_branch.organization_id,
    'merchant.branch.manage',
    v_branch.id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select state.* into v_state
  from dastak_v1.branch_operational_states state
  where state.branch_id = v_branch.id
  for update;

  if found then
    if v_state.version is distinct from p_expected_version then
      raise exception using errcode = '40001', message = 'stale branch operational-state version';
    end if;

    update dastak_v1.branch_operational_states
    set is_open = p_is_open,
        accepting_orders = p_accepting_orders,
        updated_by = p_actor_id,
        version = version + 1
    where branch_id = v_branch.id
    returning * into v_state;
  else
    if p_expected_version is distinct from 0 then
      raise exception using errcode = '40001', message = 'new branch operational state expectedVersion must be 0';
    end if;

    insert into dastak_v1.branch_operational_states (
      branch_id,
      is_open,
      accepting_orders,
      updated_by
    ) values (
      v_branch.id,
      p_is_open,
      p_accepting_orders,
      p_actor_id
    )
    returning * into v_state;
  end if;

  v_response := pg_catalog.jsonb_build_object(
    'branchId', v_state.branch_id,
    'isOpen', v_state.is_open,
    'acceptingOrders', v_state.accepting_orders,
    'version', v_state.version,
    'updatedAt', v_state.updated_at
  );

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_branch.id::text || ':BRANCH_OPERATIONAL_STATE_CHANGED:' || v_state.version::text,
    'MERCHANT_BRANCH',
    v_branch.id,
    v_state.version,
    'BRANCH_OPERATIONAL_STATE_CHANGED',
    p_actor_id,
    v_response
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'BRANCH_OPERATIONAL_STATE_CHANGED',
    'merchant_branch',
    v_branch.id,
    v_response || pg_catalog.jsonb_build_object('idempotencyKey', p_idempotency_key)
  );

  insert into dastak_v1.idempotency_records (
    actor_id,
    command_name,
    idempotency_key,
    request_hash,
    response_body,
    response_status,
    resource_id
  ) values (
    p_actor_id,
    v_command,
    p_idempotency_key,
    v_request_hash,
    v_response,
    200,
    v_branch.id
  );

  return v_response;
end;
$$;

create function dastak_v1_api.retail_prep_options(
  p_branch_id uuid,
  p_organization_id uuid,
  p_service_zone_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_configuration jsonb;
begin
  v_configuration := dastak_v1_api.wave1_branch_configuration(
    p_branch_id,
    p_organization_id,
    p_service_zone_id
  );
  return v_configuration -> 'prepTimeOptionsMinutes';
end;
$$;

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
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_display_order_number text;
  v_response jsonb;
begin
  select opportunity.* into v_opportunity
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'opportunity not found';
  end if;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_opportunity.organization_id,
    'merchant.opportunities.respond',
    v_opportunity.branch_id
  ) then
    raise exception using errcode = 'P0002', message = 'opportunity not found';
  end if;

  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = v_opportunity.branch_id;

  select customer_order.display_order_number into v_display_order_number
  from dastak_v1.orders customer_order
  where customer_order.id = v_opportunity.order_id;

  v_response := pg_catalog.jsonb_build_object(
    'id', v_opportunity.id,
    'displayOrderNumber', v_display_order_number,
    'status', v_opportunity.status,
    'version', v_opportunity.version,
    'branch', pg_catalog.jsonb_build_object(
      'id', v_branch.id,
      'displayName', v_branch.display_name
    ),
    'startedAt', v_opportunity.started_at,
    'expiresAt', v_opportunity.expires_at,
    'secondsRemaining', greatest(
      0,
      pg_catalog.floor(
        extract(
          epoch from (v_opportunity.expires_at - pg_catalog.clock_timestamp())
        )
      )::integer
    ),
    'promisedPrepMinutes', v_opportunity.promised_prep_minutes,
    'prepTimeOptionsMinutes', dastak_v1_api.retail_prep_options(
      v_branch.id,
      v_branch.organization_id,
      v_branch.service_zone_id
    ),
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              'orderLineId', opportunity_line.order_line_id,
              'skuId', opportunity_line.sku_id,
              'name', opportunity_line.product_name_snapshot,
              'variant', opportunity_line.variant_snapshot,
              'packSize', opportunity_line.pack_size_snapshot,
              'quantity', opportunity_line.requested_quantity
            )
          )
          order by opportunity_line.created_at, opportunity_line.order_line_id
        )
        from dastak_v1.merchant_opportunity_lines opportunity_line
        where opportunity_line.opportunity_id = v_opportunity.id
      ),
      '[]'::jsonb
    )
  );

  return v_response;
end;
$$;

create function dastak_v1_api.get_merchant_opportunity(
  p_actor_id uuid,
  p_opportunity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  return dastak_v1_api.merchant_opportunity_json(p_actor_id, p_opportunity_id);
end;
$$;

create function dastak_v1_api.list_merchant_opportunities(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);

  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'limit must be between 1 and 100';
  end if;

  select pg_catalog.jsonb_build_object(
    'opportunities', coalesce(
      pg_catalog.jsonb_agg(
        dastak_v1_api.merchant_opportunity_json(p_actor_id, visible.id)
        order by
          case visible.status when 'OFFERED' then 0 else 1 end,
          visible.expires_at,
          visible.id
      ),
      '[]'::jsonb
    )
  ) into v_response
  from (
    select opportunity.id, opportunity.status, opportunity.expires_at
    from dastak_v1.merchant_opportunities opportunity
    where dastak_v1_api.actor_has_wave1_merchant_permission(
      p_actor_id,
      opportunity.organization_id,
      'merchant.opportunities.respond',
      opportunity.branch_id
    )
    order by
      case opportunity.status when 'OFFERED' then 0 else 1 end,
      opportunity.expires_at,
      opportunity.id
    limit p_limit
  ) visible;

  return v_response;
end;
$$;

create function dastak_v1_api.accept_wave1_opportunity(
  p_actor_id uuid,
  p_opportunity_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_promised_prep_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'acceptWave1Opportunity';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_attempt_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_operating dastak_v1.branch_operational_states%rowtype;
  v_prep_options jsonb;
  v_evaluation jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_fulfilment_id uuid := gen_random_uuid();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);

  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;
  if p_promised_prep_minutes is null or p_promised_prep_minutes <= 0 then
    raise exception using errcode = '22023', message = 'promised preparation time is required';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'opportunityId', p_opportunity_id,
      'expectedVersion', p_expected_version,
      'promisedPrepMinutes', p_promised_prep_minutes
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  -- Resolve immutable identities first, then use the global lock order:
  -- parent order -> matching attempt -> opportunity -> physical branch.
  select opportunity.order_id, opportunity.matching_attempt_id
  into v_order_id, v_attempt_id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'opportunity not found';
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;

  select attempt.* into v_attempt
  from dastak_v1.matching_attempts attempt
  where attempt.id = v_attempt_id
  for update;

  select opportunity.* into v_opportunity
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id
  for update;

  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = v_opportunity.branch_id
  for update;

  select state.* into v_operating
  from dastak_v1.branch_operational_states state
  where state.branch_id = v_branch.id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_opportunity.organization_id,
    'merchant.opportunities.respond',
    v_opportunity.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  if v_opportunity.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale opportunity version';
  end if;
  if v_order.status <> 'MATCHING' or v_order.paid_at is not null then
    raise exception using errcode = '55000', message = 'order is no longer accepting merchant responses';
  end if;
  if v_attempt.wave <> 'WAVE_1' or v_attempt.status <> 'OPEN' then
    raise exception using errcode = '55000', message = 'matching opportunity is no longer open';
  end if;
  if v_opportunity.status <> 'OFFERED' then
    raise exception using errcode = '55000', message = 'matching opportunity is no longer open';
  end if;
  if v_now >= v_attempt.expires_at or v_now >= v_opportunity.expires_at then
    raise exception using errcode = '55000', message = 'matching opportunity has expired';
  end if;

  v_prep_options := dastak_v1_api.retail_prep_options(
    v_branch.id,
    v_branch.organization_id,
    v_branch.service_zone_id
  );
  if not v_prep_options @> pg_catalog.jsonb_build_array(p_promised_prep_minutes) then
    raise exception using errcode = '22023', message = 'promised preparation time is not allowed';
  end if;

  v_evaluation := dastak_v1_api.evaluate_wave1_candidate(v_order.id, v_branch.id);
  if not (v_evaluation ->> 'eligible')::boolean then
    raise exception using errcode = '55000', message = 'branch is no longer eligible for this order';
  end if;

  if exists (
    select 1
    from dastak_v1.order_lines order_line
    where order_line.order_id = v_order.id
      and order_line.line_type = 'RETAIL_SKU'
      and not exists (
        select 1
        from dastak_v1.merchant_opportunity_lines opportunity_line
        where opportunity_line.opportunity_id = v_opportunity.id
          and opportunity_line.order_line_id = order_line.id
          and opportunity_line.sku_id = order_line.sku_id
          and opportunity_line.requested_quantity = order_line.quantity
      )
  ) or exists (
    select 1
    from dastak_v1.merchant_opportunity_lines opportunity_line
    where opportunity_line.opportunity_id = v_opportunity.id
      and not exists (
        select 1
        from dastak_v1.order_lines order_line
        where order_line.id = opportunity_line.order_line_id
          and order_line.order_id = v_order.id
          and order_line.line_type = 'RETAIL_SKU'
          and order_line.sku_id = opportunity_line.sku_id
          and order_line.quantity = opportunity_line.requested_quantity
      )
  ) then
    raise exception using errcode = '55000', message = 'opportunity basket no longer matches the canonical order';
  end if;

  -- Accept is the merchant's live physical confirmation of every exact unit.
  update dastak_v1.merchant_opportunities
  set status = 'SELECTED',
      promised_prep_minutes = p_promised_prep_minutes,
      responded_by = p_actor_id,
      responded_at = v_now,
      version = version + 1
  where id = v_opportunity.id;

  update dastak_v1.merchant_opportunities
  set status = 'LOST',
      version = version + 1
  where matching_attempt_id = v_attempt.id
    and id <> v_opportunity.id
    and status = 'OFFERED';

  update dastak_v1.matching_attempts
  set status = 'WON',
      winner_opportunity_id = v_opportunity.id,
      closed_at = v_now,
      version = version + 1
  where id = v_attempt.id;

  insert into dastak_v1.fulfilments (
    id,
    order_id,
    organization_id,
    branch_id,
    source_opportunity_id,
    fulfilment_type,
    status,
    promised_prep_minutes,
    committed_at
  ) values (
    v_fulfilment_id,
    v_order.id,
    v_opportunity.organization_id,
    v_branch.id,
    v_opportunity.id,
    'RETAIL',
    'RESERVED_PREPAYMENT',
    p_promised_prep_minutes,
    v_now
  );

  insert into dastak_v1.fulfilment_lines (
    fulfilment_id,
    order_line_id,
    confirmed_quantity
  )
  select
    v_fulfilment_id,
    opportunity_line.order_line_id,
    opportunity_line.requested_quantity
  from dastak_v1.merchant_opportunity_lines opportunity_line
  where opportunity_line.opportunity_id = v_opportunity.id
  order by opportunity_line.order_line_id;

  insert into dastak_v1.inventory_holds (
    fulfilment_id,
    order_line_id,
    branch_id,
    held_quantity,
    status,
    held_at
  )
  select
    v_fulfilment_id,
    opportunity_line.order_line_id,
    v_branch.id,
    opportunity_line.requested_quantity,
    'HELD',
    v_now
  from dastak_v1.merchant_opportunity_lines opportunity_line
  where opportunity_line.opportunity_id = v_opportunity.id
  order by opportunity_line.order_line_id;

  insert into dastak_v1.retail_line_allocations (
    order_line_id,
    merchant_branch_id,
    allocated_quantity,
    status
  )
  select
    opportunity_line.order_line_id,
    v_branch.id,
    opportunity_line.requested_quantity,
    'SELECTED'
  from dastak_v1.merchant_opportunity_lines opportunity_line
  where opportunity_line.opportunity_id = v_opportunity.id
  order by opportunity_line.order_line_id;

  insert into dastak_v1.retail_capacity_slots (
    branch_id,
    fulfilment_id,
    status,
    held_at
  ) values (
    v_branch.id,
    v_fulfilment_id,
    'HELD',
    v_now
  );

  update dastak_v1.order_lines
  set status = 'RESERVED',
      version = version + 1
  where order_id = v_order.id
    and line_type = 'RETAIL_SKU'
    and status = 'ORDERED';

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_opportunity.id::text || ':MERCHANT_SELECTED:2',
    'MERCHANT_OPPORTUNITY',
    v_opportunity.id,
    2,
    'MERCHANT_SELECTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'opportunityId', v_opportunity.id,
      'attemptId', v_attempt.id,
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment_id,
      'organizationId', v_opportunity.organization_id,
      'branchId', v_branch.id,
      'promisedPrepMinutes', p_promised_prep_minutes,
      'physicalStockConfirmed', true
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  )
  select
    opportunity.id::text || ':MERCHANT_OPPORTUNITY_LOST:' || opportunity.version::text,
    'MERCHANT_OPPORTUNITY',
    opportunity.id,
    opportunity.version,
    'MERCHANT_OPPORTUNITY_LOST',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'opportunityId', opportunity.id,
      'orderId', opportunity.order_id
    )
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.matching_attempt_id = v_attempt.id
    and opportunity.status = 'LOST';

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_fulfilment_id::text || ':RETAIL_RESERVATION_CREATED:1',
    'FULFILMENT',
    v_fulfilment_id,
    1,
    'RETAIL_RESERVATION_CREATED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'fulfilmentId', v_fulfilment_id,
      'orderId', v_order.id,
      'branchId', v_branch.id,
      'capacitySlotHeld', true
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'WAVE_1_OPPORTUNITY_ACCEPTED',
    'merchant_opportunity',
    v_opportunity.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'attemptId', v_attempt.id,
      'fulfilmentId', v_fulfilment_id,
      'branchId', v_branch.id,
      'idempotencyKey', p_idempotency_key,
      'physicalStockConfirmed', true
    )
  );

  -- A Wave 1 winner intentionally leaves the parent at MATCHING. It does not
  -- create FULLY_SECURED, AWAITING_PAYMENT or a payment window.
  v_response := dastak_v1_api.merchant_opportunity_json(
    p_actor_id,
    v_opportunity.id
  ) || pg_catalog.jsonb_build_object('fulfilmentId', v_fulfilment_id);

  insert into dastak_v1.idempotency_records (
    actor_id,
    command_name,
    idempotency_key,
    request_hash,
    response_body,
    response_status,
    resource_id
  ) values (
    p_actor_id,
    v_command,
    p_idempotency_key,
    v_request_hash,
    v_response,
    200,
    v_opportunity.id
  );

  return v_response;
end;
$$;

create function dastak_v1_api.decline_opportunity(
  p_actor_id uuid,
  p_opportunity_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'declineOpportunity';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_attempt_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);

  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'opportunityId', p_opportunity_id,
      'expectedVersion', p_expected_version
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select opportunity.order_id, opportunity.matching_attempt_id
  into v_order_id, v_attempt_id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'opportunity not found';
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;

  select attempt.* into v_attempt
  from dastak_v1.matching_attempts attempt
  where attempt.id = v_attempt_id
  for update;

  select opportunity.* into v_opportunity
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_opportunity.organization_id,
    'merchant.opportunities.respond',
    v_opportunity.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  if v_opportunity.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale opportunity version';
  end if;
  if v_order.status <> 'MATCHING'
    or v_attempt.wave <> 'WAVE_1'
    or v_attempt.status <> 'OPEN'
    or v_opportunity.status <> 'OFFERED' then
    raise exception using errcode = '55000', message = 'matching opportunity is no longer open';
  end if;
  if v_now >= v_attempt.expires_at or v_now >= v_opportunity.expires_at then
    raise exception using errcode = '55000', message = 'matching opportunity has expired';
  end if;

  update dastak_v1.merchant_opportunities
  set status = 'DECLINED',
      responded_by = p_actor_id,
      responded_at = v_now,
      version = version + 1
  where id = v_opportunity.id;

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_opportunity.id::text || ':MERCHANT_OPPORTUNITY_DECLINED:2',
    'MERCHANT_OPPORTUNITY',
    v_opportunity.id,
    2,
    'MERCHANT_OPPORTUNITY_DECLINED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'opportunityId', v_opportunity.id,
      'orderId', v_order.id,
      'branchId', v_opportunity.branch_id
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'WAVE_1_OPPORTUNITY_DECLINED',
    'merchant_opportunity',
    v_opportunity.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'attemptId', v_attempt.id,
      'branchId', v_opportunity.branch_id,
      'idempotencyKey', p_idempotency_key
    )
  );

  v_response := dastak_v1_api.merchant_opportunity_json(
    p_actor_id,
    v_opportunity.id
  );

  insert into dastak_v1.idempotency_records (
    actor_id,
    command_name,
    idempotency_key,
    request_hash,
    response_body,
    response_status,
    resource_id
  ) values (
    p_actor_id,
    v_command,
    p_idempotency_key,
    v_request_hash,
    v_response,
    200,
    v_opportunity.id
  );

  return v_response;
end;
$$;

create function dastak_v1_api.release_order_prepayment_resources(
  p_order_id uuid,
  p_actor_id uuid,
  p_target_order_version bigint,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_attempts integer := 0;
  v_opportunities integer := 0;
  v_holds integer := 0;
  v_slots integer := 0;
  v_allocations integer := 0;
  v_fulfilments integer := 0;
  v_response jsonb;
begin
  -- The caller already owns this lock; taking it again documents and enforces
  -- the same global order used by accept and expiry.
  perform customer_order.id
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  perform attempt.id
  from dastak_v1.matching_attempts attempt
  where attempt.order_id = p_order_id
  order by attempt.id
  for update;

  perform opportunity.id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.order_id = p_order_id
  order by opportunity.id
  for update;

  perform branch.id
  from dastak_v1.merchant_branches branch
  where exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = p_order_id
      and fulfilment.branch_id = branch.id
  )
  order by branch.id
  for update;

  update dastak_v1.matching_attempts
  set status = 'CANCELLED',
      closed_at = v_now,
      version = version + 1
  where order_id = p_order_id
    and status = 'OPEN';
  get diagnostics v_attempts = row_count;

  update dastak_v1.merchant_opportunities
  set status = 'INVALIDATED',
      version = version + 1
  where order_id = p_order_id
    and status = 'OFFERED';
  get diagnostics v_opportunities = row_count;

  update dastak_v1.inventory_holds hold
  set status = 'RELEASED',
      released_at = v_now,
      release_reason = p_reason,
      version = hold.version + 1
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = hold.fulfilment_id
    and fulfilment.order_id = p_order_id
    and hold.status = 'HELD';
  get diagnostics v_holds = row_count;

  update dastak_v1.retail_capacity_slots slot
  set status = 'RELEASED',
      released_at = v_now,
      release_reason = p_reason,
      version = slot.version + 1
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = slot.fulfilment_id
    and fulfilment.order_id = p_order_id
    and slot.status = 'HELD';
  get diagnostics v_slots = row_count;

  update dastak_v1.retail_line_allocations allocation
  set status = 'RELEASED',
      version = allocation.version + 1
  from dastak_v1.order_lines order_line
  where order_line.id = allocation.order_line_id
    and order_line.order_id = p_order_id
    and allocation.status in ('PROVISIONAL', 'SELECTED');
  get diagnostics v_allocations = row_count;

  update dastak_v1.fulfilments fulfilment
  set status = 'RELEASED',
      released_at = v_now,
      release_reason = p_reason,
      version = fulfilment.version + 1
  where fulfilment.order_id = p_order_id
    and fulfilment.status = 'RESERVED_PREPAYMENT';
  get diagnostics v_fulfilments = row_count;

  v_response := pg_catalog.jsonb_build_object(
    'attemptsCancelled', v_attempts,
    'opportunitiesInvalidated', v_opportunities,
    'inventoryHoldsReleased', v_holds,
    'capacitySlotsReleased', v_slots,
    'allocationsReleased', v_allocations,
    'fulfilmentsReleased', v_fulfilments,
    'releasedAt', v_now,
    'reason', p_reason
  );

  if v_attempts + v_opportunities + v_holds + v_slots
    + v_allocations + v_fulfilments > 0 then
    insert into dastak_v1.domain_events_outbox (
      event_key,
      aggregate_type,
      aggregate_id,
      aggregate_version,
      event_type,
      actor_id,
      payload
    ) values (
      p_order_id::text || ':ORDER_PREPAYMENT_RESOURCES_RELEASED:'
        || p_target_order_version::text,
      'ORDER',
      p_order_id,
      p_target_order_version,
      'ORDER_PREPAYMENT_RESOURCES_RELEASED',
      p_actor_id,
      pg_catalog.jsonb_build_object('orderId', p_order_id) || v_response
    );

    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_actor_id,
      'ORDER_PREPAYMENT_RESOURCES_RELEASED',
      'order',
      p_order_id,
      v_response
    );
  end if;

  return v_response;
end;
$$;

create function dastak_v1_api.expire_wave1_attempt(p_attempt_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_wave2_attempt_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_expired_opportunities integer := 0;
begin
  select attempt.order_id into v_order_id
  from dastak_v1.matching_attempts attempt
  where attempt.id = p_attempt_id;

  if not found then
    return false;
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;

  select attempt.* into v_attempt
  from dastak_v1.matching_attempts attempt
  where attempt.id = p_attempt_id
  for update;

  if v_attempt.wave <> 'WAVE_1' then
    raise exception using errcode = '22023', message = 'attempt is not Wave 1';
  end if;
  if v_attempt.status <> 'OPEN' then
    return false;
  end if;
  if v_order.status <> 'MATCHING' then
    return false;
  end if;
  if v_now < v_attempt.expires_at then
    return false;
  end if;

  perform opportunity.id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.matching_attempt_id = v_attempt.id
  order by opportunity.id
  for update;

  update dastak_v1.merchant_opportunities
  set status = 'EXPIRED',
      version = version + 1
  where matching_attempt_id = v_attempt.id
    and status = 'OFFERED';
  get diagnostics v_expired_opportunities = row_count;

  update dastak_v1.matching_attempts
  set status = 'EXPIRED',
      closed_at = v_now,
      version = version + 1
  where id = v_attempt.id;

  insert into dastak_v1.matching_attempts (
    order_id,
    wave,
    status,
    started_at,
    expires_at
  ) values (
    v_order.id,
    'WAVE_2',
    'OPEN',
    v_now,
    null
  )
  on conflict (order_id, wave) do nothing
  returning id into v_wave2_attempt_id;

  if v_wave2_attempt_id is null then
    select attempt.id into v_wave2_attempt_id
    from dastak_v1.matching_attempts attempt
    where attempt.order_id = v_order.id
      and attempt.wave = 'WAVE_2';
  end if;

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    payload
  ) values (
    v_attempt.id::text || ':WAVE_1_EXPIRED:2',
    'MATCHING_ATTEMPT',
    v_attempt.id,
    2,
    'WAVE_1_EXPIRED',
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt.id,
      'orderId', v_order.id,
      'expiredAt', v_now,
      'expiredOpportunityCount', v_expired_opportunities
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    payload
  ) values (
    v_wave2_attempt_id::text || ':WAVE_2_STARTED:1',
    'MATCHING_ATTEMPT',
    v_wave2_attempt_id,
    1,
    'WAVE_2_STARTED',
    pg_catalog.jsonb_build_object(
      'attemptId', v_wave2_attempt_id,
      'orderId', v_order.id,
      'startedAt', v_now,
      'sourceWave1AttemptId', v_attempt.id
    )
  );

  insert into dastak_v1.audit_events (
    action, resource_type, resource_id, metadata
  ) values (
    'WAVE_1_EXPIRED',
    'matching_attempt',
    v_attempt.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'wave2AttemptId', v_wave2_attempt_id,
      'expiredOpportunityCount', v_expired_opportunities
    )
  );

  return true;
end;
$$;

create function dastak_v1_api.process_due_wave1_attempts(p_limit integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt_id uuid;
  v_processed integer := 0;
begin
  if p_limit is null or p_limit not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'limit must be between 1 and 1000';
  end if;

  for v_attempt_id in
    select attempt.id
    from dastak_v1.matching_attempts attempt
    where attempt.wave = 'WAVE_1'
      and attempt.status = 'OPEN'
      and attempt.expires_at <= pg_catalog.clock_timestamp()
    order by attempt.expires_at, attempt.id
    limit p_limit
  loop
    if dastak_v1_api.expire_wave1_attempt(v_attempt_id) then
      v_processed := v_processed + 1;
    end if;
  end loop;

  return v_processed;
end;
$$;

create or replace function dastak_v1_api.cancel_prepayment_order(
  p_actor_id uuid,
  p_order_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'cancelPrepaymentOrder';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_release_summary jsonb;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);

  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'orderId', p_order_id,
      'expectedVersion', p_expected_version
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  -- Cancel, accept and expiry all serialize on this parent row first.
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
    and customer_order.customer_id = p_actor_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  if v_order.status = 'CANCELLED_PREPAYMENT' then
    v_response := dastak_v1_api.order_json(v_order.id, p_actor_id);
    insert into dastak_v1.idempotency_records (
      actor_id, command_name, idempotency_key, request_hash,
      response_body, response_status, resource_id
    ) values (
      p_actor_id, v_command, p_idempotency_key, v_request_hash,
      v_response, 200, v_order.id
    );
    return v_response;
  end if;

  if v_order.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale order version';
  end if;

  if v_order.paid_at is not null
    or v_order.status not in ('CREATED', 'MATCHING', 'FULLY_SECURED', 'AWAITING_PAYMENT') then
    raise exception using
      errcode = '55000',
      message = 'customer cancellation is not allowed after payment';
  end if;

  v_release_summary := dastak_v1_api.release_order_prepayment_resources(
    v_order.id,
    p_actor_id,
    v_order.version + 1,
    'CUSTOMER_CANCELLED_PREPAYMENT'
  );

  update dastak_v1.orders
  set status = 'CANCELLED_PREPAYMENT',
      version = version + 1
  where id = v_order.id;

  insert into dastak_v1.order_state_journal (
    order_id,
    from_status,
    to_status,
    order_version,
    command_name,
    actor_id,
    reason,
    metadata
  ) values (
    v_order.id,
    v_order.status,
    'CANCELLED_PREPAYMENT',
    v_order.version + 1,
    v_command,
    p_actor_id,
    'Customer cancelled before payment.',
    pg_catalog.jsonb_build_object('resourceRelease', v_release_summary)
  );

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_order.id::text || ':ORDER_CANCELLED_PREPAYMENT:' || (v_order.version + 1)::text,
    'ORDER',
    v_order.id,
    v_order.version + 1,
    'ORDER_CANCELLED_PREPAYMENT',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'customerId', p_actor_id,
      'status', 'CANCELLED_PREPAYMENT',
      'version', v_order.version + 1,
      'resourceRelease', v_release_summary
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'ORDER_CANCELLED_PREPAYMENT',
    'order',
    v_order.id,
    pg_catalog.jsonb_build_object(
      'idempotencyKey', p_idempotency_key,
      'fromStatus', v_order.status,
      'version', v_order.version + 1,
      'resourceRelease', v_release_summary
    )
  );

  v_response := dastak_v1_api.order_json(v_order.id, p_actor_id);

  insert into dastak_v1.idempotency_records (
    actor_id,
    command_name,
    idempotency_key,
    request_hash,
    response_body,
    response_status,
    resource_id
  ) values (
    p_actor_id,
    v_command,
    p_idempotency_key,
    v_request_hash,
    v_response,
    200,
    v_order.id
  );

  return v_response;
end;
$$;

create or replace function dastak_v1_api.order_json(
  p_order_id uuid,
  p_customer_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', customer_order.id,
    'displayOrderNumber', customer_order.display_order_number,
    'orderType', customer_order.order_type,
    'status', customer_order.status,
    'version', customer_order.version,
    'fulfilmentProgress', case
      when customer_order.status = 'MATCHING' then
        pg_catalog.jsonb_build_object(
          'state', 'FINDING_ITEMS'
        )
      else null
    end,
    'deliveryAddress', context_snapshot.delivery_address,
    'recipient', context_snapshot.recipient,
    'price', (
      select pg_catalog.jsonb_build_object(
        'snapshotKind', price_snapshot.snapshot_kind,
        'subtotalPaise', price_snapshot.subtotal_paise,
        'deliveryFeePaise', price_snapshot.delivery_fee_paise,
        'platformFeePaise', price_snapshot.platform_fee_paise,
        'discountPaise', price_snapshot.discount_paise,
        'taxPaise', price_snapshot.tax_paise,
        'totalPaise', price_snapshot.total_paise,
        'currencyCode', price_snapshot.currency_code
      )
      from dastak_v1.order_price_snapshots price_snapshot
      where price_snapshot.order_id = customer_order.id
      order by case price_snapshot.snapshot_kind
        when 'FINAL' then 4
        when 'PAID' then 3
        when 'FULLY_SECURED' then 2
        else 1
      end desc
      limit 1
    ),
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              'id', order_line.id,
              'lineType', order_line.line_type,
              'skuId', order_line.sku_id,
              'menuItemId', order_line.food_menu_item_id,
              'name', order_line.product_name_snapshot,
              'variant', order_line.variant_snapshot,
              'packSize', order_line.pack_size_snapshot,
              'quantity', order_line.quantity,
              'unitPricePaise', order_line.unit_price_paise,
              'lineTotalPaise', order_line.line_total_paise,
              'status', order_line.status
            )
          )
          order by order_line.created_at, order_line.id
        )
        from dastak_v1.order_lines order_line
        where order_line.order_id = customer_order.id
      ),
      '[]'::jsonb
    ),
    'submittedAt', customer_order.submitted_at,
    'fullySecuredAt', customer_order.fully_secured_at,
    'paymentExpiresAt', customer_order.payment_expires_at,
    'paidAt', customer_order.paid_at,
    'deliveredAt', customer_order.delivered_at,
    'createdAt', customer_order.created_at,
    'updatedAt', customer_order.updated_at
  )
  from dastak_v1.orders customer_order
  join dastak_v1.order_context_snapshots context_snapshot
    on context_snapshot.order_id = customer_order.id
  where customer_order.id = p_order_id
    and customer_order.customer_id = p_customer_id;
$$;

create function public.dastak_v1_set_branch_operational_state(
  p_branch_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_is_open boolean,
  p_accepting_orders boolean
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.set_branch_operational_state(
    auth.uid(),
    p_branch_id,
    p_idempotency_key,
    p_expected_version,
    p_is_open,
    p_accepting_orders
  );
$$;

create function public.dastak_v1_list_merchant_opportunities(
  p_limit integer default 50
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.list_merchant_opportunities(auth.uid(), p_limit);
$$;

create function public.dastak_v1_get_merchant_opportunity(p_opportunity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.get_merchant_opportunity(auth.uid(), p_opportunity_id);
$$;

create function public.dastak_v1_accept_wave1_opportunity(
  p_opportunity_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_promised_prep_minutes integer
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.accept_wave1_opportunity(
    auth.uid(),
    p_opportunity_id,
    p_idempotency_key,
    p_expected_version,
    p_promised_prep_minutes
  );
$$;

create function public.dastak_v1_decline_opportunity(
  p_opportunity_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.decline_opportunity(
    auth.uid(),
    p_opportunity_id,
    p_idempotency_key,
    p_expected_version
  );
$$;

revoke execute on function public.dastak_v1_set_branch_operational_state(
  uuid, text, bigint, boolean, boolean
) from public, anon, authenticated;
revoke execute on function public.dastak_v1_list_merchant_opportunities(integer)
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_get_merchant_opportunity(uuid)
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_accept_wave1_opportunity(
  uuid, text, bigint, integer
) from public, anon, authenticated;
revoke execute on function public.dastak_v1_decline_opportunity(
  uuid, text, bigint
) from public, anon, authenticated;

grant execute on function dastak_v1_api.set_branch_operational_state(
  uuid, uuid, text, bigint, boolean, boolean
) to authenticated;
grant execute on function dastak_v1_api.list_merchant_opportunities(uuid, integer)
  to authenticated;
grant execute on function dastak_v1_api.get_merchant_opportunity(uuid, uuid)
  to authenticated;
grant execute on function dastak_v1_api.accept_wave1_opportunity(
  uuid, uuid, text, bigint, integer
) to authenticated;
grant execute on function dastak_v1_api.decline_opportunity(
  uuid, uuid, text, bigint
) to authenticated;

grant execute on function public.dastak_v1_set_branch_operational_state(
  uuid, text, bigint, boolean, boolean
) to authenticated;
grant execute on function public.dastak_v1_list_merchant_opportunities(integer)
  to authenticated;
grant execute on function public.dastak_v1_get_merchant_opportunity(uuid)
  to authenticated;
grant execute on function public.dastak_v1_accept_wave1_opportunity(
  uuid, text, bigint, integer
) to authenticated;
grant execute on function public.dastak_v1_decline_opportunity(
  uuid, text, bigint
) to authenticated;

grant execute on function dastak_v1_api.expire_wave1_attempt(uuid)
  to service_role;
grant execute on function dastak_v1_api.process_due_wave1_attempts(integer)
  to service_role;

comment on function public.dastak_v1_submit_order(text, bigint, jsonb) is
  'V1 submitOrder command. Creates Wave 1 matching and notification intent transactionally; external delivery is asynchronous.';
comment on function public.dastak_v1_cancel_prepayment_order(uuid, text, bigint) is
  'V1 cancelPrepaymentOrder command. Atomically invalidates matching and releases unpaid reservations and capacity.';
comment on table dastak_v1.inventory_holds is
  'Exact physical units confirmed and held by a merchant; this is not a stock-on-hand counter.';
comment on table dastak_v1.retail_capacity_slots is
  'One hard branch-capacity commitment per selected retail fulfilment.';

do $$
declare
  v_job_id bigint;
begin
  select job.jobid into v_job_id
  from cron.job job
  where job.jobname = 'dastak-v1-wave1-expiry';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;
end;
$$;

select cron.schedule(
  'dastak-v1-wave1-expiry',
  '10 seconds',
  'select dastak_v1_api.process_due_wave1_attempts(100);'
);
