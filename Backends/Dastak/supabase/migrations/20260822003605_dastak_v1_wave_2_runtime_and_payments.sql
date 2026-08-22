-- Dastak V1 Wave 2, all-or-nothing security coordination and payment
-- reservation lifecycle. Legacy payment-first commerce remains isolated.

create type dastak_v1.wave2_hold_status as enum (
  'HELD', 'SELECTED', 'RELEASED'
);
create type dastak_v1.fulfilment_plan_status as enum (
  'CANDIDATE', 'LOCKED', 'REJECTED'
);
create type dastak_v1.payment_status as enum (
  'RESERVED', 'SUCCEEDED', 'EXPIRED', 'CANCELLED'
);
create type dastak_v1.payment_attempt_status as enum (
  'CREATED', 'PROVIDER_READY', 'FAILED', 'SUCCEEDED', 'EXPIRED', 'LATE_SUCCESS'
);
create type dastak_v1.payment_event_outcome as enum (
  'SUCCEEDED', 'DUPLICATE', 'LATE_SUCCESS', 'REJECTED'
);
create type dastak_v1.payment_reconciliation_status as enum (
  'OPEN', 'REFUND_PENDING', 'REVERSED', 'REFUNDED', 'CLOSED'
);

-- Denormalizing the immutable wave allows the Wave 1 single-winner invariant
-- to remain index-enforced while Wave 2 selects more than one opportunity.
alter table dastak_v1.merchant_opportunities add column wave dastak_v1.matching_wave;

update dastak_v1.merchant_opportunities opportunity
set wave = attempt.wave
from dastak_v1.matching_attempts attempt
where attempt.id = opportunity.matching_attempt_id;

create function dastak_v1.set_merchant_opportunity_wave()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select attempt.wave into new.wave
  from dastak_v1.matching_attempts attempt
  where attempt.id = new.matching_attempt_id;

  if new.wave is null then
    raise exception 'matching attempt does not exist';
  end if;
  return new;
end;
$$;

create trigger merchant_opportunities_set_wave
before insert on dastak_v1.merchant_opportunities
for each row execute function dastak_v1.set_merchant_opportunity_wave();

alter table dastak_v1.merchant_opportunities alter column wave set not null;

drop index dastak_v1.merchant_opportunities_selected_attempt_uidx;
create unique index merchant_opportunities_wave1_selected_attempt_uidx
  on dastak_v1.merchant_opportunities (matching_attempt_id)
  where wave = 'WAVE_1' and status = 'SELECTED';

alter table dastak_v1.matching_attempts
  drop constraint matching_attempts_check,
  drop constraint matching_attempts_check1;

alter table dastak_v1.matching_attempts
  add constraint matching_attempts_window_check check (
    expires_at is not null and expires_at > started_at
  ),
  add constraint matching_attempts_state_check check (
    (status = 'OPEN' and closed_at is null and winner_opportunity_id is null)
    or (
      status = 'WON'
      and closed_at is not null
      and (
        (wave = 'WAVE_1' and winner_opportunity_id is not null)
        or (wave = 'WAVE_2' and winner_opportunity_id is null)
      )
    )
    or (
      status in ('EXPIRED', 'CANCELLED')
      and closed_at is not null
      and winner_opportunity_id is null
    )
  );

alter table dastak_v1.merchant_opportunities
  drop constraint merchant_opportunities_check1;

alter table dastak_v1.merchant_opportunities
  add constraint merchant_opportunities_state_check check (
    (
      status = 'OFFERED'
      and responded_by is null
      and responded_at is null
      and promised_prep_minutes is null
    )
    or (
      status in ('PROVISIONALLY_ACCEPTED', 'SELECTED', 'RELEASED')
      and responded_by is not null
      and responded_at is not null
      and promised_prep_minutes is not null
    )
    or (
      status = 'DECLINED'
      and responded_by is not null
      and responded_at is not null
      and promised_prep_minutes is null
    )
    or (
      status in ('EXPIRED', 'LOST', 'INVALIDATED')
      and promised_prep_minutes is null
    )
  ),
  add constraint merchant_opportunities_wave_state_check check (
    (wave = 'WAVE_1' and status <> 'PROVISIONALLY_ACCEPTED')
    or wave = 'WAVE_2'
  );

create table dastak_v1.wave2_provisional_holds (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references dastak_v1.merchant_opportunities(id),
  matching_attempt_id uuid not null references dastak_v1.matching_attempts(id),
  order_id uuid not null references dastak_v1.orders(id),
  order_line_id uuid not null references dastak_v1.order_lines(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  held_quantity integer not null check (held_quantity > 0),
  status dastak_v1.wave2_hold_status not null default 'HELD',
  held_at timestamptz not null,
  expires_at timestamptz not null check (expires_at > held_at),
  selected_at timestamptz,
  released_at timestamptz,
  release_reason text,
  final_inventory_hold_id uuid unique references dastak_v1.inventory_holds(id),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (opportunity_id, order_line_id),
  check (
    (status = 'HELD' and selected_at is null and released_at is null
      and release_reason is null and final_inventory_hold_id is null)
    or (status = 'SELECTED' and selected_at is not null and released_at is null
      and release_reason is null and final_inventory_hold_id is not null)
    or (status = 'RELEASED' and released_at is not null
      and release_reason is not null and final_inventory_hold_id is null)
  )
);

create index wave2_provisional_holds_attempt_idx
  on dastak_v1.wave2_provisional_holds (matching_attempt_id, status, branch_id);
create index wave2_provisional_holds_order_idx
  on dastak_v1.wave2_provisional_holds (order_id, status, order_line_id);
create index wave2_provisional_holds_line_idx
  on dastak_v1.wave2_provisional_holds (order_line_id, status, branch_id);
create index wave2_provisional_holds_branch_idx
  on dastak_v1.wave2_provisional_holds (branch_id, status);

create table dastak_v1.fulfilment_plans (
  id uuid primary key default gen_random_uuid(),
  matching_attempt_id uuid not null references dastak_v1.matching_attempts(id),
  order_id uuid not null references dastak_v1.orders(id),
  fingerprint text not null check (char_length(fingerprint) between 36 and 120),
  status dastak_v1.fulfilment_plan_status not null default 'CANDIDATE',
  merchant_count integer not null check (merchant_count between 1 and 3),
  retail_line_count integer not null check (retail_line_count > 0),
  route_distance_meters bigint not null check (route_distance_meters >= 0),
  reliability_score_bps bigint not null check (reliability_score_bps between 0 and 30000),
  feasibility_snapshot jsonb not null check (jsonb_typeof(feasibility_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  locked_at timestamptz,
  rejected_at timestamptz,
  rejection_reason text,
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (matching_attempt_id, fingerprint),
  check (
    (status = 'CANDIDATE' and locked_at is null and rejected_at is null
      and rejection_reason is null)
    or (status = 'LOCKED' and locked_at is not null and rejected_at is null
      and rejection_reason is null)
    or (status = 'REJECTED' and locked_at is null and rejected_at is not null
      and rejection_reason is not null)
  )
);

create unique index fulfilment_plans_locked_attempt_uidx
  on dastak_v1.fulfilment_plans (matching_attempt_id)
  where status = 'LOCKED';
create index fulfilment_plans_order_idx
  on dastak_v1.fulfilment_plans (order_id, status, merchant_count);

create table dastak_v1.fulfilment_plan_merchants (
  plan_id uuid not null references dastak_v1.fulfilment_plans(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  opportunity_id uuid not null references dastak_v1.merchant_opportunities(id),
  reliability_score_bps integer not null check (reliability_score_bps between 0 and 10000),
  created_at timestamptz not null default now(),
  primary key (plan_id, branch_id),
  unique (plan_id, opportunity_id)
);

create index fulfilment_plan_merchants_branch_idx
  on dastak_v1.fulfilment_plan_merchants (branch_id, plan_id);
create index fulfilment_plan_merchants_opportunity_idx
  on dastak_v1.fulfilment_plan_merchants (opportunity_id);

create table dastak_v1.fulfilment_plan_lines (
  plan_id uuid not null references dastak_v1.fulfilment_plans(id),
  order_line_id uuid not null references dastak_v1.order_lines(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  provisional_hold_id uuid not null references dastak_v1.wave2_provisional_holds(id),
  allocated_quantity integer not null check (allocated_quantity > 0),
  created_at timestamptz not null default now(),
  primary key (plan_id, order_line_id),
  foreign key (plan_id, branch_id)
    references dastak_v1.fulfilment_plan_merchants(plan_id, branch_id)
);

create index fulfilment_plan_lines_order_line_idx
  on dastak_v1.fulfilment_plan_lines (order_line_id);
create index fulfilment_plan_lines_branch_idx
  on dastak_v1.fulfilment_plan_lines (branch_id, plan_id);
create index fulfilment_plan_lines_hold_idx
  on dastak_v1.fulfilment_plan_lines (provisional_hold_id);

create table dastak_v1.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references dastak_v1.orders(id),
  customer_id uuid not null references public.accounts(id),
  status dastak_v1.payment_status not null default 'RESERVED',
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null check (currency_code = 'INR'),
  reserved_at timestamptz not null,
  expires_at timestamptz not null check (expires_at > reserved_at),
  succeeded_at timestamptz,
  expired_at timestamptz,
  cancelled_at timestamptz,
  provider_payment_reference text unique check (
    provider_payment_reference is null
    or provider_payment_reference ~ '^pay_[A-Za-z0-9]+$'
  ),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  check (
    (status = 'RESERVED' and succeeded_at is null and expired_at is null
      and cancelled_at is null and provider_payment_reference is null)
    or (status = 'SUCCEEDED' and succeeded_at is not null and expired_at is null
      and cancelled_at is null and provider_payment_reference is not null)
    or (status = 'EXPIRED' and succeeded_at is null and expired_at is not null
      and cancelled_at is null and provider_payment_reference is null)
    or (status = 'CANCELLED' and succeeded_at is null and expired_at is null
      and cancelled_at is not null and provider_payment_reference is null)
  )
);

create index payments_due_idx
  on dastak_v1.payments (expires_at, order_id)
  where status = 'RESERVED';
create index payments_customer_idx
  on dastak_v1.payments (customer_id, reserved_at desc);

create table dastak_v1.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references dastak_v1.payments(id),
  order_id uuid not null references dastak_v1.orders(id),
  customer_id uuid not null references public.accounts(id),
  status dastak_v1.payment_attempt_status not null default 'CREATED',
  idempotency_key text not null check (char_length(idempotency_key) between 1 and 200),
  request_hash bytea not null,
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null check (currency_code = 'INR'),
  provider text not null default 'RAZORPAY' check (provider = 'RAZORPAY'),
  provider_receipt text not null unique check (char_length(provider_receipt) between 1 and 40),
  provider_order_reference text unique check (
    provider_order_reference is null
    or provider_order_reference ~ '^order_[A-Za-z0-9]+$'
  ),
  provider_payment_reference text unique check (
    provider_payment_reference is null
    or provider_payment_reference ~ '^pay_[A-Za-z0-9]+$'
  ),
  failure_code text,
  created_at timestamptz not null default now(),
  provider_ready_at timestamptz,
  failed_at timestamptz,
  succeeded_at timestamptz,
  expired_at timestamptz,
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (customer_id, idempotency_key),
  check (
    (status = 'CREATED' and provider_ready_at is null and failed_at is null
      and succeeded_at is null and expired_at is null and failure_code is null)
    or (status = 'PROVIDER_READY' and provider_order_reference is not null
      and provider_ready_at is not null and failed_at is null
      and succeeded_at is null and expired_at is null and failure_code is null)
    or (status = 'FAILED' and failed_at is not null and failure_code is not null
      and succeeded_at is null and expired_at is null)
    or (status = 'SUCCEEDED' and provider_order_reference is not null
      and provider_payment_reference is not null and succeeded_at is not null
      and expired_at is null)
    or (status = 'EXPIRED' and succeeded_at is null and expired_at is not null)
    or (status = 'LATE_SUCCESS' and provider_order_reference is not null
      and provider_payment_reference is not null and succeeded_at is not null)
  )
);

create index payment_attempts_payment_idx
  on dastak_v1.payment_attempts (payment_id, created_at desc);
create index payment_attempts_order_idx
  on dastak_v1.payment_attempts (order_id, created_at desc);

create table dastak_v1.payment_provider_events (
  provider text not null default 'RAZORPAY' check (provider = 'RAZORPAY'),
  provider_event_id text not null check (char_length(provider_event_id) between 1 and 200),
  event_type text not null check (event_type in ('payment_captured', 'payment_failed')),
  order_id uuid not null references dastak_v1.orders(id),
  payment_id uuid not null references dastak_v1.payments(id),
  payment_attempt_id uuid references dastak_v1.payment_attempts(id),
  provider_order_reference text not null check (
    provider_order_reference ~ '^order_[A-Za-z0-9]+$'
  ),
  provider_payment_reference text not null check (
    provider_payment_reference ~ '^pay_[A-Za-z0-9]+$'
  ),
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null check (currency_code = 'INR'),
  occurred_at timestamptz not null,
  request_digest text not null check (request_digest ~ '^[0-9a-f]{64}$'),
  outcome dastak_v1.payment_event_outcome not null,
  response_body jsonb not null check (jsonb_typeof(response_body) = 'object'),
  processed_at timestamptz not null default now(),
  primary key (provider, provider_event_id)
);

create index payment_provider_events_order_idx
  on dastak_v1.payment_provider_events (order_id, processed_at desc);
create index payment_provider_events_payment_idx
  on dastak_v1.payment_provider_events (payment_id, processed_at desc);
create index payment_provider_events_attempt_idx
  on dastak_v1.payment_provider_events (payment_attempt_id);
create index payment_provider_events_payment_reference_idx
  on dastak_v1.payment_provider_events (provider_payment_reference);

create table dastak_v1.payment_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  payment_id uuid not null references dastak_v1.payments(id),
  payment_attempt_id uuid references dastak_v1.payment_attempts(id),
  source_provider_event_id text not null,
  provider_payment_reference text not null unique check (
    provider_payment_reference ~ '^pay_[A-Za-z0-9]+$'
  ),
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null check (currency_code = 'INR'),
  reason text not null check (char_length(reason) between 1 and 200),
  status dastak_v1.payment_reconciliation_status not null default 'OPEN',
  resolution_reference text,
  opened_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  check (
    (status in ('OPEN', 'REFUND_PENDING') and resolved_at is null)
    or (status in ('REVERSED', 'REFUNDED', 'CLOSED') and resolved_at is not null)
  )
);

create index payment_reconciliation_cases_status_idx
  on dastak_v1.payment_reconciliation_cases (status, opened_at, id);
create index payment_reconciliation_cases_order_idx
  on dastak_v1.payment_reconciliation_cases (order_id, opened_at desc);
create index payment_reconciliation_cases_payment_idx
  on dastak_v1.payment_reconciliation_cases (payment_id, opened_at desc);
create index payment_reconciliation_cases_attempt_idx
  on dastak_v1.payment_reconciliation_cases (payment_attempt_id);

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values
  (
    'matching.wave2_max_pickup_route_meters',
    'INTEGER',
    'Maximum branch-to-branch-to-customer pickup route for a Wave 2 plan.',
    null,
    '{"minimum":1}'::jsonb,
    true,
    true
  ),
  (
    'matching.operational_reliability_bps',
    'INTEGER',
    'Audited operational reliability score used only after route efficiency.',
    null,
    '{"minimum":0,"maximum":10000}'::jsonb,
    true,
    true
  ),
  (
    'delivery.transport_load_profiles',
    'JSON',
    'Supported transport load ceilings used before payment.',
    null,
    '{}'::jsonb,
    true,
    true
  ),
  (
    'delivery.default_sku_logistics',
    'JSON',
    'Explicit operational fallback for incomplete canonical SKU logistics.',
    null,
    '{}'::jsonb,
    true,
    true
  );

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values (
  'platform.orders.trace',
  'Inspect matching, reservation, capacity and payment execution traces.',
  'HIGHLY_SENSITIVE'
);

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
values (
  '10000000-0000-4000-8000-000000000006',
  'platform.orders.trace'
);

create or replace function dastak_v1.guard_merchant_opportunity()
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
    or new.wave is distinct from old.wave
    or new.started_at is distinct from old.started_at
    or new.expires_at is distinct from old.expires_at
    or new.created_at is distinct from old.created_at then
    raise exception 'merchant-opportunity identity and authoritative window cannot change';
  end if;

  if new.version <> old.version + 1 then
    raise exception 'merchant-opportunity version must increment exactly once';
  end if;

  if new.status is distinct from old.status and not (
    (
      old.status = 'OFFERED'
      and new.status in (
        'PROVISIONALLY_ACCEPTED', 'SELECTED', 'DECLINED',
        'EXPIRED', 'LOST', 'INVALIDATED'
      )
    )
    or (
      old.status = 'PROVISIONALLY_ACCEPTED'
      and new.status in ('SELECTED', 'RELEASED', 'EXPIRED', 'INVALIDATED')
    )
    or (old.status = 'SELECTED' and new.status = 'RELEASED')
  ) then
    raise exception 'invalid merchant-opportunity transition: % -> %', old.status, new.status;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_wave2_provisional_hold()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_line dastak_v1.order_lines%rowtype;
begin
  if tg_op = 'INSERT' then
    select opportunity.* into v_opportunity
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.id = new.opportunity_id;

    select order_line.* into v_line
    from dastak_v1.order_lines order_line
    where order_line.id = new.order_line_id;

    if v_opportunity.wave <> 'WAVE_2'
      or v_opportunity.status <> 'PROVISIONALLY_ACCEPTED'
      or v_opportunity.matching_attempt_id <> new.matching_attempt_id
      or v_opportunity.order_id <> new.order_id
      or v_opportunity.branch_id <> new.branch_id
      or v_line.order_id <> new.order_id
      or v_line.line_type <> 'RETAIL_SKU'
      or v_line.quantity <> new.held_quantity
      or not exists (
        select 1
        from dastak_v1.merchant_opportunity_lines opportunity_line
        where opportunity_line.opportunity_id = new.opportunity_id
          and opportunity_line.order_line_id = new.order_line_id
          and opportunity_line.requested_quantity = new.held_quantity
      ) then
      raise exception 'invalid Wave 2 exact physical hold';
    end if;
  else
    if new.id is distinct from old.id
      or new.opportunity_id is distinct from old.opportunity_id
      or new.matching_attempt_id is distinct from old.matching_attempt_id
      or new.order_id is distinct from old.order_id
      or new.order_line_id is distinct from old.order_line_id
      or new.branch_id is distinct from old.branch_id
      or new.held_quantity is distinct from old.held_quantity
      or new.held_at is distinct from old.held_at
      or new.expires_at is distinct from old.expires_at then
      raise exception 'Wave 2 physical-hold identity and quantity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'Wave 2 physical-hold version must increment exactly once';
    end if;
    if new.status is distinct from old.status
      and not (old.status = 'HELD' and new.status in ('SELECTED', 'RELEASED')) then
      raise exception 'invalid Wave 2 physical-hold transition: % -> %', old.status, new.status;
    end if;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_fulfilment_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.matching_attempt_id is distinct from old.matching_attempt_id
    or new.order_id is distinct from old.order_id
    or new.fingerprint is distinct from old.fingerprint
    or new.merchant_count is distinct from old.merchant_count
    or new.retail_line_count is distinct from old.retail_line_count
    or new.route_distance_meters is distinct from old.route_distance_meters
    or new.reliability_score_bps is distinct from old.reliability_score_bps
    or new.feasibility_snapshot is distinct from old.feasibility_snapshot
    or new.created_at is distinct from old.created_at then
    raise exception 'fulfilment-plan evaluation cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'fulfilment-plan version must increment exactly once';
  end if;
  if new.status is distinct from old.status
    and not (old.status = 'CANDIDATE' and new.status in ('LOCKED', 'REJECTED')) then
    raise exception 'invalid fulfilment-plan transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.customer_id is distinct from old.customer_id
    or new.amount_paise is distinct from old.amount_paise
    or new.currency_code is distinct from old.currency_code
    or new.reserved_at is distinct from old.reserved_at
    or new.expires_at is distinct from old.expires_at then
    raise exception 'payment reservation identity and amount cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'payment version must increment exactly once';
  end if;
  if new.status is distinct from old.status
    and not (old.status = 'RESERVED' and new.status in ('SUCCEEDED', 'EXPIRED', 'CANCELLED')) then
    raise exception 'invalid payment transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_payment_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.payment_id is distinct from old.payment_id
    or new.order_id is distinct from old.order_id
    or new.customer_id is distinct from old.customer_id
    or new.idempotency_key is distinct from old.idempotency_key
    or new.request_hash is distinct from old.request_hash
    or new.amount_paise is distinct from old.amount_paise
    or new.currency_code is distinct from old.currency_code
    or new.provider is distinct from old.provider
    or new.provider_receipt is distinct from old.provider_receipt
    or new.created_at is distinct from old.created_at then
    raise exception 'payment-attempt identity and amount cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'payment-attempt version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'CREATED' and new.status in ('PROVIDER_READY', 'FAILED', 'EXPIRED'))
    or (old.status = 'PROVIDER_READY' and new.status in ('FAILED', 'SUCCEEDED', 'EXPIRED', 'LATE_SUCCESS'))
    or (old.status = 'FAILED' and new.status in ('SUCCEEDED', 'LATE_SUCCESS'))
    or (old.status = 'EXPIRED' and new.status = 'LATE_SUCCESS')
  ) then
    raise exception 'invalid payment-attempt transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_payment_reconciliation_case()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.payment_id is distinct from old.payment_id
    or new.payment_attempt_id is distinct from old.payment_attempt_id
    or new.source_provider_event_id is distinct from old.source_provider_event_id
    or new.provider_payment_reference is distinct from old.provider_payment_reference
    or new.amount_paise is distinct from old.amount_paise
    or new.currency_code is distinct from old.currency_code
    or new.reason is distinct from old.reason
    or new.opened_at is distinct from old.opened_at then
    raise exception 'payment reconciliation identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'payment reconciliation version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'OPEN' and new.status in ('REFUND_PENDING', 'REVERSED', 'REFUNDED', 'CLOSED'))
    or (old.status = 'REFUND_PENDING' and new.status in ('REVERSED', 'REFUNDED', 'CLOSED'))
  ) then
    raise exception 'invalid payment reconciliation transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.enforce_retail_capacity_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer;
  v_held integer;
begin
  select branch.capacity_limit into v_limit
  from dastak_v1.merchant_branches branch
  where branch.id = new.branch_id
  for update;

  if not found then
    raise exception 'retail capacity branch does not exist';
  end if;

  select count(*) into v_held
  from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = new.branch_id
    and slot.status = 'HELD';

  if v_held >= v_limit then
    raise exception using errcode = '55000', message = 'RETAIL_CAPACITY_UNAVAILABLE';
  end if;
  return new;
end;
$$;

create trigger wave2_provisional_holds_guard
before insert or update on dastak_v1.wave2_provisional_holds
for each row execute function dastak_v1.guard_wave2_provisional_hold();
create trigger wave2_provisional_holds_no_delete
before delete on dastak_v1.wave2_provisional_holds
for each row execute function dastak_v1.reject_delete();

create trigger fulfilment_plans_guard
before update on dastak_v1.fulfilment_plans
for each row execute function dastak_v1.guard_fulfilment_plan();
create trigger fulfilment_plans_no_delete
before delete on dastak_v1.fulfilment_plans
for each row execute function dastak_v1.reject_delete();

create trigger fulfilment_plan_merchants_immutable
before update or delete on dastak_v1.fulfilment_plan_merchants
for each row execute function dastak_v1.reject_mutation();
create trigger fulfilment_plan_lines_immutable
before update or delete on dastak_v1.fulfilment_plan_lines
for each row execute function dastak_v1.reject_mutation();

create trigger payments_guard
before update on dastak_v1.payments
for each row execute function dastak_v1.guard_payment();
create trigger payments_no_delete
before delete on dastak_v1.payments
for each row execute function dastak_v1.reject_delete();

create trigger payment_attempts_guard
before update on dastak_v1.payment_attempts
for each row execute function dastak_v1.guard_payment_attempt();
create trigger payment_attempts_no_delete
before delete on dastak_v1.payment_attempts
for each row execute function dastak_v1.reject_delete();

create trigger payment_provider_events_immutable
before update or delete on dastak_v1.payment_provider_events
for each row execute function dastak_v1.reject_mutation();

create trigger payment_reconciliation_cases_guard
before update on dastak_v1.payment_reconciliation_cases
for each row execute function dastak_v1.guard_payment_reconciliation_case();
create trigger payment_reconciliation_cases_no_delete
before delete on dastak_v1.payment_reconciliation_cases
for each row execute function dastak_v1.reject_delete();

create trigger retail_capacity_slots_enforce_limit
before insert on dastak_v1.retail_capacity_slots
for each row execute function dastak_v1.enforce_retail_capacity_insert();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'wave2_provisional_holds',
    'fulfilment_plans',
    'fulfilment_plan_merchants',
    'fulfilment_plan_lines',
    'payments',
    'payment_attempts',
    'payment_provider_events',
    'payment_reconciliation_cases'
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

create function dastak_v1.is_valid_default_sku_logistics(p_value jsonb)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select dastak_v1.is_valid_sku_logistics(p_value)
    and p_value ?& array[
      'weightGrams', 'lengthMillimetres', 'widthMillimetres',
      'heightMillimetres', 'temperatureClass', 'fragile', 'bulky'
    ];
$$;

create function dastak_v1.is_valid_transport_load_profiles(p_profiles jsonb)
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
  v_class jsonb;
begin
  if pg_catalog.jsonb_typeof(p_profiles) <> 'array'
    or pg_catalog.jsonb_array_length(p_profiles) = 0 then
    return false;
  end if;

  for v_profile in
    select value from pg_catalog.jsonb_array_elements(p_profiles)
  loop
    if pg_catalog.jsonb_typeof(v_profile) <> 'object' then
      return false;
    end if;
    v_type := v_profile ->> 'transportType';
    if v_type not in ('WALKING', 'BICYCLE', 'MOTORBIKE', 'SCOOTER', 'AUTO', 'CAR')
      or v_type = any(v_seen) then
      return false;
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_type);

    if pg_catalog.jsonb_typeof(v_profile -> 'maxWeightGrams') <> 'number'
      or v_profile ->> 'maxWeightGrams' !~ '^[1-9][0-9]*$'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxVolumeCubicMillimetres') <> 'number'
      or v_profile ->> 'maxVolumeCubicMillimetres' !~ '^[1-9][0-9]*$'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxLongestSideMillimetres') <> 'number'
      or v_profile ->> 'maxLongestSideMillimetres' !~ '^[1-9][0-9]*$'
      or pg_catalog.jsonb_typeof(v_profile -> 'allowsBulky') <> 'boolean'
      or pg_catalog.jsonb_typeof(v_profile -> 'temperatureClasses') <> 'array'
      or pg_catalog.jsonb_array_length(v_profile -> 'temperatureClasses') = 0 then
      return false;
    end if;

    for v_class in
      select value
      from pg_catalog.jsonb_array_elements(v_profile -> 'temperatureClasses')
    loop
      if pg_catalog.jsonb_typeof(v_class) <> 'string'
        or v_class #>> '{}' not in ('AMBIENT', 'CHILLED', 'FROZEN') then
        return false;
      end if;
    end loop;
  end loop;

  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

create function dastak_v1_api.wave2_global_configuration()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_timeout jsonb;
  v_hold jsonb;
  v_max_merchants jsonb;
  v_route_max jsonb;
  v_payment_window jsonb;
  v_profiles jsonb;
  v_default_logistics jsonb;
begin
  v_timeout := dastak_v1_api.effective_setting_json('matching.wave2_timeout_seconds');
  v_hold := dastak_v1_api.effective_setting_json('matching.wave2_hold_seconds');
  v_max_merchants := dastak_v1_api.effective_setting_json(
    'matching.wave2_max_retail_merchants'
  );
  v_route_max := dastak_v1_api.effective_setting_json(
    'matching.wave2_max_pickup_route_meters'
  );
  v_payment_window := dastak_v1_api.effective_setting_json('payment.reservation_seconds');
  v_profiles := dastak_v1_api.effective_setting_json('delivery.transport_load_profiles');
  v_default_logistics := dastak_v1_api.effective_setting_json(
    'delivery.default_sku_logistics'
  );

  if not dastak_v1.validate_setting_value('matching.wave2_timeout_seconds', v_timeout)
    or (v_timeout #>> '{}')::numeric > 2147483647
    or not dastak_v1.validate_setting_value('matching.wave2_hold_seconds', v_hold)
    or (v_hold #>> '{}')::numeric > 2147483647
    or (v_hold #>> '{}')::integer < (v_timeout #>> '{}')::integer
    or not dastak_v1.validate_setting_value(
      'matching.wave2_max_retail_merchants', v_max_merchants
    )
    or (v_max_merchants #>> '{}')::integer <> 3
    or not dastak_v1.validate_setting_value(
      'matching.wave2_max_pickup_route_meters', v_route_max
    )
    or (v_route_max #>> '{}')::numeric > 2147483647
    or not dastak_v1.validate_setting_value(
      'payment.reservation_seconds', v_payment_window
    )
    or (v_payment_window #>> '{}')::numeric > 2147483647
    or not dastak_v1.is_valid_transport_load_profiles(v_profiles)
    or not dastak_v1.is_valid_default_sku_logistics(v_default_logistics) then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Wave 2, transport and payment reservation configuration is missing or invalid.',
      hint = 'Configure explicit Wave 2 timeout/hold/route, transport profiles, SKU logistics fallback and payment window values.';
  end if;

  return pg_catalog.jsonb_build_object(
    'wave2TimeoutSeconds', (v_timeout #>> '{}')::integer,
    'wave2HoldSeconds', (v_hold #>> '{}')::integer,
    'maxRetailMerchants', (v_max_merchants #>> '{}')::integer,
    'maxPickupRouteMeters', (v_route_max #>> '{}')::integer,
    'paymentReservationSeconds', (v_payment_window #>> '{}')::integer,
    'transportLoadProfiles', v_profiles,
    'defaultSkuLogistics', v_default_logistics
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Wave 2 numeric configuration is invalid.',
      hint = 'Correct Wave 2 and payment operational settings.';
end;
$$;

create function dastak_v1_api.branch_reliability_bps(p_branch_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch dastak_v1.merchant_branches%rowtype;
  v_value jsonb;
begin
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'branch not found';
  end if;

  v_value := dastak_v1_api.effective_setting_json(
    'matching.operational_reliability_bps',
    v_branch.id,
    v_branch.organization_id,
    v_branch.service_zone_id
  );

  if not dastak_v1.validate_setting_value(
    'matching.operational_reliability_bps', v_value
  ) or (v_value #>> '{}')::numeric > 10000 then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = pg_catalog.format(
        'Operational reliability is missing or invalid for branch %s.',
        p_branch_id
      ),
      hint = 'Configure an audited branch reliability score before Wave 2 matching.';
  end if;

  return (v_value #>> '{}')::integer;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = pg_catalog.format(
        'Operational reliability is invalid for branch %s.', p_branch_id
      );
end;
$$;

create function dastak_v1_api.order_transport_snapshot(p_order_id uuid)
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
  v_has_bulky boolean := false;
  v_temperature_classes text[] := '{}'::text[];
  v_line record;
  v_attributes jsonb;
  v_weight numeric;
  v_length numeric;
  v_width numeric;
  v_height numeric;
  v_temperature text;
  v_feasible jsonb;
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
    v_weight := coalesce(
      (v_attributes ->> 'weightGrams')::numeric,
      (v_default ->> 'weightGrams')::numeric
    );
    v_length := coalesce(
      (v_attributes ->> 'lengthMillimetres')::numeric,
      (v_default ->> 'lengthMillimetres')::numeric
    );
    v_width := coalesce(
      (v_attributes ->> 'widthMillimetres')::numeric,
      (v_default ->> 'widthMillimetres')::numeric
    );
    v_height := coalesce(
      (v_attributes ->> 'heightMillimetres')::numeric,
      (v_default ->> 'heightMillimetres')::numeric
    );
    v_temperature := coalesce(
      v_attributes ->> 'temperatureClass',
      v_default ->> 'temperatureClass'
    );

    v_total_weight := v_total_weight + (v_weight * v_line.quantity);
    v_total_volume := v_total_volume
      + (v_length * v_width * v_height * v_line.quantity);
    v_longest_side := greatest(v_longest_side, v_length, v_width, v_height);
    v_has_bulky := v_has_bulky or coalesce(
      (v_attributes ->> 'bulky')::boolean,
      (v_default ->> 'bulky')::boolean
    );
    if not v_temperature = any(v_temperature_classes) then
      v_temperature_classes := pg_catalog.array_append(
        v_temperature_classes, v_temperature
      );
    end if;
  end loop;

  if v_total_weight <= 0 or v_total_volume <= 0 or v_longest_side <= 0 then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Order logistics could not be calculated from canonical or fallback data.';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(profile.value order by profile.value ->> 'transportType'),
    '[]'::jsonb
  ) into v_feasible
  from pg_catalog.jsonb_array_elements(v_profiles) profile(value)
  where (profile.value ->> 'maxWeightGrams')::numeric >= v_total_weight
    and (profile.value ->> 'maxVolumeCubicMillimetres')::numeric >= v_total_volume
    and (profile.value ->> 'maxLongestSideMillimetres')::numeric >= v_longest_side
    and (not v_has_bulky or (profile.value ->> 'allowsBulky')::boolean)
    and not exists (
      select 1
      from pg_catalog.unnest(v_temperature_classes) required_class
      where not (profile.value -> 'temperatureClasses')
        @> pg_catalog.to_jsonb(array[required_class])
    );

  return pg_catalog.jsonb_build_object(
    'feasible', pg_catalog.jsonb_array_length(v_feasible) > 0,
    'totalWeightGrams', v_total_weight,
    'totalVolumeCubicMillimetres', v_total_volume,
    'longestSideMillimetres', v_longest_side,
    'containsBulky', v_has_bulky,
    'temperatureClasses', pg_catalog.to_jsonb(v_temperature_classes),
    'eligibleTransportTypes', (
      select coalesce(
        pg_catalog.jsonb_agg(profile.value ->> 'transportType'),
        '[]'::jsonb
      )
      from pg_catalog.jsonb_array_elements(v_feasible) profile(value)
    )
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Canonical SKU logistics or transport limits contain invalid numbers.';
end;
$$;

create function dastak_v1_api.branch_customer_distance_meters(
  p_order_id uuid,
  p_branch_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.st_distance(
    branch.location::extensions.geography,
    extensions.st_setsrid(
      extensions.st_makepoint(
        (context_snapshot.delivery_address ->> 'longitude')::double precision,
        (context_snapshot.delivery_address ->> 'latitude')::double precision
      ),
      4326
    )::extensions.geography
  )
  from dastak_v1.merchant_branches branch
  join dastak_v1.order_context_snapshots context_snapshot
    on context_snapshot.order_id = p_order_id
  where branch.id = p_branch_id
    and branch.location is not null
    and pg_catalog.jsonb_typeof(context_snapshot.delivery_address -> 'latitude') = 'number'
    and pg_catalog.jsonb_typeof(context_snapshot.delivery_address -> 'longitude') = 'number';
$$;

create function dastak_v1_api.branch_distance_meters(
  p_from_branch_id uuid,
  p_to_branch_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.st_distance(
    source.location::extensions.geography,
    destination.location::extensions.geography
  )
  from dastak_v1.merchant_branches source
  join dastak_v1.merchant_branches destination
    on destination.id = p_to_branch_id
  where source.id = p_from_branch_id
    and source.location is not null
    and destination.location is not null;
$$;

create function dastak_v1_api.pickup_route_distance_meters(
  p_order_id uuid,
  p_branch_ids uuid[]
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_count integer := pg_catalog.cardinality(p_branch_ids);
  v_distance numeric;
begin
  if v_count = 1 then
    v_distance := dastak_v1_api.branch_customer_distance_meters(
      p_order_id, p_branch_ids[1]
    );
  elsif v_count = 2 then
    v_distance := least(
      dastak_v1_api.branch_distance_meters(p_branch_ids[1], p_branch_ids[2])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[2]),
      dastak_v1_api.branch_distance_meters(p_branch_ids[2], p_branch_ids[1])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[1])
    );
  elsif v_count = 3 then
    v_distance := least(
      dastak_v1_api.branch_distance_meters(p_branch_ids[1], p_branch_ids[2])
        + dastak_v1_api.branch_distance_meters(p_branch_ids[2], p_branch_ids[3])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[3]),
      dastak_v1_api.branch_distance_meters(p_branch_ids[1], p_branch_ids[3])
        + dastak_v1_api.branch_distance_meters(p_branch_ids[3], p_branch_ids[2])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[2]),
      dastak_v1_api.branch_distance_meters(p_branch_ids[2], p_branch_ids[1])
        + dastak_v1_api.branch_distance_meters(p_branch_ids[1], p_branch_ids[3])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[3]),
      dastak_v1_api.branch_distance_meters(p_branch_ids[2], p_branch_ids[3])
        + dastak_v1_api.branch_distance_meters(p_branch_ids[3], p_branch_ids[1])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[1]),
      dastak_v1_api.branch_distance_meters(p_branch_ids[3], p_branch_ids[1])
        + dastak_v1_api.branch_distance_meters(p_branch_ids[1], p_branch_ids[2])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[2]),
      dastak_v1_api.branch_distance_meters(p_branch_ids[3], p_branch_ids[2])
        + dastak_v1_api.branch_distance_meters(p_branch_ids[2], p_branch_ids[1])
        + dastak_v1_api.branch_customer_distance_meters(p_order_id, p_branch_ids[1])
    );
  else
    raise exception using errcode = '22023', message = 'pickup route requires one to three branches';
  end if;

  if v_distance is null then
    return null;
  end if;
  return pg_catalog.round(v_distance)::bigint;
end;
$$;

create function dastak_v1_api.evaluate_wave2_candidate(
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
  v_wave1 jsonb;
  v_reasons text[];
  v_selected_count integer;
  v_reliability integer;
begin
  v_wave1 := dastak_v1_api.evaluate_wave1_candidate(p_order_id, p_branch_id);
  v_selected_count := (v_wave1 ->> 'selectedLineCount')::integer;

  select coalesce(pg_catalog.array_agg(reason), '{}'::text[])
  into v_reasons
  from pg_catalog.jsonb_array_elements_text(
    v_wave1 -> 'exclusionReasons'
  ) reason
  where reason <> 'INCOMPLETE_CATALOGUE_COVERAGE';

  if v_selected_count = 0 then
    v_reasons := pg_catalog.array_append(v_reasons, 'NO_REQUESTED_SKUS_SELECTED');
  end if;

  if pg_catalog.cardinality(v_reasons) = 0 then
    v_reliability := dastak_v1_api.branch_reliability_bps(p_branch_id);
  end if;

  return v_wave1 || pg_catalog.jsonb_build_object(
    'eligible', pg_catalog.cardinality(v_reasons) = 0,
    'exclusionReasons', pg_catalog.to_jsonb(v_reasons),
    'operationalReliabilityBps', v_reliability,
    'wave2SubsetLineCount', v_selected_count
  );
end;
$$;

create function dastak_v1_api.start_wave2(
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
  v_wave1 dastak_v1.matching_attempts%rowtype;
  v_attempt_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_configuration jsonb;
  v_expires_at timestamptz;
  v_candidate_count integer := 0;
  v_opportunity_count integer := 0;
  v_transport jsonb;
begin
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
    and attempt.wave = 'WAVE_2';

  if v_attempt_id is not null then
    return v_attempt_id;
  end if;

  select attempt.* into v_wave1
  from dastak_v1.matching_attempts attempt
  where attempt.order_id = v_order.id
    and attempt.wave = 'WAVE_1'
  for update;

  if v_order.status <> 'MATCHING'
    or v_order.order_type not in ('RETAIL_ONLY', 'MIXED')
    or v_wave1.status <> 'EXPIRED' then
    raise exception using
      errcode = '55000',
      message = 'order is not eligible to start Wave 2';
  end if;

  -- Required operational settings are resolved before availability is
  -- evaluated. A missing value aborts instead of masquerading as no stock.
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(v_order.id);
  v_expires_at := v_now + pg_catalog.make_interval(
    secs => (v_configuration ->> 'wave2TimeoutSeconds')::integer
  );

  insert into dastak_v1.matching_attempts (
    order_id, wave, status, started_at, expires_at
  ) values (
    v_order.id, 'WAVE_2', 'OPEN', v_now, v_expires_at
  )
  returning id into v_attempt_id;

  insert into dastak_v1.matching_candidate_evaluations (
    matching_attempt_id, order_id, organization_id, branch_id,
    eligible, exclusion_reasons, eligibility_snapshot, evaluated_at
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
    select dastak_v1_api.evaluate_wave2_candidate(v_order.id, branch.id) snapshot
  ) evaluation
  where organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
  order by branch.id;

  get diagnostics v_candidate_count = row_count;

  -- A valid configuration but an over-limit basket is genuine transport
  -- infeasibility. It opens no merchant opportunities and expires normally.
  if (v_transport ->> 'feasible')::boolean then
    insert into dastak_v1.merchant_opportunities (
      matching_attempt_id, order_id, organization_id, branch_id,
      status, started_at, expires_at
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
  end if;

  get diagnostics v_opportunity_count = row_count;

  insert into dastak_v1.merchant_opportunity_lines (
    opportunity_id, order_line_id, sku_id, product_name_snapshot,
    variant_snapshot, pack_size_snapshot, requested_quantity
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
  join dastak_v1.merchant_sku_selections selection
    on selection.branch_id = opportunity.branch_id
    and selection.sku_id = order_line.sku_id
    and selection.state = 'SELECTED'
  where opportunity.matching_attempt_id = v_attempt_id
  order by opportunity.id, order_line.created_at, order_line.id;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_attempt_id::text || ':WAVE_2_STARTED:1',
    'MATCHING_ATTEMPT',
    v_attempt_id,
    1,
    'WAVE_2_STARTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt_id,
      'orderId', v_order.id,
      'startedAt', v_now,
      'expiresAt', v_expires_at,
      'eligibleOpportunityCount', v_opportunity_count,
      'transportSnapshot', v_transport
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
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
      'expiresAt', opportunity.expires_at,
      'subsetLineCount', (
        select count(*)
        from dastak_v1.merchant_opportunity_lines line
        where line.opportunity_id = opportunity.id
      )
    )
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.matching_attempt_id = v_attempt_id;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'WAVE_2_STARTED',
    'matching_attempt',
    v_attempt_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'candidateCount', v_candidate_count,
      'opportunityCount', v_opportunity_count,
      'startedAt', v_now,
      'expiresAt', v_expires_at,
      'transportFeasible', v_transport -> 'feasible'
    )
  );

  return v_attempt_id;
end;
$$;

create or replace function dastak_v1_api.expire_wave1_attempt(p_attempt_id uuid)
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
  if v_attempt.status <> 'OPEN' or v_order.status <> 'MATCHING'
    or v_now < v_attempt.expires_at then
    return false;
  end if;

  perform opportunity.id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.matching_attempt_id = v_attempt.id
  order by opportunity.id
  for update;

  update dastak_v1.merchant_opportunities
  set status = 'EXPIRED', version = version + 1
  where matching_attempt_id = v_attempt.id
    and status = 'OFFERED';
  get diagnostics v_expired_opportunities = row_count;

  update dastak_v1.matching_attempts
  set status = 'EXPIRED', closed_at = v_now, version = version + 1
  where id = v_attempt.id;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
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

  -- This call is part of the same authoritative expiry transaction.
  v_wave2_attempt_id := dastak_v1_api.start_wave2(v_order.id, null);

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

create function dastak_v1_api.record_wave2_candidate_plans(p_attempt_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_configuration jsonb;
  v_transport jsonb;
  v_combo record;
  v_plan_id uuid;
  v_inserted integer := 0;
begin
  select attempt.* into v_attempt
  from dastak_v1.matching_attempts attempt
  where attempt.id = p_attempt_id;

  if not found or v_attempt.wave <> 'WAVE_2' then
    raise exception using errcode = '22023', message = 'Wave 2 attempt is required';
  end if;

  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(v_attempt.order_id);
  if not (v_transport ->> 'feasible')::boolean then
    return 0;
  end if;

  for v_combo in
    with recursive accepted_branches as (
      select distinct hold.branch_id
      from dastak_v1.wave2_provisional_holds hold
      join dastak_v1.merchant_opportunities opportunity
        on opportunity.id = hold.opportunity_id
      where hold.matching_attempt_id = p_attempt_id
        and hold.status = 'HELD'
        and hold.expires_at > pg_catalog.clock_timestamp()
        and opportunity.status = 'PROVISIONALLY_ACCEPTED'
    ), combinations(branch_ids, last_branch_id, merchant_count) as (
      select array[branch.branch_id], branch.branch_id, 1
      from accepted_branches branch
      union all
      select
        combination.branch_ids || branch.branch_id,
        branch.branch_id,
        combination.merchant_count + 1
      from combinations combination
      join accepted_branches branch
        on branch.branch_id > combination.last_branch_id
      where combination.merchant_count < 3
    ), complete_combinations as (
      select combination.branch_ids, combination.merchant_count
      from combinations combination
      where not exists (
        select 1
        from dastak_v1.order_lines order_line
        where order_line.order_id = v_attempt.order_id
          and order_line.line_type = 'RETAIL_SKU'
          and not exists (
            select 1
            from dastak_v1.wave2_provisional_holds hold
            join dastak_v1.merchant_opportunities opportunity
              on opportunity.id = hold.opportunity_id
            where hold.matching_attempt_id = p_attempt_id
              and hold.order_line_id = order_line.id
              and hold.branch_id = any(combination.branch_ids)
              and hold.status = 'HELD'
              and hold.expires_at > pg_catalog.clock_timestamp()
              and opportunity.status = 'PROVISIONALLY_ACCEPTED'
          )
      )
    ), minimal_combinations as (
      select complete.branch_ids, complete.merchant_count
      from complete_combinations complete
      where not exists (
        select 1
        from pg_catalog.unnest(complete.branch_ids) removed(branch_id)
        where pg_catalog.cardinality(complete.branch_ids) > 1
          and not exists (
            select 1
            from dastak_v1.order_lines order_line
            where order_line.order_id = v_attempt.order_id
              and order_line.line_type = 'RETAIL_SKU'
              and not exists (
                select 1
                from dastak_v1.wave2_provisional_holds hold
                join dastak_v1.merchant_opportunities opportunity
                  on opportunity.id = hold.opportunity_id
                where hold.matching_attempt_id = p_attempt_id
                  and hold.order_line_id = order_line.id
                  and hold.branch_id = any(
                    pg_catalog.array_remove(complete.branch_ids, removed.branch_id)
                  )
                  and hold.status = 'HELD'
                  and hold.expires_at > pg_catalog.clock_timestamp()
                  and opportunity.status = 'PROVISIONALLY_ACCEPTED'
              )
          )
      )
    )
    select
      minimal.branch_ids,
      minimal.merchant_count,
      dastak_v1_api.pickup_route_distance_meters(
        v_attempt.order_id, minimal.branch_ids
      ) route_distance_meters,
      (
        select sum(dastak_v1_api.branch_reliability_bps(reliability_branch.branch_id))
        from pg_catalog.unnest(minimal.branch_ids) reliability_branch(branch_id)
      ) reliability_score_bps
    from minimal_combinations minimal
    order by minimal.merchant_count, minimal.branch_ids
  loop
    if v_combo.route_distance_meters is null
      or v_combo.route_distance_meters
        > (v_configuration ->> 'maxPickupRouteMeters')::bigint then
      continue;
    end if;

    insert into dastak_v1.fulfilment_plans (
      matching_attempt_id,
      order_id,
      fingerprint,
      merchant_count,
      retail_line_count,
      route_distance_meters,
      reliability_score_bps,
      feasibility_snapshot
    ) values (
      v_attempt.id,
      v_attempt.order_id,
      pg_catalog.array_to_string(v_combo.branch_ids, ','),
      v_combo.merchant_count,
      (
        select count(*)
        from dastak_v1.order_lines order_line
        where order_line.order_id = v_attempt.order_id
          and order_line.line_type = 'RETAIL_SKU'
      ),
      v_combo.route_distance_meters,
      v_combo.reliability_score_bps,
      pg_catalog.jsonb_build_object(
        'transport', v_transport,
        'routeFeasible', true,
        'maxPickupRouteMeters', v_configuration -> 'maxPickupRouteMeters',
        'advertisingInfluence', false
      )
    )
    on conflict (matching_attempt_id, fingerprint) do nothing
    returning id into v_plan_id;

    if v_plan_id is null then
      select plan.id into v_plan_id
      from dastak_v1.fulfilment_plans plan
      where plan.matching_attempt_id = v_attempt.id
        and plan.fingerprint = pg_catalog.array_to_string(v_combo.branch_ids, ',');
    else
      v_inserted := v_inserted + 1;

      insert into dastak_v1.fulfilment_plan_merchants (
        plan_id, branch_id, opportunity_id, reliability_score_bps
      )
      select
        v_plan_id,
        selected_branch.branch_id,
        (
          select opportunity.id
          from dastak_v1.merchant_opportunities opportunity
          where opportunity.matching_attempt_id = v_attempt.id
            and opportunity.branch_id = selected_branch.branch_id
            and opportunity.status = 'PROVISIONALLY_ACCEPTED'
          order by opportunity.id
          limit 1
        ),
        dastak_v1_api.branch_reliability_bps(selected_branch.branch_id)
      from pg_catalog.unnest(v_combo.branch_ids) selected_branch(branch_id)
      order by selected_branch.branch_id;

      insert into dastak_v1.fulfilment_plan_lines (
        plan_id, order_line_id, branch_id, provisional_hold_id, allocated_quantity
      )
      select
        v_plan_id,
        order_line.id,
        selected_hold.branch_id,
        selected_hold.id,
        order_line.quantity
      from dastak_v1.order_lines order_line
      cross join lateral (
        select hold.id, hold.branch_id
        from dastak_v1.wave2_provisional_holds hold
        join dastak_v1.merchant_opportunities opportunity
          on opportunity.id = hold.opportunity_id
        where hold.matching_attempt_id = v_attempt.id
          and hold.order_line_id = order_line.id
          and hold.branch_id = any(v_combo.branch_ids)
          and hold.status = 'HELD'
          and hold.expires_at > pg_catalog.clock_timestamp()
          and opportunity.status = 'PROVISIONALLY_ACCEPTED'
        order by
          dastak_v1_api.branch_reliability_bps(hold.branch_id) desc,
          hold.branch_id,
          hold.id
        limit 1
      ) selected_hold
      where order_line.order_id = v_attempt.order_id
        and order_line.line_type = 'RETAIL_SKU'
      order by order_line.id;
    end if;

    v_plan_id := null;
  end loop;

  return v_inserted;
end;
$$;

create function dastak_v1_api.retail_security_snapshot(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_configuration jsonb;
  v_transport jsonb;
  v_branch_ids uuid[];
  v_route_distance bigint;
  v_line_count integer;
  v_allocation_count integer;
  v_fulfilment_count integer;
  v_reasons text[] := '{}'::text[];
begin
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(p_order_id);

  select count(*) into v_line_count
  from dastak_v1.order_lines order_line
  where order_line.order_id = p_order_id
    and order_line.line_type = 'RETAIL_SKU';

  select count(*) into v_allocation_count
  from dastak_v1.retail_line_allocations allocation
  join dastak_v1.order_lines order_line
    on order_line.id = allocation.order_line_id
  where order_line.order_id = p_order_id
    and order_line.line_type = 'RETAIL_SKU'
    and allocation.status = 'SELECTED'
    and allocation.allocated_quantity = order_line.quantity;

  select coalesce(pg_catalog.array_agg(distinct fulfilment.branch_id order by fulfilment.branch_id), '{}')
  into v_branch_ids
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id
    and fulfilment.fulfilment_type = 'RETAIL'
    and fulfilment.status = 'RESERVED_PREPAYMENT';

  select count(*) into v_fulfilment_count
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id
    and fulfilment.fulfilment_type = 'RETAIL'
    and fulfilment.status = 'RESERVED_PREPAYMENT';

  if v_line_count = 0 then
    v_reasons := pg_catalog.array_append(v_reasons, 'RETAIL_LINES_MISSING');
  end if;
  if v_allocation_count <> v_line_count then
    v_reasons := pg_catalog.array_append(v_reasons, 'RETAIL_COVERAGE_INCOMPLETE');
  end if;
  if pg_catalog.cardinality(v_branch_ids) < 1
    or pg_catalog.cardinality(v_branch_ids)
      > (v_configuration ->> 'maxRetailMerchants')::integer then
    v_reasons := pg_catalog.array_append(v_reasons, 'RETAIL_MERCHANT_COUNT_INVALID');
  end if;

  if exists (
    select 1
    from dastak_v1.order_lines order_line
    where order_line.order_id = p_order_id
      and order_line.line_type = 'RETAIL_SKU'
      and not exists (
        select 1
        from dastak_v1.retail_line_allocations allocation
        join dastak_v1.fulfilment_lines fulfilment_line
          on fulfilment_line.order_line_id = allocation.order_line_id
        join dastak_v1.fulfilments fulfilment
          on fulfilment.id = fulfilment_line.fulfilment_id
        join dastak_v1.inventory_holds hold
          on hold.fulfilment_id = fulfilment.id
          and hold.order_line_id = order_line.id
        join dastak_v1.retail_capacity_slots capacity_slot
          on capacity_slot.fulfilment_id = fulfilment.id
        where allocation.order_line_id = order_line.id
          and allocation.status = 'SELECTED'
          and allocation.allocated_quantity = order_line.quantity
          and allocation.merchant_branch_id = fulfilment.branch_id
          and fulfilment.status = 'RESERVED_PREPAYMENT'
          and fulfilment_line.confirmed_quantity = order_line.quantity
          and hold.status = 'HELD'
          and hold.held_quantity = order_line.quantity
          and hold.branch_id = fulfilment.branch_id
          and capacity_slot.status = 'HELD'
      )
  ) then
    v_reasons := pg_catalog.array_append(v_reasons, 'EXACT_RESERVATIONS_INVALID');
  end if;

  if exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    join dastak_v1.merchant_branches branch on branch.id = fulfilment.branch_id
    join dastak_v1.merchant_organizations organization
      on organization.id = branch.organization_id
    left join dastak_v1.branch_operational_states operating
      on operating.branch_id = branch.id
    where fulfilment.order_id = p_order_id
      and fulfilment.fulfilment_type = 'RETAIL'
      and fulfilment.status = 'RESERVED_PREPAYMENT'
      and (
        organization.status <> 'ACTIVE'
        or organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
        or branch.status <> 'ACTIVE'
        or operating.branch_id is null
        or not operating.is_open
        or not operating.accepting_orders
        or (
          select count(*)
          from dastak_v1.retail_capacity_slots slot
          where slot.branch_id = branch.id and slot.status = 'HELD'
        ) > branch.capacity_limit
      )
  ) then
    v_reasons := pg_catalog.array_append(v_reasons, 'MERCHANT_CAPACITY_OR_ELIGIBILITY_INVALID');
  end if;

  if v_fulfilment_count <> pg_catalog.cardinality(v_branch_ids) then
    v_reasons := pg_catalog.array_append(v_reasons, 'ONE_FULFILMENT_PER_BRANCH_REQUIRED');
  end if;

  if not (v_transport ->> 'feasible')::boolean then
    v_reasons := pg_catalog.array_append(v_reasons, 'TRANSPORT_LOAD_INFEASIBLE');
  end if;

  if pg_catalog.cardinality(v_branch_ids) between 1 and 3 then
    v_route_distance := dastak_v1_api.pickup_route_distance_meters(
      p_order_id, v_branch_ids
    );
    if v_route_distance is null
      or v_route_distance > (v_configuration ->> 'maxPickupRouteMeters')::bigint then
      v_reasons := pg_catalog.array_append(v_reasons, 'PICKUP_ROUTE_INFEASIBLE');
    end if;
  end if;

  if not (
    exists (
      select 1
      from dastak_v1.matching_attempts attempt
      where attempt.order_id = p_order_id
        and attempt.wave = 'WAVE_1'
        and attempt.status = 'WON'
    )
    or exists (
      select 1
      from dastak_v1.fulfilment_plans plan
      where plan.order_id = p_order_id
        and plan.status = 'LOCKED'
    )
  ) then
    v_reasons := pg_catalog.array_append(v_reasons, 'MATCHING_PLAN_NOT_LOCKED');
  end if;

  return pg_catalog.jsonb_build_object(
    'secured', pg_catalog.cardinality(v_reasons) = 0,
    'reasons', pg_catalog.to_jsonb(v_reasons),
    'retailLineCount', v_line_count,
    'allocatedLineCount', v_allocation_count,
    'retailMerchantCount', pg_catalog.cardinality(v_branch_ids),
    'branchIds', pg_catalog.to_jsonb(v_branch_ids),
    'routeDistanceMeters', v_route_distance,
    'transport', v_transport
  );
end;
$$;

create function dastak_v1_api.food_security_snapshot(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order_type dastak_v1.order_type;
  v_required boolean;
  v_line_count integer;
  v_secured_count integer;
begin
  select customer_order.order_type into v_order_type
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;

  v_required := v_order_type in ('FOOD_ONLY', 'MIXED');
  if not v_required then
    return pg_catalog.jsonb_build_object(
      'required', false,
      'secured', true,
      'reason', null
    );
  end if;

  select count(*) into v_line_count
  from dastak_v1.order_lines order_line
  where order_line.order_id = p_order_id
    and order_line.line_type = 'FOOD_MENU_ITEM';

  select count(*) into v_secured_count
  from dastak_v1.order_lines order_line
  where order_line.order_id = p_order_id
    and order_line.line_type = 'FOOD_MENU_ITEM'
    and exists (
      select 1
      from dastak_v1.fulfilment_lines fulfilment_line
      join dastak_v1.fulfilments fulfilment
        on fulfilment.id = fulfilment_line.fulfilment_id
      where fulfilment_line.order_line_id = order_line.id
        and fulfilment.fulfilment_type = 'FOOD'
        and fulfilment.status = 'RESERVED_PREPAYMENT'
        and fulfilment_line.confirmed_quantity = order_line.quantity
    );

  return pg_catalog.jsonb_build_object(
    'required', true,
    'secured', v_line_count > 0 and v_secured_count = v_line_count,
    'foodLineCount', v_line_count,
    'securedFoodLineCount', v_secured_count,
    'reason', case
      when v_line_count > 0 and v_secured_count = v_line_count then null
      else 'RESTAURANT_CONFIRMATION_INCOMPLETE'
    end
  );
end;
$$;

create function dastak_v1_api.coordinate_fully_secured(
  p_order_id uuid,
  p_actor_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_retail jsonb;
  v_food jsonb;
  v_configuration jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_payment_expires_at timestamptz;
  v_payment_id uuid;
  v_price dastak_v1.order_price_snapshots%rowtype;
  v_from_version bigint;
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  if v_order.status in ('FULLY_SECURED', 'AWAITING_PAYMENT') then
    return pg_catalog.jsonb_build_object(
      'coordinated', true,
      'orderId', v_order.id,
      'status', v_order.status,
      'version', v_order.version,
      'paymentExpiresAt', v_order.payment_expires_at
    );
  end if;
  if v_order.status <> 'MATCHING' then
    return pg_catalog.jsonb_build_object(
      'coordinated', false,
      'orderId', v_order.id,
      'status', v_order.status,
      'reasons', pg_catalog.jsonb_build_array('ORDER_NOT_MATCHING')
    );
  end if;

  -- The parent order is always first. Selected branches follow in UUID order.
  perform branch.id
  from dastak_v1.merchant_branches branch
  where exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = v_order.id
      and fulfilment.branch_id = branch.id
      and fulfilment.status = 'RESERVED_PREPAYMENT'
  )
  order by branch.id
  for update;

  v_retail := case
    when v_order.order_type in ('RETAIL_ONLY', 'MIXED')
      then dastak_v1_api.retail_security_snapshot(v_order.id)
    else pg_catalog.jsonb_build_object('secured', true, 'required', false)
  end;
  v_food := dastak_v1_api.food_security_snapshot(v_order.id);

  if not (v_retail ->> 'secured')::boolean
    or not (v_food ->> 'secured')::boolean then
    return pg_catalog.jsonb_build_object(
      'coordinated', false,
      'orderId', v_order.id,
      'status', v_order.status,
      'retail', v_retail,
      'food', v_food
    );
  end if;

  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_payment_expires_at := v_now + pg_catalog.make_interval(
    secs => (v_configuration ->> 'paymentReservationSeconds')::integer
  );

  select price_snapshot.* into v_price
  from dastak_v1.order_price_snapshots price_snapshot
  where price_snapshot.order_id = v_order.id
    and price_snapshot.snapshot_kind = 'SUBMITTED';

  if not found or v_price.total_paise <= 0 or v_price.currency_code <> 'INR' then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'A positive authoritative INR order total is required before payment.';
  end if;

  v_from_version := v_order.version;
  update dastak_v1.orders
  set status = 'FULLY_SECURED',
      fully_secured_at = v_now,
      version = version + 1
  where id = v_order.id
  returning * into v_order;

  insert into dastak_v1.order_price_snapshots (
    order_id, snapshot_kind, subtotal_paise, delivery_fee_paise,
    platform_fee_paise, discount_paise, tax_paise, total_paise,
    currency_code, calculation_details
  ) values (
    v_order.id,
    'FULLY_SECURED',
    v_price.subtotal_paise,
    v_price.delivery_fee_paise,
    v_price.platform_fee_paise,
    v_price.discount_paise,
    v_price.tax_paise,
    v_price.total_paise,
    v_price.currency_code,
    v_price.calculation_details || pg_catalog.jsonb_build_object(
      'securityCoordinator', 'DASTAK_V1',
      'retailMerchantCount', v_retail -> 'retailMerchantCount'
    )
  );

  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, actor_id, reason, metadata
  ) values (
    v_order.id,
    'MATCHING',
    'FULLY_SECURED',
    v_order.version,
    'coordinateFullySecured',
    p_actor_id,
    'Every required fulfilment and delivery feasibility check passed.',
    pg_catalog.jsonb_build_object('retail', v_retail, 'food', v_food)
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_order.id::text || ':ORDER_FULLY_SECURED:' || v_order.version::text,
    'ORDER',
    v_order.id,
    v_order.version,
    'ORDER_FULLY_SECURED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'status', 'FULLY_SECURED',
      'version', v_order.version,
      'fullySecuredAt', v_now,
      'retailMerchantCount', v_retail -> 'retailMerchantCount'
    )
  );

  insert into dastak_v1.payments (
    order_id, customer_id, status, amount_paise, currency_code,
    reserved_at, expires_at
  ) values (
    v_order.id,
    v_order.customer_id,
    'RESERVED',
    v_price.total_paise,
    v_price.currency_code,
    v_now,
    v_payment_expires_at
  )
  returning id into v_payment_id;

  update dastak_v1.orders
  set status = 'AWAITING_PAYMENT',
      payment_expires_at = v_payment_expires_at,
      version = version + 1
  where id = v_order.id
  returning * into v_order;

  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, actor_id, reason, metadata
  ) values (
    v_order.id,
    'FULLY_SECURED',
    'AWAITING_PAYMENT',
    v_order.version,
    'startPaymentReservation',
    p_actor_id,
    'Authoritative payment reservation window started.',
    pg_catalog.jsonb_build_object(
      'paymentId', v_payment_id,
      'amountPaise', v_price.total_paise,
      'currencyCode', v_price.currency_code,
      'expiresAt', v_payment_expires_at
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_order.id::text || ':PAYMENT_WINDOW_STARTED:' || v_order.version::text,
    'ORDER',
    v_order.id,
    v_order.version,
    'PAYMENT_WINDOW_STARTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'paymentId', v_payment_id,
      'status', 'AWAITING_PAYMENT',
      'version', v_order.version,
      'amountPaise', v_price.total_paise,
      'currencyCode', v_price.currency_code,
      'expiresAt', v_payment_expires_at
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'ORDER_FULLY_SECURED_AND_PAYMENT_RESERVED',
    'order',
    v_order.id,
    pg_catalog.jsonb_build_object(
      'fromVersion', v_from_version,
      'version', v_order.version,
      'paymentId', v_payment_id,
      'paymentExpiresAt', v_payment_expires_at,
      'retail', v_retail,
      'food', v_food
    )
  );

  return pg_catalog.jsonb_build_object(
    'coordinated', true,
    'orderId', v_order.id,
    'status', v_order.status,
    'version', v_order.version,
    'paymentId', v_payment_id,
    'amountPaise', v_price.total_paise,
    'currencyCode', v_price.currency_code,
    'paymentExpiresAt', v_payment_expires_at
  );
end;
$$;

create function dastak_v1.coordinate_wave1_after_capacity_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_wave dastak_v1.matching_wave;
begin
  select fulfilment.order_id, opportunity.wave
  into v_order_id, v_wave
  from dastak_v1.fulfilments fulfilment
  join dastak_v1.merchant_opportunities opportunity
    on opportunity.id = fulfilment.source_opportunity_id
  where fulfilment.id = new.fulfilment_id;

  if v_wave = 'WAVE_1' then
    perform dastak_v1_api.coordinate_fully_secured(v_order_id, null);
  end if;
  return new;
end;
$$;

create trigger retail_capacity_slots_coordinate_wave1
after insert on dastak_v1.retail_capacity_slots
for each row execute function dastak_v1.coordinate_wave1_after_capacity_insert();

create function dastak_v1_api.lock_best_wave2_plan(
  p_attempt_id uuid,
  p_actor_id uuid default null,
  p_force boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_plan dastak_v1.fulfilment_plans%rowtype;
  v_merchant record;
  v_fulfilment_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_configuration jsonb;
  v_transport jsonb;
  v_route_distance bigint;
  v_invalid_reason text;
  v_held_capacity integer;
  v_coordination jsonb;
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

  if v_attempt.wave <> 'WAVE_2' then
    raise exception using errcode = '22023', message = 'attempt is not Wave 2';
  end if;
  if v_attempt.status = 'WON' then
    return true;
  end if;
  if v_attempt.status <> 'OPEN' or v_order.status <> 'MATCHING' then
    return false;
  end if;
  if not p_force and v_now >= v_attempt.expires_at then
    return false;
  end if;
  if not p_force and exists (
    select 1
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status = 'OFFERED'
  ) then
    return false;
  end if;

  perform dastak_v1_api.record_wave2_candidate_plans(v_attempt.id);
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(v_order.id);

  for v_plan in
    select plan.*
    from dastak_v1.fulfilment_plans plan
    where plan.matching_attempt_id = v_attempt.id
      and plan.status = 'CANDIDATE'
    order by
      plan.merchant_count,
      plan.route_distance_meters,
      plan.reliability_score_bps desc,
      plan.fingerprint,
      plan.id
    for update
  loop
    v_invalid_reason := null;

    perform branch.id
    from dastak_v1.merchant_branches branch
    join dastak_v1.fulfilment_plan_merchants plan_merchant
      on plan_merchant.branch_id = branch.id
    where plan_merchant.plan_id = v_plan.id
    order by branch.id
    for update;

    perform hold.id
    from dastak_v1.wave2_provisional_holds hold
    join dastak_v1.fulfilment_plan_lines plan_line
      on plan_line.provisional_hold_id = hold.id
    where plan_line.plan_id = v_plan.id
    order by hold.id
    for update;

    if (
      select count(*)
      from dastak_v1.fulfilment_plan_merchants plan_merchant
      where plan_merchant.plan_id = v_plan.id
    ) <> v_plan.merchant_count
      or (
        select count(*)
        from dastak_v1.fulfilment_plan_lines plan_line
        where plan_line.plan_id = v_plan.id
      ) <> v_plan.retail_line_count then
      v_invalid_reason := 'PLAN_COVERAGE_INVALID';
    elsif exists (
      select 1
      from dastak_v1.fulfilment_plan_lines plan_line
      join dastak_v1.order_lines order_line
        on order_line.id = plan_line.order_line_id
      join dastak_v1.wave2_provisional_holds hold
        on hold.id = plan_line.provisional_hold_id
      join dastak_v1.merchant_opportunities opportunity
        on opportunity.id = hold.opportunity_id
      where plan_line.plan_id = v_plan.id
        and (
          order_line.order_id <> v_order.id
          or order_line.line_type <> 'RETAIL_SKU'
          or plan_line.allocated_quantity <> order_line.quantity
          or hold.order_line_id <> order_line.id
          or hold.branch_id <> plan_line.branch_id
          or hold.held_quantity <> order_line.quantity
          or hold.status <> 'HELD'
          or hold.expires_at <= v_now
          or opportunity.status <> 'PROVISIONALLY_ACCEPTED'
        )
    ) then
      v_invalid_reason := 'PROVISIONAL_HOLD_INVALID';
    elsif exists (
      select 1
      from dastak_v1.fulfilment_plan_merchants plan_merchant
      join dastak_v1.merchant_branches branch
        on branch.id = plan_merchant.branch_id
      join dastak_v1.merchant_organizations organization
        on organization.id = branch.organization_id
      left join dastak_v1.branch_operational_states operating
        on operating.branch_id = branch.id
      where plan_merchant.plan_id = v_plan.id
        and (
          organization.status <> 'ACTIVE'
          or organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
          or branch.status <> 'ACTIVE'
          or operating.branch_id is null
          or not operating.is_open
          or not operating.accepting_orders
        )
    ) then
      v_invalid_reason := 'BRANCH_ELIGIBILITY_LOST';
    elsif exists (
      select 1
      from dastak_v1.fulfilment_plan_lines plan_line
      join dastak_v1.order_lines order_line
        on order_line.id = plan_line.order_line_id
      where plan_line.plan_id = v_plan.id
        and not exists (
          select 1
          from dastak_v1.merchant_sku_selections selection
          where selection.branch_id = plan_line.branch_id
            and selection.sku_id = order_line.sku_id
            and selection.state = 'SELECTED'
        )
    ) then
      v_invalid_reason := 'MERCHANT_SKU_SELECTION_LOST';
    end if;

    if v_invalid_reason is null then
      for v_merchant in
        select plan_merchant.branch_id
        from dastak_v1.fulfilment_plan_merchants plan_merchant
        where plan_merchant.plan_id = v_plan.id
        order by plan_merchant.branch_id
      loop
        select count(*) into v_held_capacity
        from dastak_v1.retail_capacity_slots slot
        where slot.branch_id = v_merchant.branch_id
          and slot.status = 'HELD';

        if v_held_capacity >= (
          select branch.capacity_limit
          from dastak_v1.merchant_branches branch
          where branch.id = v_merchant.branch_id
        ) then
          v_invalid_reason := 'BRANCH_CAPACITY_LOST';
          exit;
        end if;
      end loop;
    end if;

    if v_invalid_reason is null and not (v_transport ->> 'feasible')::boolean then
      v_invalid_reason := 'TRANSPORT_LOAD_INFEASIBLE';
    end if;

    -- Recompute the route from locked branch rows; the persisted evaluation is
    -- evidence, not authority at final lock.
    if v_invalid_reason is null then
      v_route_distance := dastak_v1_api.pickup_route_distance_meters(
        v_order.id,
        array(
          select plan_merchant.branch_id
          from dastak_v1.fulfilment_plan_merchants plan_merchant
          where plan_merchant.plan_id = v_plan.id
          order by plan_merchant.branch_id
        )
      );
      if v_route_distance is null
        or v_route_distance > (v_configuration ->> 'maxPickupRouteMeters')::bigint then
        v_invalid_reason := 'PICKUP_ROUTE_INFEASIBLE';
      end if;
    end if;

    if v_invalid_reason is not null then
      update dastak_v1.fulfilment_plans
      set status = 'REJECTED',
          rejected_at = v_now,
          rejection_reason = v_invalid_reason,
          version = version + 1
      where id = v_plan.id;
      continue;
    end if;

    for v_merchant in
      select
        plan_merchant.branch_id,
        plan_merchant.opportunity_id,
        opportunity.organization_id,
        opportunity.promised_prep_minutes
      from dastak_v1.fulfilment_plan_merchants plan_merchant
      join dastak_v1.merchant_opportunities opportunity
        on opportunity.id = plan_merchant.opportunity_id
      where plan_merchant.plan_id = v_plan.id
      order by plan_merchant.branch_id
    loop
      v_fulfilment_id := gen_random_uuid();

      insert into dastak_v1.fulfilments (
        id, order_id, organization_id, branch_id, source_opportunity_id,
        fulfilment_type, status, promised_prep_minutes, committed_at
      ) values (
        v_fulfilment_id,
        v_order.id,
        v_merchant.organization_id,
        v_merchant.branch_id,
        v_merchant.opportunity_id,
        'RETAIL',
        'RESERVED_PREPAYMENT',
        v_merchant.promised_prep_minutes,
        v_now
      );

      insert into dastak_v1.fulfilment_lines (
        fulfilment_id, order_line_id, confirmed_quantity
      )
      select
        v_fulfilment_id,
        plan_line.order_line_id,
        plan_line.allocated_quantity
      from dastak_v1.fulfilment_plan_lines plan_line
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
      order by plan_line.order_line_id;

      insert into dastak_v1.inventory_holds (
        fulfilment_id, order_line_id, branch_id, held_quantity,
        status, held_at
      )
      select
        v_fulfilment_id,
        plan_line.order_line_id,
        v_merchant.branch_id,
        plan_line.allocated_quantity,
        'HELD',
        v_now
      from dastak_v1.fulfilment_plan_lines plan_line
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
      order by plan_line.order_line_id;

      insert into dastak_v1.retail_capacity_slots (
        branch_id, fulfilment_id, status, held_at
      ) values (
        v_merchant.branch_id, v_fulfilment_id, 'HELD', v_now
      );

      insert into dastak_v1.retail_line_allocations (
        order_line_id, merchant_branch_id, allocated_quantity, status
      )
      select
        plan_line.order_line_id,
        v_merchant.branch_id,
        plan_line.allocated_quantity,
        'SELECTED'
      from dastak_v1.fulfilment_plan_lines plan_line
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
      order by plan_line.order_line_id;

      update dastak_v1.wave2_provisional_holds hold
      set status = 'SELECTED',
          selected_at = v_now,
          final_inventory_hold_id = final_hold.id,
          version = hold.version + 1
      from dastak_v1.fulfilment_plan_lines plan_line
      join dastak_v1.inventory_holds final_hold
        on final_hold.fulfilment_id = v_fulfilment_id
        and final_hold.order_line_id = plan_line.order_line_id
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
        and hold.id = plan_line.provisional_hold_id
        and hold.status = 'HELD';
    end loop;

    update dastak_v1.wave2_provisional_holds hold
    set status = 'RELEASED',
        released_at = v_now,
        release_reason = 'NOT_SELECTED_IN_FINAL_PLAN',
        version = hold.version + 1
    where hold.matching_attempt_id = v_attempt.id
      and hold.status = 'HELD';

    update dastak_v1.merchant_opportunities opportunity
    set status = 'SELECTED', version = opportunity.version + 1
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status = 'PROVISIONALLY_ACCEPTED'
      and exists (
        select 1
        from dastak_v1.fulfilment_plan_merchants plan_merchant
        where plan_merchant.plan_id = v_plan.id
          and plan_merchant.opportunity_id = opportunity.id
      );

    update dastak_v1.merchant_opportunities opportunity
    set status = case
          when opportunity.status = 'PROVISIONALLY_ACCEPTED' then 'RELEASED'::dastak_v1.merchant_opportunity_status
          else 'INVALIDATED'::dastak_v1.merchant_opportunity_status
        end,
        version = opportunity.version + 1
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status in ('PROVISIONALLY_ACCEPTED', 'OFFERED');

    update dastak_v1.fulfilment_plans plan
    set status = 'REJECTED',
        rejected_at = v_now,
        rejection_reason = 'BETTER_PLAN_SELECTED',
        version = plan.version + 1
    where plan.matching_attempt_id = v_attempt.id
      and plan.id <> v_plan.id
      and plan.status = 'CANDIDATE';

    update dastak_v1.fulfilment_plans
    set status = 'LOCKED', locked_at = v_now, version = version + 1
    where id = v_plan.id;

    update dastak_v1.matching_attempts
    set status = 'WON', closed_at = v_now, version = version + 1
    where id = v_attempt.id;

    update dastak_v1.order_lines
    set status = 'RESERVED', version = version + 1
    where order_id = v_order.id
      and line_type = 'RETAIL_SKU'
      and status = 'ORDERED';

    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_plan.id::text || ':WAVE_2_PLAN_LOCKED:2',
      'FULFILMENT_PLAN',
      v_plan.id,
      2,
      'WAVE_2_PLAN_LOCKED',
      p_actor_id,
      pg_catalog.jsonb_build_object(
        'planId', v_plan.id,
        'attemptId', v_attempt.id,
        'orderId', v_order.id,
        'merchantCount', v_plan.merchant_count,
        'routeDistanceMeters', v_route_distance,
        'reliabilityScoreBps', v_plan.reliability_score_bps,
        'advertisingInfluence', false
      )
    );

    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_actor_id,
      'WAVE_2_PLAN_LOCKED',
      'fulfilment_plan',
      v_plan.id,
      pg_catalog.jsonb_build_object(
        'attemptId', v_attempt.id,
        'orderId', v_order.id,
        'merchantCount', v_plan.merchant_count,
        'routeDistanceMeters', v_route_distance,
        'reliabilityScoreBps', v_plan.reliability_score_bps,
        'physicalHoldsConverted', true,
        'capacityRevalidated', true
      )
    );

    v_coordination := dastak_v1_api.coordinate_fully_secured(v_order.id, p_actor_id);
    if v_order.order_type = 'RETAIL_ONLY'
      and not coalesce((v_coordination ->> 'coordinated')::boolean, false) then
      raise exception using
        errcode = '55000',
        message = 'FULLY_SECURED_COORDINATION_FAILED',
        detail = v_coordination::text;
    end if;

    return true;
  end loop;

  return false;
end;
$$;

create function dastak_v1_api.fail_wave2_attempt(
  p_attempt_id uuid,
  p_reason text,
  p_actor_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_holds integer := 0;
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

  if v_attempt.wave <> 'WAVE_2' then
    raise exception using errcode = '22023', message = 'attempt is not Wave 2';
  end if;
  if v_attempt.status <> 'OPEN' or v_order.status <> 'MATCHING' then
    return false;
  end if;

  perform opportunity.id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.matching_attempt_id = v_attempt.id
  order by opportunity.id
  for update;

  perform hold.id
  from dastak_v1.wave2_provisional_holds hold
  where hold.matching_attempt_id = v_attempt.id
  order by hold.id
  for update;

  update dastak_v1.wave2_provisional_holds hold
  set status = 'RELEASED',
      released_at = v_now,
      release_reason = p_reason,
      version = hold.version + 1
  where hold.matching_attempt_id = v_attempt.id
    and hold.status = 'HELD';
  get diagnostics v_holds = row_count;

  update dastak_v1.merchant_opportunities opportunity
  set status = case
        when opportunity.status = 'PROVISIONALLY_ACCEPTED'
          then 'RELEASED'::dastak_v1.merchant_opportunity_status
        else 'EXPIRED'::dastak_v1.merchant_opportunity_status
      end,
      version = opportunity.version + 1
  where opportunity.matching_attempt_id = v_attempt.id
    and opportunity.status in ('PROVISIONALLY_ACCEPTED', 'OFFERED');

  update dastak_v1.fulfilment_plans plan
  set status = 'REJECTED',
      rejected_at = v_now,
      rejection_reason = p_reason,
      version = plan.version + 1
  where plan.matching_attempt_id = v_attempt.id
    and plan.status = 'CANDIDATE';

  update dastak_v1.matching_attempts
  set status = 'EXPIRED', closed_at = v_now, version = version + 1
  where id = v_attempt.id;

  update dastak_v1.orders
  set status = 'UNAVAILABLE', version = version + 1
  where id = v_order.id
  returning * into v_order;

  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, actor_id, reason, metadata
  ) values (
    v_order.id,
    'MATCHING',
    'UNAVAILABLE',
    v_order.version,
    'failWave2Attempt',
    p_actor_id,
    p_reason,
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt.id,
      'provisionalHoldsReleased', v_holds
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values
  (
    v_attempt.id::text || ':WAVE_2_HOLD_RELEASED:' || (v_attempt.version + 1)::text,
    'MATCHING_ATTEMPT',
    v_attempt.id,
    v_attempt.version + 1,
    'WAVE_2_HOLD_RELEASED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt.id,
      'orderId', v_order.id,
      'releasedHoldCount', v_holds,
      'reason', p_reason
    )
  ),
  (
    v_order.id::text || ':ORDER_UNAVAILABLE:' || v_order.version::text,
    'ORDER',
    v_order.id,
    v_order.version,
    'ORDER_UNAVAILABLE',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'status', 'UNAVAILABLE',
      'version', v_order.version,
      'reason', p_reason
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'WAVE_2_FAILED',
    'matching_attempt',
    v_attempt.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'reason', p_reason,
      'provisionalHoldsReleased', v_holds
    )
  );

  return true;
end;
$$;

create function dastak_v1_api.expire_wave2_attempt(p_attempt_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
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

  if v_attempt.wave <> 'WAVE_2' then
    raise exception using errcode = '22023', message = 'attempt is not Wave 2';
  end if;
  if v_attempt.status <> 'OPEN' or v_order.status <> 'MATCHING'
    or v_now < v_attempt.expires_at then
    return false;
  end if;

  update dastak_v1.merchant_opportunities opportunity
  set status = 'EXPIRED', version = opportunity.version + 1
  where opportunity.matching_attempt_id = v_attempt.id
    and opportunity.status = 'OFFERED';

  if dastak_v1_api.lock_best_wave2_plan(v_attempt.id, null, true) then
    return true;
  end if;

  return dastak_v1_api.fail_wave2_attempt(
    v_attempt.id, 'WAVE_2_EXPIRED_WITHOUT_VALID_PLAN', null
  );
end;
$$;

create function dastak_v1_api.process_due_wave2_attempts(p_limit integer default 100)
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
    where attempt.wave = 'WAVE_2'
      and attempt.status = 'OPEN'
      and attempt.expires_at <= pg_catalog.clock_timestamp()
    order by attempt.expires_at, attempt.id
    limit p_limit
  loop
    if dastak_v1_api.expire_wave2_attempt(v_attempt_id) then
      v_processed := v_processed + 1;
    end if;
  end loop;

  return v_processed;
end;
$$;

create function dastak_v1_api.accept_wave2_opportunity(
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
  v_command constant text := 'acceptWave2Opportunity';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_attempt_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_prep_options jsonb;
  v_evaluation jsonb;
  v_configuration jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
  v_locked boolean := false;
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
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
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

  -- Global lock order: order, attempt, opportunity, branch, then holds.
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
  if v_order.status <> 'MATCHING' or v_order.paid_at is not null
    or v_attempt.wave <> 'WAVE_2' or v_attempt.status <> 'OPEN'
    or v_opportunity.wave <> 'WAVE_2' or v_opportunity.status <> 'OFFERED' then
    raise exception using errcode = '55000', message = 'matching opportunity is no longer open';
  end if;
  if v_now >= v_attempt.expires_at or v_now >= v_opportunity.expires_at then
    raise exception using errcode = '55000', message = 'matching opportunity has expired';
  end if;

  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_prep_options := dastak_v1_api.retail_prep_options(
    v_branch.id, v_branch.organization_id, v_branch.service_zone_id
  );
  if not v_prep_options @> pg_catalog.jsonb_build_array(p_promised_prep_minutes) then
    raise exception using errcode = '22023', message = 'promised preparation time is not allowed';
  end if;

  v_evaluation := dastak_v1_api.evaluate_wave2_candidate(v_order.id, v_branch.id);
  if not (v_evaluation ->> 'eligible')::boolean then
    raise exception using errcode = '55000', message = 'branch is no longer eligible for this order';
  end if;

  if not exists (
    select 1
    from dastak_v1.merchant_opportunity_lines opportunity_line
    where opportunity_line.opportunity_id = v_opportunity.id
  ) or exists (
    select 1
    from dastak_v1.merchant_opportunity_lines opportunity_line
    where opportunity_line.opportunity_id = v_opportunity.id
      and not exists (
        select 1
        from dastak_v1.order_lines order_line
        join dastak_v1.merchant_sku_selections selection
          on selection.branch_id = v_branch.id
          and selection.sku_id = order_line.sku_id
          and selection.state = 'SELECTED'
        where order_line.id = opportunity_line.order_line_id
          and order_line.order_id = v_order.id
          and order_line.line_type = 'RETAIL_SKU'
          and order_line.sku_id = opportunity_line.sku_id
          and order_line.quantity = opportunity_line.requested_quantity
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'opportunity subset no longer matches the exact canonical order';
  end if;

  update dastak_v1.merchant_opportunities
  set status = 'PROVISIONALLY_ACCEPTED',
      promised_prep_minutes = p_promised_prep_minutes,
      responded_by = p_actor_id,
      responded_at = v_now,
      version = version + 1
  where id = v_opportunity.id;

  insert into dastak_v1.wave2_provisional_holds (
    opportunity_id, matching_attempt_id, order_id, order_line_id,
    branch_id, held_quantity, status, held_at, expires_at
  )
  select
    v_opportunity.id,
    v_attempt.id,
    v_order.id,
    opportunity_line.order_line_id,
    v_branch.id,
    opportunity_line.requested_quantity,
    'HELD',
    v_now,
    v_now + pg_catalog.make_interval(
      secs => (v_configuration ->> 'wave2HoldSeconds')::integer
    )
  from dastak_v1.merchant_opportunity_lines opportunity_line
  where opportunity_line.opportunity_id = v_opportunity.id
  order by opportunity_line.order_line_id;

  perform dastak_v1_api.record_wave2_candidate_plans(v_attempt.id);

  if not exists (
    select 1
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status = 'OFFERED'
  ) then
    v_locked := dastak_v1_api.lock_best_wave2_plan(v_attempt.id, p_actor_id, true);
    if not v_locked then
      perform dastak_v1_api.fail_wave2_attempt(
        v_attempt.id, 'NO_VALID_COMPLETE_WAVE_2_PLAN', p_actor_id
      );
    end if;
  end if;

  select opportunity.* into v_opportunity
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_opportunity.id::text || ':WAVE_2_PROVISIONAL_ACCEPTED:'
      || v_opportunity.version::text,
    'MERCHANT_OPPORTUNITY',
    v_opportunity.id,
    v_opportunity.version,
    'WAVE_2_PROVISIONAL_ACCEPTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'opportunityId', v_opportunity.id,
      'attemptId', v_attempt.id,
      'orderId', v_order.id,
      'branchId', v_branch.id,
      'promisedPrepMinutes', p_promised_prep_minutes,
      'physicalStockConfirmed', true,
      'capacityConsumed', false,
      'finalPlanLocked', v_locked
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'WAVE_2_OPPORTUNITY_PROVISIONALLY_ACCEPTED',
    'merchant_opportunity',
    v_opportunity.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'attemptId', v_attempt.id,
      'branchId', v_branch.id,
      'idempotencyKey', p_idempotency_key,
      'physicalStockConfirmed', true,
      'capacityConsumed', false,
      'finalPlanLocked', v_locked
    )
  );

  v_response := dastak_v1_api.merchant_opportunity_json(
    p_actor_id, v_opportunity.id
  ) || pg_catalog.jsonb_build_object('finalPlanLocked', v_locked);

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_opportunity.id
  );

  return v_response;
end;
$$;

create function dastak_v1_api.decline_wave2_opportunity(
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
  v_command constant text := 'declineWave2Opportunity';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_attempt_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_locked boolean := false;
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
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
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
  if v_order.status <> 'MATCHING' or v_attempt.wave <> 'WAVE_2'
    or v_attempt.status <> 'OPEN' or v_opportunity.wave <> 'WAVE_2'
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

  if not exists (
    select 1
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status = 'OFFERED'
  ) then
    v_locked := dastak_v1_api.lock_best_wave2_plan(v_attempt.id, p_actor_id, true);
    if not v_locked then
      perform dastak_v1_api.fail_wave2_attempt(
        v_attempt.id, 'NO_VALID_COMPLETE_WAVE_2_PLAN', p_actor_id
      );
    end if;
  end if;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
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
      'branchId', v_opportunity.branch_id,
      'finalPlanLocked', v_locked
    )
  );

  v_response := dastak_v1_api.merchant_opportunity_json(
    p_actor_id, v_opportunity.id
  ) || pg_catalog.jsonb_build_object('finalPlanLocked', v_locked);

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_opportunity.id
  );

  return v_response;
end;
$$;

create function dastak_v1.release_step2_resources_after_cancellation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if new.status = 'CANCELLED_PREPAYMENT'
    and old.status is distinct from new.status then
    update dastak_v1.wave2_provisional_holds hold
    set status = 'RELEASED',
        released_at = v_now,
        release_reason = 'CUSTOMER_CANCELLED_PREPAYMENT',
        version = hold.version + 1
    where hold.order_id = new.id
      and hold.status = 'HELD';

    update dastak_v1.merchant_opportunities opportunity
    set status = 'RELEASED', version = opportunity.version + 1
    where opportunity.order_id = new.id
      and opportunity.wave = 'WAVE_2'
      and opportunity.status = 'PROVISIONALLY_ACCEPTED';

    update dastak_v1.fulfilment_plans plan
    set status = 'REJECTED',
        rejected_at = v_now,
        rejection_reason = 'CUSTOMER_CANCELLED_PREPAYMENT',
        version = plan.version + 1
    where plan.order_id = new.id
      and plan.status = 'CANDIDATE';

    update dastak_v1.payment_attempts attempt
    set status = 'EXPIRED',
        expired_at = v_now,
        version = attempt.version + 1
    where attempt.order_id = new.id
      and attempt.status in ('CREATED', 'PROVIDER_READY');

    update dastak_v1.payments payment
    set status = 'CANCELLED',
        cancelled_at = v_now,
        version = payment.version + 1
    where payment.order_id = new.id
      and payment.status = 'RESERVED';
  end if;
  return new;
end;
$$;

create trigger orders_release_step2_after_cancellation
after update of status on dastak_v1.orders
for each row execute function dastak_v1.release_step2_resources_after_cancellation();

create function dastak_v1_api.expire_payment_reservation(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_release jsonb;
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
  for update;
  if not found then
    return false;
  end if;

  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.order_id = v_order.id
  for update;
  if not found then
    return false;
  end if;

  if v_order.status <> 'AWAITING_PAYMENT'
    or v_payment.status <> 'RESERVED'
    or v_now < v_payment.expires_at then
    return false;
  end if;

  v_release := dastak_v1_api.release_order_prepayment_resources(
    v_order.id,
    null,
    v_order.version + 1,
    'PAYMENT_RESERVATION_EXPIRED'
  );

  update dastak_v1.payment_attempts attempt
  set status = 'EXPIRED',
      expired_at = v_now,
      version = attempt.version + 1
  where attempt.payment_id = v_payment.id
    and attempt.status in ('CREATED', 'PROVIDER_READY');

  update dastak_v1.payments
  set status = 'EXPIRED',
      expired_at = v_now,
      version = version + 1
  where id = v_payment.id;

  update dastak_v1.orders
  set status = 'PAYMENT_EXPIRED', version = version + 1
  where id = v_order.id
  returning * into v_order;

  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, reason, metadata
  ) values (
    v_order.id,
    'AWAITING_PAYMENT',
    'PAYMENT_EXPIRED',
    v_order.version,
    'expirePaymentReservation',
    'The authoritative payment reservation window expired unpaid.',
    pg_catalog.jsonb_build_object(
      'paymentId', v_payment.id,
      'expiredAt', v_now,
      'resourceRelease', v_release
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_order.id::text || ':PAYMENT_RESERVATION_EXPIRED:' || v_order.version::text,
    'ORDER',
    v_order.id,
    v_order.version,
    'PAYMENT_RESERVATION_EXPIRED',
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'paymentId', v_payment.id,
      'status', 'PAYMENT_EXPIRED',
      'version', v_order.version,
      'expiredAt', v_now,
      'resourceRelease', v_release
    )
  );

  insert into dastak_v1.audit_events (
    action, resource_type, resource_id, metadata
  ) values (
    'PAYMENT_RESERVATION_EXPIRED',
    'order',
    v_order.id,
    pg_catalog.jsonb_build_object(
      'paymentId', v_payment.id,
      'version', v_order.version,
      'resourceRelease', v_release
    )
  );

  return true;
end;
$$;

create function dastak_v1_api.process_due_payment_reservations(p_limit integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_processed integer := 0;
begin
  if p_limit is null or p_limit not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'limit must be between 1 and 1000';
  end if;

  for v_order_id in
    select payment.order_id
    from dastak_v1.payments payment
    where payment.status = 'RESERVED'
      and payment.expires_at <= pg_catalog.clock_timestamp()
    order by payment.expires_at, payment.order_id
    limit p_limit
  loop
    if dastak_v1_api.expire_payment_reservation(v_order_id) then
      v_processed := v_processed + 1;
    end if;
  end loop;

  return v_processed;
end;
$$;

create function dastak_v1_api.payment_attempt_json(p_attempt_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'attemptId', attempt.id,
    'paymentId', attempt.payment_id,
    'entityId', attempt.order_id,
    'orderId', attempt.order_id,
    'status', attempt.status,
    'amountPaise', attempt.amount_paise,
    'currency', attempt.currency_code,
    'receipt', attempt.provider_receipt,
    'providerOrderId', attempt.provider_order_reference,
    'providerPaymentId', attempt.provider_payment_reference,
    'failureCode', attempt.failure_code,
    'paymentExpiresAt', payment.expires_at,
    'reservationActive', payment.status = 'RESERVED'
      and payment.expires_at > pg_catalog.clock_timestamp()
  )
  from dastak_v1.payment_attempts attempt
  join dastak_v1.payments payment on payment.id = attempt.payment_id
  where attempt.id = p_attempt_id;
$$;

create function dastak_v1_api.prepare_razorpay_checkout(
  p_actor_id uuid,
  p_order_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_existing dastak_v1.payment_attempts%rowtype;
  v_attempt_id uuid := gen_random_uuid();
  v_request_hash bytea;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if p_actor_id is null or not exists (
    select 1
    from public.accounts account
    join private.account_memberships membership
      on membership.account_id = account.id
    where account.id = p_actor_id
      and membership.role = 'customer'
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
  ) then
    raise exception using errcode = '42501', message = 'active customer access required';
  end if;
  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object('orderId', p_order_id, 'provider', 'RAZORPAY')
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':prepareV1RazorpayCheckout:' || p_idempotency_key, 0
    )
  );

  select attempt.* into v_existing
  from dastak_v1.payment_attempts attempt
  where attempt.customer_id = p_actor_id
    and attempt.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return dastak_v1_api.payment_attempt_json(v_existing.id);
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
    and customer_order.customer_id = p_actor_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.order_id = v_order.id
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'payment reservation does not exist';
  end if;

  if v_order.status <> 'AWAITING_PAYMENT'
    or v_payment.status <> 'RESERVED'
    or v_now >= v_payment.expires_at then
    raise exception using errcode = '55000', message = 'payment reservation is not active';
  end if;

  insert into dastak_v1.payment_attempts (
    id, payment_id, order_id, customer_id, status,
    idempotency_key, request_hash, amount_paise, currency_code,
    provider, provider_receipt
  ) values (
    v_attempt_id,
    v_payment.id,
    v_order.id,
    p_actor_id,
    'CREATED',
    p_idempotency_key,
    v_request_hash,
    v_payment.amount_paise,
    v_payment.currency_code,
    'RAZORPAY',
    'dskv1_' || pg_catalog.replace(v_attempt_id::text, '-', '')
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'PAYMENT_ATTEMPT_CREATED',
    'payment_attempt',
    v_attempt_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'paymentId', v_payment.id,
      'amountPaise', v_payment.amount_paise,
      'currencyCode', v_payment.currency_code,
      'idempotencyKey', p_idempotency_key
    )
  );

  return dastak_v1_api.payment_attempt_json(v_attempt_id);
end;
$$;

create function dastak_v1_api.attach_razorpay_order(
  p_actor_id uuid,
  p_attempt_id uuid,
  p_provider_order_reference text,
  p_amount_paise bigint,
  p_currency text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_identity record;
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_attempt dastak_v1.payment_attempts%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select attempt.order_id, attempt.payment_id
  into v_identity
  from dastak_v1.payment_attempts attempt
  where attempt.id = p_attempt_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment attempt not found';
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
  where attempt.id = p_attempt_id
  for update;

  if v_attempt.customer_id <> p_actor_id
    or v_order.customer_id <> p_actor_id then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if p_provider_order_reference !~ '^order_[A-Za-z0-9]+$'
    or pg_catalog.char_length(p_provider_order_reference) > 200 then
    raise exception using errcode = '22023', message = 'invalid provider order reference';
  end if;
  if p_amount_paise <> v_attempt.amount_paise
    or p_currency <> v_attempt.currency_code then
    raise exception using errcode = '22023', message = 'payment amount mismatch';
  end if;

  if v_attempt.status = 'PROVIDER_READY' then
    if v_attempt.provider_order_reference = p_provider_order_reference then
      return dastak_v1_api.payment_attempt_json(v_attempt.id);
    end if;
    raise exception using errcode = '23505', message = 'provider order reference conflict';
  end if;
  if v_attempt.status <> 'CREATED'
    or v_order.status <> 'AWAITING_PAYMENT'
    or v_payment.status <> 'RESERVED'
    or v_now >= v_payment.expires_at then
    raise exception using errcode = '55000', message = 'payment attempt is no longer attachable';
  end if;

  update dastak_v1.payment_attempts
  set status = 'PROVIDER_READY',
      provider_order_reference = p_provider_order_reference,
      provider_ready_at = v_now,
      version = version + 1
  where id = v_attempt.id;

  return dastak_v1_api.payment_attempt_json(v_attempt.id);
end;
$$;

create function dastak_v1_api.mark_payment_attempt_failed(
  p_actor_id uuid,
  p_attempt_id uuid,
  p_failure_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_identity record;
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_attempt dastak_v1.payment_attempts%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_failure text := pg_catalog.upper(
    pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_failure_code, '')), '[^A-Za-z0-9_]+', '_', 'g')
  );
begin
  if pg_catalog.char_length(v_failure) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'invalid payment failure code';
  end if;

  if auth.uid() is not null and p_actor_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select attempt.order_id, attempt.payment_id
  into v_identity
  from dastak_v1.payment_attempts attempt
  where attempt.id = p_attempt_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment attempt not found';
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
  where attempt.id = p_attempt_id
  for update;

  if p_actor_id is not null and (
    v_attempt.customer_id <> p_actor_id or v_order.customer_id <> p_actor_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  if v_attempt.status = 'FAILED' then
    return dastak_v1_api.payment_attempt_json(v_attempt.id);
  end if;
  if v_attempt.status not in ('CREATED', 'PROVIDER_READY')
    or v_payment.status <> 'RESERVED' then
    raise exception using errcode = '55000', message = 'payment attempt can no longer fail';
  end if;

  update dastak_v1.payment_attempts
  set status = 'FAILED',
      failure_code = v_failure,
      failed_at = v_now,
      version = version + 1
  where id = v_attempt.id;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_attempt.id::text || ':PAYMENT_ATTEMPT_FAILED:' || (v_attempt.version + 1)::text,
    'PAYMENT_ATTEMPT',
    v_attempt.id,
    v_attempt.version + 1,
    'PAYMENT_ATTEMPT_FAILED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt.id,
      'orderId', v_order.id,
      'failureCode', v_failure,
      'reservationStillActive', v_payment.expires_at > v_now
    )
  );

  return dastak_v1_api.payment_attempt_json(v_attempt.id);
end;
$$;

create function dastak_v1_api.record_razorpay_payment_event(
  p_provider_event_id text,
  p_event_type text,
  p_provider_order_reference text,
  p_provider_payment_reference text,
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
  v_existing dastak_v1.payment_provider_events%rowtype;
  v_identity record;
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_attempt dastak_v1.payment_attempts%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
  v_outcome dastak_v1.payment_event_outcome;
  v_status integer;
  v_reconciliation_id uuid;
begin
  if p_provider_event_id is null
    or pg_catalog.char_length(p_provider_event_id) not between 1 and 200
    or p_event_type <> 'payment_captured'
    or p_provider_order_reference !~ '^order_[A-Za-z0-9]+$'
    or p_provider_payment_reference !~ '^pay_[A-Za-z0-9]+$'
    or p_amount_paise is null or p_amount_paise <= 0
    or p_occurred_at is null
    or p_request_digest !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid Razorpay payment event';
  end if;

  -- The provider event row does not exist on first delivery, so serialize by
  -- event identity before checking it. Concurrent webhook retries then share
  -- the same idempotent response instead of racing the primary-key insert.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'dastak-v1-razorpay-event:' || p_provider_event_id,
      0
    )
  );

  select event.* into v_existing
  from dastak_v1.payment_provider_events event
  where event.provider = 'RAZORPAY'
    and event.provider_event_id = p_provider_event_id;

  if found then
    if v_existing.request_digest <> p_request_digest
      or v_existing.provider_order_reference <> p_provider_order_reference
      or v_existing.provider_payment_reference <> p_provider_payment_reference
      or v_existing.amount_paise <> p_amount_paise then
      raise exception using
        errcode = '22023',
        message = 'provider event id was reused with different payment data';
    end if;
    response_body := v_existing.response_body;
    response_status := case v_existing.outcome
      when 'LATE_SUCCESS' then 202
      when 'REJECTED' then 409
      else 200
    end;
    return next;
    return;
  end if;

  select attempt.id, attempt.order_id, attempt.payment_id
  into v_identity
  from dastak_v1.payment_attempts attempt
  where attempt.provider_order_reference = p_provider_order_reference;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'payment_not_found',
        'message', 'No Dastak V1 payment attempt matched this provider order.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  -- Paid and expiry commands serialize on the same order/payment rows.
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
  where attempt.id = v_identity.id
  for update;

  if v_payment.status = 'RESERVED'
    and v_order.status = 'AWAITING_PAYMENT'
    and v_now >= v_payment.expires_at then
    perform dastak_v1_api.expire_payment_reservation(v_order.id);
    select customer_order.* into v_order
    from dastak_v1.orders customer_order
    where customer_order.id = v_identity.order_id;
    select payment.* into v_payment
    from dastak_v1.payments payment
    where payment.id = v_identity.payment_id;
    select attempt.* into v_attempt
    from dastak_v1.payment_attempts attempt
    where attempt.id = v_identity.id;
  end if;

  if p_amount_paise <> v_payment.amount_paise then
    v_outcome := 'REJECTED';
    v_status := 409;
    v_response := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'payment_amount_mismatch',
        'message', 'Captured payment amount does not match the authoritative order total.'
      ),
      'orderId', v_order.id
    );

    insert into dastak_v1.payment_reconciliation_cases (
      order_id, payment_id, payment_attempt_id, source_provider_event_id,
      provider_payment_reference, amount_paise, currency_code, reason
    ) values (
      v_order.id,
      v_payment.id,
      v_attempt.id,
      p_provider_event_id,
      p_provider_payment_reference,
      p_amount_paise,
      'INR',
      'CAPTURED_AMOUNT_MISMATCH'
    )
    on conflict (provider_payment_reference) do nothing
    returning id into v_reconciliation_id;
  elsif v_payment.status = 'SUCCEEDED'
    and v_order.status = 'PAID'
    and v_payment.provider_payment_reference = p_provider_payment_reference then
    v_outcome := 'DUPLICATE';
    v_status := 200;
    v_response := pg_catalog.jsonb_build_object(
      'received', true,
      'processed', true,
      'duplicate', true,
      'orderId', v_order.id,
      'status', 'PAID'
    );
  elsif v_payment.status <> 'RESERVED'
    or v_order.status <> 'AWAITING_PAYMENT' then
    v_outcome := 'LATE_SUCCESS';
    v_status := 202;

    if v_attempt.status in ('PROVIDER_READY', 'FAILED', 'EXPIRED') then
      update dastak_v1.payment_attempts
      set status = 'LATE_SUCCESS',
          provider_payment_reference = p_provider_payment_reference,
          succeeded_at = coalesce(p_occurred_at, v_now),
          version = version + 1
      where id = v_attempt.id;
    end if;

    insert into dastak_v1.payment_reconciliation_cases (
      order_id, payment_id, payment_attempt_id, source_provider_event_id,
      provider_payment_reference, amount_paise, currency_code, reason
    ) values (
      v_order.id,
      v_payment.id,
      v_attempt.id,
      p_provider_event_id,
      p_provider_payment_reference,
      p_amount_paise,
      'INR',
      case
        when v_order.status = 'PAYMENT_EXPIRED' then 'LATE_SUCCESS_AFTER_PAYMENT_EXPIRED'
        when v_order.status = 'CANCELLED_PREPAYMENT' then 'SUCCESS_AFTER_CUSTOMER_CANCELLATION'
        else 'DUPLICATE_CAPTURE_AFTER_PAYMENT_FINALIZED'
      end
    )
    on conflict (provider_payment_reference) do nothing
    returning id into v_reconciliation_id;

    v_response := pg_catalog.jsonb_build_object(
      'received', true,
      'processed', true,
      'orderId', v_order.id,
      'status', v_order.status,
      'lateSuccess', true,
      'reconciliationRequired', true,
      'reconciliationCaseId', v_reconciliation_id
    );

    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, payload
    ) values (
      v_order.id::text || ':PAYMENT_LATE_SUCCESS:' || p_provider_payment_reference,
      'ORDER',
      v_order.id,
      v_order.version,
      'PAYMENT_LATE_SUCCESS_RECONCILIATION_REQUIRED',
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'paymentId', v_payment.id,
        'paymentAttemptId', v_attempt.id,
        'providerPaymentReference', p_provider_payment_reference,
        'reconciliationCaseId', v_reconciliation_id,
        'orderStatusPreserved', v_order.status
      )
    );
  else
    v_outcome := 'SUCCEEDED';
    v_status := 200;

    update dastak_v1.payment_attempts
    set status = 'SUCCEEDED',
        provider_payment_reference = p_provider_payment_reference,
        succeeded_at = coalesce(p_occurred_at, v_now),
        failed_at = null,
        failure_code = null,
        version = version + 1
    where id = v_attempt.id;

    update dastak_v1.payment_attempts attempt
    set status = 'EXPIRED',
        expired_at = v_now,
        version = attempt.version + 1
    where attempt.payment_id = v_payment.id
      and attempt.id <> v_attempt.id
      and attempt.status in ('CREATED', 'PROVIDER_READY');

    update dastak_v1.payments
    set status = 'SUCCEEDED',
        succeeded_at = coalesce(p_occurred_at, v_now),
        provider_payment_reference = p_provider_payment_reference,
        version = version + 1
    where id = v_payment.id;

    update dastak_v1.orders
    set status = 'PAID',
        paid_at = coalesce(p_occurred_at, v_now),
        version = version + 1
    where id = v_order.id
    returning * into v_order;

    insert into dastak_v1.order_price_snapshots (
      order_id, snapshot_kind, subtotal_paise, delivery_fee_paise,
      platform_fee_paise, discount_paise, tax_paise, total_paise,
      currency_code, calculation_details
    )
    select
      price_snapshot.order_id,
      'PAID',
      price_snapshot.subtotal_paise,
      price_snapshot.delivery_fee_paise,
      price_snapshot.platform_fee_paise,
      price_snapshot.discount_paise,
      price_snapshot.tax_paise,
      price_snapshot.total_paise,
      price_snapshot.currency_code,
      price_snapshot.calculation_details || pg_catalog.jsonb_build_object(
        'provider', 'RAZORPAY',
        'paymentAttemptId', v_attempt.id
      )
    from dastak_v1.order_price_snapshots price_snapshot
    where price_snapshot.order_id = v_order.id
      and price_snapshot.snapshot_kind = 'FULLY_SECURED';

    insert into dastak_v1.order_state_journal (
      order_id, from_status, to_status, order_version,
      command_name, reason, metadata
    ) values (
      v_order.id,
      'AWAITING_PAYMENT',
      'PAID',
      v_order.version,
      'recordRazorpayPaymentEvent',
      'Authoritative provider capture confirmed within the reservation window.',
      pg_catalog.jsonb_build_object(
        'paymentId', v_payment.id,
        'paymentAttemptId', v_attempt.id,
        'providerEventId', p_provider_event_id,
        'providerPaymentReference', p_provider_payment_reference
      )
    );

    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, payload
    ) values (
      v_order.id::text || ':PAYMENT_CONFIRMED:' || v_order.version::text,
      'ORDER',
      v_order.id,
      v_order.version,
      'PAYMENT_CONFIRMED',
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'paymentId', v_payment.id,
        'paymentAttemptId', v_attempt.id,
        'status', 'PAID',
        'version', v_order.version,
        'paidAt', v_order.paid_at,
        'provider', 'RAZORPAY'
      )
    );

    insert into dastak_v1.audit_events (
      action, resource_type, resource_id, metadata
    ) values (
      'PAYMENT_CONFIRMED',
      'order',
      v_order.id,
      pg_catalog.jsonb_build_object(
        'paymentId', v_payment.id,
        'paymentAttemptId', v_attempt.id,
        'providerEventId', p_provider_event_id,
        'providerPaymentReference', p_provider_payment_reference,
        'version', v_order.version
      )
    );

    v_response := pg_catalog.jsonb_build_object(
      'received', true,
      'processed', true,
      'duplicate', false,
      'orderId', v_order.id,
      'status', 'PAID',
      'paidAt', v_order.paid_at
    );
  end if;

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
    v_outcome,
    v_response
  );

  response_body := v_response;
  response_status := v_status;
  return next;
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
  select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'id', customer_order.id,
    'displayOrderNumber', customer_order.display_order_number,
    'orderType', customer_order.order_type,
    'status', customer_order.status,
    'customerState', case customer_order.status
      when 'MATCHING' then 'FINDING_ITEMS'
      when 'FULLY_SECURED' then 'ORDER_SECURED'
      when 'AWAITING_PAYMENT' then 'PAYMENT_READY'
      when 'PAID' then 'PAYMENT_CONFIRMED'
      when 'PAYMENT_EXPIRED' then 'PAYMENT_EXPIRED'
      when 'UNAVAILABLE' then 'UNAVAILABLE'
      when 'CANCELLED_PREPAYMENT' then 'CANCELLED'
      else customer_order.status::text
    end,
    'version', customer_order.version,
    'fulfilmentProgress', case
      when customer_order.status = 'MATCHING' then
        pg_catalog.jsonb_build_object(
          'state', 'FINDING_ITEMS',
          'title', 'Finding your items…'
        )
      when customer_order.status in ('FULLY_SECURED', 'AWAITING_PAYMENT') then
        pg_catalog.jsonb_build_object(
          'state', 'ORDER_SECURED',
          'title', 'Your order is secured'
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
    'payment', (
      select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'status', payment.status,
        'amountPaise', payment.amount_paise,
        'currencyCode', payment.currency_code,
        'reservedAt', payment.reserved_at,
        'expiresAt', payment.expires_at,
        'secondsRemaining', greatest(
          0,
          pg_catalog.floor(
            extract(epoch from (payment.expires_at - pg_catalog.clock_timestamp()))
          )::integer
        ),
        'canAttempt', payment.status = 'RESERVED'
          and customer_order.status = 'AWAITING_PAYMENT'
          and payment.expires_at > pg_catalog.clock_timestamp(),
        'canRetry', payment.status = 'RESERVED'
          and customer_order.status = 'AWAITING_PAYMENT'
          and payment.expires_at > pg_catalog.clock_timestamp(),
        'latestAttempt', (
          select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'id', attempt.id,
            'status', attempt.status,
            'failureCode', attempt.failure_code,
            'createdAt', attempt.created_at,
            'failedAt', attempt.failed_at,
            'succeededAt', attempt.succeeded_at
          ))
          from dastak_v1.payment_attempts attempt
          where attempt.payment_id = payment.id
          order by attempt.created_at desc, attempt.id desc
          limit 1
        )
      ))
      from dastak_v1.payments payment
      where payment.order_id = customer_order.id
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
  ))
  from dastak_v1.orders customer_order
  join dastak_v1.order_context_snapshots context_snapshot
    on context_snapshot.order_id = customer_order.id
  where customer_order.id = p_order_id
    and customer_order.customer_id = p_customer_id;
$$;

create or replace function dastak_v1_api.merchant_opportunity_json(
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
  v_order dastak_v1.orders%rowtype;
  v_hold_expires_at timestamptz;
  v_capacity_consumed boolean;
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
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_opportunity.order_id;

  select max(hold.expires_at) into v_hold_expires_at
  from dastak_v1.wave2_provisional_holds hold
  where hold.opportunity_id = v_opportunity.id
    and hold.status = 'HELD';

  select exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    join dastak_v1.retail_capacity_slots slot
      on slot.fulfilment_id = fulfilment.id
      and slot.status = 'HELD'
    where fulfilment.source_opportunity_id = v_opportunity.id
      and fulfilment.status = 'RESERVED_PREPAYMENT'
  ) into v_capacity_consumed;

  return pg_catalog.jsonb_build_object(
    'id', v_opportunity.id,
    'displayOrderNumber', v_order.display_order_number,
    'requestScope', case v_opportunity.wave
      when 'WAVE_1' then 'FULL_BASKET'
      else 'REQUESTED_SUBSET'
    end,
    'status', v_opportunity.status,
    'reservationState', case
      when v_opportunity.status = 'PROVISIONALLY_ACCEPTED' then 'ITEMS_HELD_WHILE_ORDER_COMPLETES'
      when v_opportunity.status = 'SELECTED' and v_order.status = 'AWAITING_PAYMENT'
        then 'WAITING_FOR_CUSTOMER_PAYMENT'
      when v_opportunity.status = 'SELECTED' and v_order.status = 'PAID'
        then 'PAYMENT_CONFIRMED'
      when v_opportunity.status in ('RELEASED', 'EXPIRED', 'LOST', 'INVALIDATED')
        or v_order.status in ('PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT', 'UNAVAILABLE')
        then 'RESERVATION_RELEASED'
      else 'AWAITING_RESPONSE'
    end,
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
        extract(epoch from (v_opportunity.expires_at - pg_catalog.statement_timestamp()))
      )::integer
    ),
    'provisionalHoldExpiresAt', v_hold_expires_at,
    'promisedPrepMinutes', v_opportunity.promised_prep_minutes,
    'prepTimeOptionsMinutes', dastak_v1_api.retail_prep_options(
      v_branch.id, v_branch.organization_id, v_branch.service_zone_id
    ),
    'physicalConfirmationRequired', v_opportunity.status = 'OFFERED',
    'capacityConsumed', v_capacity_consumed,
    'orderPaymentState', case v_order.status
      when 'AWAITING_PAYMENT' then 'WAITING_FOR_CUSTOMER_PAYMENT'
      when 'PAID' then 'PAID'
      when 'PAYMENT_EXPIRED' then 'PAYMENT_EXPIRED'
      when 'CANCELLED_PREPAYMENT' then 'CANCELLED'
      else null
    end,
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'orderLineId', opportunity_line.order_line_id,
            'skuId', opportunity_line.sku_id,
            'name', opportunity_line.product_name_snapshot,
            'variant', opportunity_line.variant_snapshot,
            'packSize', opportunity_line.pack_size_snapshot,
            'quantity', opportunity_line.requested_quantity
          ))
          order by opportunity_line.created_at, opportunity_line.order_line_id
        )
        from dastak_v1.merchant_opportunity_lines opportunity_line
        where opportunity_line.opportunity_id = v_opportunity.id
      ),
      '[]'::jsonb
    )
  );
end;
$$;

create function dastak_v1_api.admin_execution_orders(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.orders.trace'
  );
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'limit must be between 1 and 100';
  end if;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, metadata
  ) values (
    p_actor_id,
    'ADMIN_EXECUTION_ORDERS_READ',
    'order_collection',
    pg_catalog.jsonb_build_object('limit', p_limit)
  );

  return pg_catalog.jsonb_build_object(
    'orders', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', selected.id,
        'displayOrderNumber', selected.display_order_number,
        'status', selected.status,
        'version', selected.version,
        'submittedAt', selected.submitted_at,
        'fullySecuredAt', selected.fully_secured_at,
        'paymentExpiresAt', selected.payment_expires_at,
        'paidAt', selected.paid_at,
        'updatedAt', selected.updated_at
      ) order by selected.updated_at desc, selected.id desc)
      from (
        select customer_order.*
        from dastak_v1.orders customer_order
        order by customer_order.updated_at desc, customer_order.id desc
        limit p_limit
      ) selected
    ), '[]'::jsonb)
  );
end;
$$;

create function dastak_v1_api.admin_execution_trace(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.orders.trace'
  );

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'ADMIN_EXECUTION_TRACE_READ',
    'order',
    v_order.id,
    pg_catalog.jsonb_build_object('orderVersion', v_order.version)
  );

  return pg_catalog.jsonb_build_object(
    'order', pg_catalog.jsonb_build_object(
      'id', v_order.id,
      'displayOrderNumber', v_order.display_order_number,
      'status', v_order.status,
      'version', v_order.version,
      'submittedAt', v_order.submitted_at,
      'fullySecuredAt', v_order.fully_secured_at,
      'paymentExpiresAt', v_order.payment_expires_at,
      'paidAt', v_order.paid_at
    ),
    'matchingAttempts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', attempt.id,
        'wave', attempt.wave,
        'status', attempt.status,
        'startedAt', attempt.started_at,
        'expiresAt', attempt.expires_at,
        'closedAt', attempt.closed_at,
        'version', attempt.version,
        'opportunities', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'id', opportunity.id,
            'branchId', opportunity.branch_id,
            'branchName', branch.display_name,
            'status', opportunity.status,
            'version', opportunity.version,
            'promisedPrepMinutes', opportunity.promised_prep_minutes,
            'respondedAt', opportunity.responded_at,
            'lineCount', (
              select count(*)
              from dastak_v1.merchant_opportunity_lines line
              where line.opportunity_id = opportunity.id
            ),
            'activeProvisionalHoldCount', (
              select count(*)
              from dastak_v1.wave2_provisional_holds hold
              where hold.opportunity_id = opportunity.id and hold.status = 'HELD'
            )
          ) order by opportunity.started_at, opportunity.id)
          from dastak_v1.merchant_opportunities opportunity
          join dastak_v1.merchant_branches branch on branch.id = opportunity.branch_id
          where opportunity.matching_attempt_id = attempt.id
        ), '[]'::jsonb)
      ) order by attempt.started_at, attempt.id)
      from dastak_v1.matching_attempts attempt
      where attempt.order_id = v_order.id
    ), '[]'::jsonb),
    'provisionalHolds', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', hold.id,
        'opportunityId', hold.opportunity_id,
        'orderLineId', hold.order_line_id,
        'branchId', hold.branch_id,
        'quantity', hold.held_quantity,
        'status', hold.status,
        'heldAt', hold.held_at,
        'expiresAt', hold.expires_at,
        'selectedAt', hold.selected_at,
        'releasedAt', hold.released_at,
        'releaseReason', hold.release_reason
      ) order by hold.held_at, hold.id)
      from dastak_v1.wave2_provisional_holds hold
      where hold.order_id = v_order.id
    ), '[]'::jsonb),
    'plans', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', plan.id,
        'status', plan.status,
        'merchantCount', plan.merchant_count,
        'retailLineCount', plan.retail_line_count,
        'routeDistanceMeters', plan.route_distance_meters,
        'reliabilityScoreBps', plan.reliability_score_bps,
        'feasibility', plan.feasibility_snapshot,
        'lockedAt', plan.locked_at,
        'rejectedAt', plan.rejected_at,
        'rejectionReason', plan.rejection_reason,
        'branches', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'branchId', plan_merchant.branch_id,
            'branchName', branch.display_name,
            'opportunityId', plan_merchant.opportunity_id,
            'reliabilityScoreBps', plan_merchant.reliability_score_bps
          ) order by plan_merchant.branch_id)
          from dastak_v1.fulfilment_plan_merchants plan_merchant
          join dastak_v1.merchant_branches branch on branch.id = plan_merchant.branch_id
          where plan_merchant.plan_id = plan.id
        ), '[]'::jsonb)
      ) order by plan.merchant_count, plan.route_distance_meters, plan.id)
      from dastak_v1.fulfilment_plans plan
      where plan.order_id = v_order.id
    ), '[]'::jsonb),
    'capacity', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'branchId', selected_branch.id,
        'branchName', selected_branch.display_name,
        'capacityLimit', selected_branch.capacity_limit,
        'activeSlots', (
          select count(*)
          from dastak_v1.retail_capacity_slots slot
          where slot.branch_id = selected_branch.id and slot.status = 'HELD'
        )
      ) order by selected_branch.id)
      from (
        select distinct branch.id, branch.display_name, branch.capacity_limit
        from dastak_v1.merchant_branches branch
        join dastak_v1.merchant_opportunities opportunity
          on opportunity.branch_id = branch.id
        where opportunity.order_id = v_order.id
      ) selected_branch
    ), '[]'::jsonb),
    'payment', (
      select pg_catalog.jsonb_build_object(
        'id', payment.id,
        'status', payment.status,
        'amountPaise', payment.amount_paise,
        'currencyCode', payment.currency_code,
        'reservedAt', payment.reserved_at,
        'expiresAt', payment.expires_at,
        'succeededAt', payment.succeeded_at,
        'expiredAt', payment.expired_at,
        'attempts', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'id', attempt.id,
            'status', attempt.status,
            'providerOrderReference', attempt.provider_order_reference,
            'providerPaymentReference', attempt.provider_payment_reference,
            'failureCode', attempt.failure_code,
            'createdAt', attempt.created_at,
            'succeededAt', attempt.succeeded_at,
            'expiredAt', attempt.expired_at
          ) order by attempt.created_at, attempt.id)
          from dastak_v1.payment_attempts attempt
          where attempt.payment_id = payment.id
        ), '[]'::jsonb),
        'providerEvents', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'providerEventId', event.provider_event_id,
            'eventType', event.event_type,
            'outcome', event.outcome,
            'providerPaymentReference', event.provider_payment_reference,
            'processedAt', event.processed_at
          ) order by event.processed_at, event.provider_event_id)
          from dastak_v1.payment_provider_events event
          where event.payment_id = payment.id
        ), '[]'::jsonb)
      )
      from dastak_v1.payments payment
      where payment.order_id = v_order.id
    ),
    'reconciliationCases', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', reconciliation.id,
        'status', reconciliation.status,
        'reason', reconciliation.reason,
        'providerPaymentReference', reconciliation.provider_payment_reference,
        'amountPaise', reconciliation.amount_paise,
        'openedAt', reconciliation.opened_at,
        'resolvedAt', reconciliation.resolved_at
      ) order by reconciliation.opened_at, reconciliation.id)
      from dastak_v1.payment_reconciliation_cases reconciliation
      where reconciliation.order_id = v_order.id
    ), '[]'::jsonb)
  );
end;
$$;

create function public.dastak_v1_accept_wave2_opportunity(
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
  select dastak_v1_api.accept_wave2_opportunity(
    auth.uid(), p_opportunity_id, p_idempotency_key,
    p_expected_version, p_promised_prep_minutes
  );
$$;

create function public.dastak_v1_decline_wave2_opportunity(
  p_opportunity_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.decline_wave2_opportunity(
    auth.uid(), p_opportunity_id, p_idempotency_key, p_expected_version
  );
$$;

create function public.dastak_v1_prepare_razorpay_checkout(
  p_account_id uuid,
  p_order_id uuid,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.prepare_razorpay_checkout(
    p_account_id, p_order_id, p_idempotency_key
  );
$$;

create function public.dastak_v1_attach_razorpay_order(
  p_account_id uuid,
  p_attempt_id uuid,
  p_provider_order_reference text,
  p_amount_paise bigint,
  p_currency text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.attach_razorpay_order(
    p_account_id, p_attempt_id, p_provider_order_reference,
    p_amount_paise, p_currency
  );
$$;

create function public.dastak_v1_mark_payment_attempt_failed(
  p_account_id uuid,
  p_attempt_id uuid,
  p_failure_code text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.mark_payment_attempt_failed(
    p_account_id, p_attempt_id, p_failure_code
  );
$$;

create function public.dastak_v1_report_payment_attempt_failed(
  p_attempt_id uuid,
  p_failure_code text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.mark_payment_attempt_failed(
    auth.uid(), p_attempt_id, p_failure_code
  );
$$;

create function public.dastak_v1_record_razorpay_event(
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

create function public.dastak_v1_admin_execution_orders(p_limit integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_execution_orders(auth.uid(), p_limit);
$$;

create function public.dastak_v1_admin_execution_trace(p_order_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_execution_trace(auth.uid(), p_order_id);
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
    where namespace.nspname = 'dastak_v1'
      and function_row.proname in (
        'set_merchant_opportunity_wave',
        'guard_wave2_provisional_hold',
        'guard_fulfilment_plan',
        'guard_payment',
        'guard_payment_attempt',
        'guard_payment_reconciliation_case',
        'enforce_retail_capacity_insert',
        'coordinate_wave1_after_capacity_insert',
        'release_step2_resources_after_cancellation',
        'is_valid_default_sku_logistics',
        'is_valid_transport_load_profiles'
      )
  loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      v_function
    );
  end loop;

  for v_function in
    select function_row.oid::regprocedure
    from pg_catalog.pg_proc function_row
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function_row.pronamespace
    where namespace.nspname = 'dastak_v1_api'
      and function_row.proname in (
        'wave2_global_configuration',
        'branch_reliability_bps',
        'order_transport_snapshot',
        'branch_customer_distance_meters',
        'branch_distance_meters',
        'pickup_route_distance_meters',
        'evaluate_wave2_candidate',
        'start_wave2',
        'record_wave2_candidate_plans',
        'retail_security_snapshot',
        'food_security_snapshot',
        'coordinate_fully_secured',
        'lock_best_wave2_plan',
        'fail_wave2_attempt',
        'expire_wave2_attempt',
        'process_due_wave2_attempts',
        'accept_wave2_opportunity',
        'decline_wave2_opportunity',
        'expire_payment_reservation',
        'process_due_payment_reservations',
        'payment_attempt_json',
        'prepare_razorpay_checkout',
        'attach_razorpay_order',
        'mark_payment_attempt_failed',
        'record_razorpay_payment_event',
        'admin_execution_orders',
        'admin_execution_trace'
      )
  loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      v_function
    );
  end loop;
end;
$$;

revoke execute on function public.dastak_v1_accept_wave2_opportunity(
  uuid, text, bigint, integer
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_decline_wave2_opportunity(
  uuid, text, bigint
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_prepare_razorpay_checkout(
  uuid, uuid, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_attach_razorpay_order(
  uuid, uuid, text, bigint, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_mark_payment_attempt_failed(
  uuid, uuid, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_report_payment_attempt_failed(
  uuid, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_record_razorpay_event(
  text, text, text, text, text, bigint, timestamptz, text
) from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_admin_execution_orders(integer)
  from public, anon, authenticated, service_role;
revoke execute on function public.dastak_v1_admin_execution_trace(uuid)
  from public, anon, authenticated, service_role;

grant execute on function dastak_v1_api.accept_wave2_opportunity(
  uuid, uuid, text, bigint, integer
) to authenticated;
grant execute on function dastak_v1_api.decline_wave2_opportunity(
  uuid, uuid, text, bigint
) to authenticated;
grant execute on function dastak_v1_api.mark_payment_attempt_failed(
  uuid, uuid, text
) to authenticated, service_role;
grant execute on function dastak_v1_api.admin_execution_orders(uuid, integer)
  to authenticated;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  to authenticated;

grant execute on function dastak_v1_api.start_wave2(uuid, uuid) to service_role;
grant execute on function dastak_v1_api.coordinate_fully_secured(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.expire_wave2_attempt(uuid) to service_role;
grant execute on function dastak_v1_api.process_due_wave2_attempts(integer)
  to service_role;
grant execute on function dastak_v1_api.expire_payment_reservation(uuid)
  to service_role;
grant execute on function dastak_v1_api.process_due_payment_reservations(integer)
  to service_role;
grant execute on function dastak_v1_api.prepare_razorpay_checkout(uuid, uuid, text)
  to service_role;
grant execute on function dastak_v1_api.attach_razorpay_order(
  uuid, uuid, text, bigint, text
) to service_role;
grant execute on function dastak_v1_api.record_razorpay_payment_event(
  text, text, text, text, bigint, timestamptz, text
) to service_role;

grant execute on function public.dastak_v1_accept_wave2_opportunity(
  uuid, text, bigint, integer
) to authenticated;
grant execute on function public.dastak_v1_decline_wave2_opportunity(
  uuid, text, bigint
) to authenticated;
grant execute on function public.dastak_v1_report_payment_attempt_failed(uuid, text)
  to authenticated;
grant execute on function public.dastak_v1_admin_execution_orders(integer)
  to authenticated;
grant execute on function public.dastak_v1_admin_execution_trace(uuid)
  to authenticated;

grant execute on function public.dastak_v1_prepare_razorpay_checkout(
  uuid, uuid, text
) to service_role;
grant execute on function public.dastak_v1_attach_razorpay_order(
  uuid, uuid, text, bigint, text
) to service_role;
grant execute on function public.dastak_v1_mark_payment_attempt_failed(
  uuid, uuid, text
) to service_role;
grant execute on function public.dastak_v1_record_razorpay_event(
  text, text, text, text, text, bigint, timestamptz, text
) to service_role;

grant execute on function dastak_v1_api.process_due_wave1_attempts(integer)
  to service_role;

comment on table dastak_v1.wave2_provisional_holds is
  'Exact physical Wave 2 confirmations. HELD consumes no final merchant preparation capacity.';
comment on table dastak_v1.fulfilment_plans is
  'Auditable complete-cover Wave 2 plans ranked by merchant count, route and reliability; advertising is excluded.';
comment on table dastak_v1.payments is
  'One authoritative pre-payment reservation lifecycle per Dastak V1 parent order.';
comment on function public.dastak_v1_record_razorpay_event(
  text, text, text, text, text, bigint, timestamptz, text
) is 'Idempotent Dastak V1 Razorpay capture recording. Expired orders never reactivate.';

do $$
declare
  v_job_id bigint;
begin
  select job.jobid into v_job_id
  from cron.job job
  where job.jobname = 'dastak-v1-wave2-expiry';
  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  select job.jobid into v_job_id
  from cron.job job
  where job.jobname = 'dastak-v1-payment-expiry';
  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;
end;
$$;

select cron.schedule(
  'dastak-v1-wave2-expiry',
  '10 seconds',
  'select dastak_v1_api.process_due_wave2_attempts(100);'
);

select cron.schedule(
  'dastak-v1-payment-expiry',
  '10 seconds',
  'select dastak_v1_api.process_due_payment_reservations(100);'
);

notify pgrst, 'reload schema';
