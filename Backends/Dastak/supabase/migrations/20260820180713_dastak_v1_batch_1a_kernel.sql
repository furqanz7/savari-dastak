-- Dastak V1 is additive. Legacy commerce tables remain read-only history and
-- are intentionally not referenced by this domain.
create schema dastak_v1;
create schema dastak_v1_api;

revoke all on schema dastak_v1 from public, anon, authenticated, service_role;
revoke all on schema dastak_v1_api from public, anon, authenticated;
grant usage on schema dastak_v1 to service_role;
grant usage on schema dastak_v1_api to service_role;

alter default privileges in schema dastak_v1
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema dastak_v1
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges in schema dastak_v1
  revoke execute on functions from public, anon, authenticated, service_role;
alter default privileges in schema dastak_v1_api
  revoke execute on functions from public, anon, authenticated, service_role;

create type dastak_v1.merchant_type as enum (
  'RETAIL',
  'RESTAURANT_CAFE',
  'DASTAK_CONVENIENCE_STORE'
);
create type dastak_v1.merchant_status as enum (
  'PENDING_REVIEW', 'ACTIVE', 'SUSPENDED', 'CLOSED'
);
create type dastak_v1.branch_status as enum (
  'PENDING_REVIEW', 'ACTIVE', 'PAUSED', 'SUSPENDED', 'CLOSED'
);
create type dastak_v1.merchant_user_status as enum (
  'INVITED', 'ACTIVE', 'SUSPENDED', 'REVOKED'
);
create type dastak_v1.permission_sensitivity as enum (
  'STANDARD', 'SENSITIVE', 'HIGHLY_SENSITIVE'
);
create type dastak_v1.permission_bundle_scope as enum (
  'MERCHANT', 'PLATFORM'
);
create type dastak_v1.setting_value_type as enum (
  'BOOLEAN', 'INTEGER', 'NUMERIC', 'TEXT', 'DURATION_SECONDS', 'JSON'
);
create type dastak_v1.setting_scope_type as enum (
  'GLOBAL', 'SERVICE_ZONE', 'MERCHANT_ORGANIZATION', 'MERCHANT_BRANCH'
);
create type dastak_v1.catalogue_status as enum (
  'DRAFT', 'ACTIVE', 'INACTIVE'
);
create type dastak_v1.merchant_sku_state as enum (
  'SELECTED', 'UNAVAILABLE', 'DELISTED'
);
create type dastak_v1.order_type as enum (
  'RETAIL_ONLY', 'FOOD_ONLY', 'MIXED'
);
create type dastak_v1.order_status as enum (
  'CREATED',
  'MATCHING',
  'FULLY_SECURED',
  'AWAITING_PAYMENT',
  'PAID',
  'PREPARING',
  'PICKUP_IN_PROGRESS',
  'OUT_FOR_DELIVERY',
  'DELIVERED',
  'UNAVAILABLE',
  'PAYMENT_EXPIRED',
  'CANCELLED_PREPAYMENT',
  'DASTAK_FULFILMENT_FAILURE'
);
create type dastak_v1.order_line_type as enum (
  'RETAIL_SKU', 'FOOD_MENU_ITEM'
);
create type dastak_v1.order_line_status as enum (
  'ORDERED', 'RESERVED', 'FULFILLING', 'RECOVERY', 'FULFILLED', 'REFUNDED'
);
create type dastak_v1.price_snapshot_kind as enum (
  'SUBMITTED', 'FULLY_SECURED', 'PAID', 'FINAL'
);
create type dastak_v1.retail_allocation_status as enum (
  'PROVISIONAL', 'SELECTED', 'RELEASED'
);
create type dastak_v1.outbox_status as enum (
  'PENDING', 'PUBLISHED', 'DEAD_LETTER'
);

create table dastak_v1.merchant_organizations (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null check (char_length(trim(legal_name)) between 1 and 160),
  display_name text not null check (char_length(trim(display_name)) between 1 and 100),
  merchant_type dastak_v1.merchant_type not null,
  status dastak_v1.merchant_status not null default 'PENDING_REVIEW',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create table dastak_v1.merchant_branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references dastak_v1.merchant_organizations(id),
  display_name text not null check (char_length(trim(display_name)) between 1 and 100),
  service_zone_id uuid references public.service_zones(id),
  address_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(address_snapshot) = 'object'),
  location extensions.geometry(Point, 4326),
  capacity_limit integer not null default 5 check (capacity_limit > 0),
  status dastak_v1.branch_status not null default 'PENDING_REVIEW',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (id, organization_id)
);

create index merchant_branches_organization_idx
  on dastak_v1.merchant_branches (organization_id, status);
create index merchant_branches_location_gix
  on dastak_v1.merchant_branches using gist (location);

create table dastak_v1.merchant_users (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references dastak_v1.merchant_organizations(id),
  account_id uuid not null references public.accounts(id),
  status dastak_v1.merchant_user_status not null default 'INVITED',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (organization_id, account_id),
  unique (id, organization_id)
);

create index merchant_users_account_idx
  on dastak_v1.merchant_users (account_id, status);

create table dastak_v1.permission_definitions (
  permission_key text primary key
    check (permission_key ~ '^[a-z][a-z0-9_.]{2,99}$'),
  description text not null check (char_length(trim(description)) between 1 and 240),
  sensitivity dastak_v1.permission_sensitivity not null default 'STANDARD',
  created_at timestamptz not null default now()
);

create table dastak_v1.permission_bundles (
  id uuid primary key default gen_random_uuid(),
  bundle_key text not null unique check (bundle_key ~ '^[a-z][a-z0-9_]{2,79}$'),
  display_name text not null check (char_length(trim(display_name)) between 1 and 100),
  scope dastak_v1.permission_bundle_scope not null,
  description text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create table dastak_v1.permission_bundle_permissions (
  bundle_id uuid not null references dastak_v1.permission_bundles(id),
  permission_key text not null references dastak_v1.permission_definitions(permission_key),
  created_at timestamptz not null default now(),
  primary key (bundle_id, permission_key)
);

create table dastak_v1.merchant_permission_grants (
  id uuid primary key default gen_random_uuid(),
  merchant_user_id uuid not null,
  organization_id uuid not null,
  bundle_id uuid not null references dastak_v1.permission_bundles(id),
  branch_id uuid,
  granted_by uuid not null references public.accounts(id),
  grant_reason text not null check (char_length(trim(grant_reason)) between 3 and 500),
  granted_at timestamptz not null default now(),
  revoked_by uuid references public.accounts(id),
  revoke_reason text check (revoke_reason is null or char_length(trim(revoke_reason)) between 3 and 500),
  revoked_at timestamptz,
  version bigint not null default 1 check (version > 0),
  foreign key (merchant_user_id, organization_id)
    references dastak_v1.merchant_users(id, organization_id),
  foreign key (branch_id, organization_id)
    references dastak_v1.merchant_branches(id, organization_id),
  check (
    (revoked_at is null and revoked_by is null and revoke_reason is null)
    or (revoked_at is not null and revoked_by is not null and revoke_reason is not null)
  )
);

create unique index merchant_permission_grants_active_uidx
  on dastak_v1.merchant_permission_grants (
    merchant_user_id,
    bundle_id,
    coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  where revoked_at is null;
create index merchant_permission_grants_org_idx
  on dastak_v1.merchant_permission_grants (organization_id, merchant_user_id)
  where revoked_at is null;

create table dastak_v1.merchant_permission_grant_history (
  id bigint generated always as identity primary key,
  grant_id uuid not null,
  action text not null check (action in ('GRANTED', 'REVOKED')),
  actor_id uuid not null references public.accounts(id),
  grant_snapshot jsonb not null check (jsonb_typeof(grant_snapshot) = 'object'),
  occurred_at timestamptz not null default now()
);

create table dastak_v1.setting_definitions (
  setting_key text primary key check (setting_key ~ '^[a-z][a-z0-9_.]{2,119}$'),
  value_type dastak_v1.setting_value_type not null,
  description text not null,
  default_value jsonb,
  validation_rules jsonb not null default '{}'::jsonb
    check (jsonb_typeof(validation_rules) = 'object'),
  protected boolean not null default true,
  requires_explicit_value boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (default_value is not null or requires_explicit_value)
);

create table dastak_v1.platform_settings (
  id uuid primary key default gen_random_uuid(),
  setting_key text not null references dastak_v1.setting_definitions(setting_key),
  scope_type dastak_v1.setting_scope_type not null default 'GLOBAL',
  scope_id uuid,
  setting_value jsonb not null,
  updated_by uuid not null references public.accounts(id),
  update_reason text not null check (char_length(trim(update_reason)) between 3 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  check (
    (scope_type = 'GLOBAL' and scope_id is null)
    or (scope_type <> 'GLOBAL' and scope_id is not null)
  )
);

create unique index platform_settings_scope_uidx
  on dastak_v1.platform_settings (
    setting_key,
    scope_type,
    coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table dastak_v1.platform_setting_history (
  id bigint generated always as identity primary key,
  platform_setting_id uuid not null,
  setting_key text not null,
  scope_type dastak_v1.setting_scope_type not null,
  scope_id uuid,
  setting_value jsonb not null,
  version bigint not null,
  actor_id uuid not null references public.accounts(id),
  reason text not null,
  occurred_at timestamptz not null default now()
);

create table dastak_v1.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 100),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  image_key text,
  status dastak_v1.catalogue_status not null default 'DRAFT',
  sort_order integer not null default 0,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create table dastak_v1.subcategories (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references dastak_v1.categories(id),
  name text not null check (char_length(trim(name)) between 1 and 100),
  slug text not null check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  image_key text,
  status dastak_v1.catalogue_status not null default 'DRAFT',
  sort_order integer not null default 0,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  unique (category_id, slug)
);

create table dastak_v1.brands (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 100),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  image_key text,
  status dastak_v1.catalogue_status not null default 'DRAFT',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create table dastak_v1.skus (
  id uuid primary key default gen_random_uuid(),
  subcategory_id uuid not null references dastak_v1.subcategories(id),
  brand_id uuid references dastak_v1.brands(id),
  canonical_name text not null check (char_length(trim(canonical_name)) between 1 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  variant_name text,
  pack_size text not null check (char_length(trim(pack_size)) between 1 and 80),
  description text,
  image_key text,
  list_price_paise bigint not null check (list_price_paise >= 0),
  selling_price_paise bigint not null check (
    selling_price_paise >= 0 and selling_price_paise <= list_price_paise
  ),
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  tax_rate_bps integer not null default 0 check (tax_rate_bps between 0 and 10000),
  status dastak_v1.catalogue_status not null default 'DRAFT',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create index skus_browse_idx
  on dastak_v1.skus (subcategory_id, status, canonical_name);

create table dastak_v1.merchant_sku_selections (
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  sku_id uuid not null references dastak_v1.skus(id),
  state dastak_v1.merchant_sku_state not null default 'SELECTED',
  selected_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  primary key (branch_id, sku_id)
);

create index merchant_sku_selections_sku_idx
  on dastak_v1.merchant_sku_selections (sku_id, state, branch_id);

create sequence dastak_v1.order_number_sequence;

create table dastak_v1.orders (
  id uuid primary key default gen_random_uuid(),
  display_order_number text not null unique,
  customer_id uuid not null references public.accounts(id),
  order_type dastak_v1.order_type not null,
  restaurant_organization_id uuid references dastak_v1.merchant_organizations(id),
  status dastak_v1.order_status not null default 'CREATED',
  submitted_at timestamptz,
  fully_secured_at timestamptz,
  payment_expires_at timestamptz,
  paid_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  check (
    (order_type = 'RETAIL_ONLY' and restaurant_organization_id is null)
    or (order_type in ('FOOD_ONLY', 'MIXED') and restaurant_organization_id is not null)
  ),
  check (paid_at is null or submitted_at is not null),
  check (delivered_at is null or paid_at is not null)
);

create index orders_customer_timeline_idx
  on dastak_v1.orders (customer_id, created_at desc, id desc);
create index orders_status_idx
  on dastak_v1.orders (status, updated_at);

create table dastak_v1.order_context_snapshots (
  order_id uuid primary key references dastak_v1.orders(id),
  delivery_address jsonb not null check (jsonb_typeof(delivery_address) = 'object'),
  recipient jsonb not null check (jsonb_typeof(recipient) = 'object'),
  snapshot_hash bytea not null,
  created_at timestamptz not null default now()
);

create table dastak_v1.order_lines (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  line_type dastak_v1.order_line_type not null,
  sku_id uuid references dastak_v1.skus(id),
  food_menu_item_id uuid,
  restaurant_organization_id uuid references dastak_v1.merchant_organizations(id),
  product_name_snapshot text not null
    check (char_length(trim(product_name_snapshot)) between 1 and 200),
  variant_snapshot text,
  pack_size_snapshot text,
  quantity integer not null check (quantity > 0),
  unit_price_paise bigint not null check (unit_price_paise >= 0),
  tax_rate_bps integer not null default 0 check (tax_rate_bps between 0 and 10000),
  line_total_paise bigint generated always as (quantity::bigint * unit_price_paise) stored,
  status dastak_v1.order_line_status not null default 'ORDERED',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  check (
    (
      line_type = 'RETAIL_SKU'
      and sku_id is not null
      and food_menu_item_id is null
      and restaurant_organization_id is null
    )
    or (
      line_type = 'FOOD_MENU_ITEM'
      and sku_id is null
      and food_menu_item_id is not null
      and restaurant_organization_id is not null
    )
  )
);

create unique index order_lines_retail_sku_uidx
  on dastak_v1.order_lines (order_id, sku_id)
  where line_type = 'RETAIL_SKU';
create unique index order_lines_food_item_uidx
  on dastak_v1.order_lines (order_id, food_menu_item_id)
  where line_type = 'FOOD_MENU_ITEM';
create index order_lines_order_idx on dastak_v1.order_lines (order_id, id);

create table dastak_v1.order_price_snapshots (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  snapshot_kind dastak_v1.price_snapshot_kind not null,
  subtotal_paise bigint not null check (subtotal_paise >= 0),
  delivery_fee_paise bigint not null default 0 check (delivery_fee_paise >= 0),
  platform_fee_paise bigint not null default 0 check (platform_fee_paise >= 0),
  discount_paise bigint not null default 0 check (discount_paise >= 0),
  tax_paise bigint not null default 0 check (tax_paise >= 0),
  total_paise bigint not null check (total_paise >= 0),
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  calculation_details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(calculation_details) = 'object'),
  created_at timestamptz not null default now(),
  unique (order_id, snapshot_kind),
  check (
    total_paise = subtotal_paise + delivery_fee_paise + platform_fee_paise
      + tax_paise - discount_paise
  )
);

create index order_price_snapshots_order_idx
  on dastak_v1.order_price_snapshots (order_id, created_at desc);

-- One row per retail order line makes quantity splitting structurally
-- impossible. Future matching may allocate the whole line or no line.
create table dastak_v1.retail_line_allocations (
  order_line_id uuid primary key references dastak_v1.order_lines(id),
  merchant_branch_id uuid not null references dastak_v1.merchant_branches(id),
  allocated_quantity integer not null check (allocated_quantity > 0),
  status dastak_v1.retail_allocation_status not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create index retail_line_allocations_branch_idx
  on dastak_v1.retail_line_allocations (merchant_branch_id, status);

create table dastak_v1.order_state_journal (
  id bigint generated always as identity primary key,
  order_id uuid not null references dastak_v1.orders(id),
  from_status dastak_v1.order_status,
  to_status dastak_v1.order_status not null,
  order_version bigint not null check (order_version > 0),
  command_name text not null,
  actor_id uuid references public.accounts(id),
  reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  occurred_at timestamptz not null default now(),
  unique (order_id, order_version)
);

create index order_state_journal_order_idx
  on dastak_v1.order_state_journal (order_id, occurred_at, id);

create table dastak_v1.idempotency_records (
  actor_id uuid not null references public.accounts(id),
  command_name text not null check (char_length(trim(command_name)) between 1 and 100),
  idempotency_key text not null check (char_length(idempotency_key) between 1 and 200),
  request_hash bytea not null,
  response_body jsonb not null,
  response_status integer not null check (response_status between 200 and 599),
  resource_id uuid,
  created_at timestamptz not null default now(),
  primary key (actor_id, command_name, idempotency_key)
);

create table dastak_v1.domain_events_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  aggregate_type text not null,
  aggregate_id uuid not null,
  aggregate_version bigint not null check (aggregate_version > 0),
  event_type text not null,
  actor_id uuid references public.accounts(id),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  status dastak_v1.outbox_status not null default 'PENDING',
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  published_at timestamptz,
  occurred_at timestamptz not null default now(),
  unique (aggregate_type, aggregate_id, event_type, aggregate_version)
);

create index domain_events_outbox_pending_idx
  on dastak_v1.domain_events_outbox (available_at, occurred_at)
  where status = 'PENDING';

create table dastak_v1.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references public.accounts(id),
  action text not null,
  resource_type text not null,
  resource_id uuid,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  occurred_at timestamptz not null default now()
);

create index audit_events_resource_idx
  on dastak_v1.audit_events (resource_type, resource_id, occurred_at desc);
create index audit_events_actor_idx
  on dastak_v1.audit_events (actor_id, occurred_at desc);

-- Keep every foreign-key lookup indexed so parent updates, deletes, and
-- advisor checks remain predictable as the V1 domain grows.
create index brands_created_by_idx
  on dastak_v1.brands (created_by);
create index categories_created_by_idx
  on dastak_v1.categories (created_by);
create index domain_events_outbox_actor_idx
  on dastak_v1.domain_events_outbox (actor_id);
create index merchant_branches_created_by_idx
  on dastak_v1.merchant_branches (created_by);
create index merchant_branches_service_zone_idx
  on dastak_v1.merchant_branches (service_zone_id);
create index merchant_organizations_created_by_idx
  on dastak_v1.merchant_organizations (created_by);
create index merchant_permission_grant_history_actor_idx
  on dastak_v1.merchant_permission_grant_history (actor_id);
create index merchant_permission_grants_branch_org_idx
  on dastak_v1.merchant_permission_grants (branch_id, organization_id);
create index merchant_permission_grants_bundle_idx
  on dastak_v1.merchant_permission_grants (bundle_id);
create index merchant_permission_grants_granted_by_idx
  on dastak_v1.merchant_permission_grants (granted_by);
create index merchant_permission_grants_user_org_idx
  on dastak_v1.merchant_permission_grants (merchant_user_id, organization_id);
create index merchant_permission_grants_revoked_by_idx
  on dastak_v1.merchant_permission_grants (revoked_by);
create index merchant_sku_selections_selected_by_idx
  on dastak_v1.merchant_sku_selections (selected_by);
create index merchant_users_created_by_idx
  on dastak_v1.merchant_users (created_by);
create index order_lines_restaurant_org_idx
  on dastak_v1.order_lines (restaurant_organization_id);
create index order_lines_sku_idx
  on dastak_v1.order_lines (sku_id);
create index order_state_journal_actor_idx
  on dastak_v1.order_state_journal (actor_id);
create index orders_restaurant_org_idx
  on dastak_v1.orders (restaurant_organization_id);
create index platform_setting_history_actor_idx
  on dastak_v1.platform_setting_history (actor_id);
create index platform_settings_setting_key_idx
  on dastak_v1.platform_settings (setting_key);
create index platform_settings_updated_by_idx
  on dastak_v1.platform_settings (updated_by);
create index skus_brand_idx
  on dastak_v1.skus (brand_id);
create index skus_created_by_idx
  on dastak_v1.skus (created_by);
create index subcategories_created_by_idx
  on dastak_v1.subcategories (created_by);

create function dastak_v1.reject_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_schema || '.' || tg_table_name;
end;
$$;

create function dastak_v1.reject_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception '% cannot be deleted', tg_table_schema || '.' || tg_table_name;
end;
$$;

create function dastak_v1.is_valid_order_transition(
  p_from dastak_v1.order_status,
  p_to dastak_v1.order_status
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_from
    when 'CREATED' then p_to in ('MATCHING', 'CANCELLED_PREPAYMENT')
    when 'MATCHING' then p_to in ('FULLY_SECURED', 'UNAVAILABLE', 'CANCELLED_PREPAYMENT')
    when 'FULLY_SECURED' then p_to in ('AWAITING_PAYMENT', 'CANCELLED_PREPAYMENT')
    when 'AWAITING_PAYMENT' then p_to in ('PAID', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT')
    when 'PAID' then p_to in ('PREPARING', 'DASTAK_FULFILMENT_FAILURE')
    when 'PREPARING' then p_to in ('PICKUP_IN_PROGRESS', 'DASTAK_FULFILMENT_FAILURE')
    when 'PICKUP_IN_PROGRESS' then p_to in ('OUT_FOR_DELIVERY', 'DASTAK_FULFILMENT_FAILURE')
    when 'OUT_FOR_DELIVERY' then p_to in ('DELIVERED', 'DASTAK_FULFILMENT_FAILURE')
    else false
  end;
$$;

create function dastak_v1.guard_order_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.display_order_number is distinct from old.display_order_number
    or new.customer_id is distinct from old.customer_id
    or new.order_type is distinct from old.order_type
    or new.restaurant_organization_id is distinct from old.restaurant_organization_id
    or new.created_at is distinct from old.created_at
    or new.submitted_at is distinct from old.submitted_at then
    raise exception 'immutable order identity or submission data cannot change';
  end if;

  if new.version <> old.version + 1 then
    raise exception 'order version must increment exactly once';
  end if;

  if new.status is distinct from old.status
    and not dastak_v1.is_valid_order_transition(old.status, new.status) then
    raise exception 'invalid Dastak V1 order transition: % -> %', old.status, new.status;
  end if;

  if new.status = 'CANCELLED_PREPAYMENT'
    and (new.paid_at is not null or old.paid_at is not null) then
    raise exception 'a paid order cannot become CANCELLED_PREPAYMENT';
  end if;

  if new.status = 'PAID' and new.paid_at is null then
    raise exception 'PAID requires paid_at';
  end if;

  if new.status = 'DELIVERED' and new.delivered_at is null then
    raise exception 'DELIVERED requires delivered_at';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create function dastak_v1.is_valid_order_line_transition(
  p_from dastak_v1.order_line_status,
  p_to dastak_v1.order_line_status
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_from
    when 'ORDERED' then p_to = 'RESERVED'
    when 'RESERVED' then p_to = 'FULFILLING'
    when 'FULFILLING' then p_to in ('FULFILLED', 'RECOVERY', 'REFUNDED')
    when 'RECOVERY' then p_to in ('FULFILLED', 'REFUNDED')
    else false
  end;
$$;

create function dastak_v1.guard_order_line_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
begin
  select * into v_order
  from dastak_v1.orders
  where id = new.order_id;

  if not found then
    raise exception 'order does not exist';
  end if;

  if new.line_type = 'RETAIL_SKU' and v_order.order_type = 'FOOD_ONLY' then
    raise exception 'FOOD_ONLY order cannot contain retail lines';
  end if;

  if new.line_type = 'FOOD_MENU_ITEM' then
    if v_order.order_type = 'RETAIL_ONLY' then
      raise exception 'RETAIL_ONLY order cannot contain food lines';
    end if;
    if new.restaurant_organization_id is distinct from v_order.restaurant_organization_id then
      raise exception 'all food lines must belong to the order restaurant group';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
      or new.order_id is distinct from old.order_id
      or new.line_type is distinct from old.line_type
      or new.sku_id is distinct from old.sku_id
      or new.food_menu_item_id is distinct from old.food_menu_item_id
      or new.restaurant_organization_id is distinct from old.restaurant_organization_id
      or new.product_name_snapshot is distinct from old.product_name_snapshot
      or new.variant_snapshot is distinct from old.variant_snapshot
      or new.pack_size_snapshot is distinct from old.pack_size_snapshot
      or new.quantity is distinct from old.quantity
      or new.unit_price_paise is distinct from old.unit_price_paise
      or new.tax_rate_bps is distinct from old.tax_rate_bps
      or new.created_at is distinct from old.created_at then
      raise exception 'order line commercial snapshot cannot change';
    end if;

    if new.version <> old.version + 1 then
      raise exception 'order line version must increment exactly once';
    end if;

    if new.status is distinct from old.status
      and not dastak_v1.is_valid_order_line_transition(old.status, new.status) then
      raise exception 'invalid Dastak V1 order line transition: % -> %', old.status, new.status;
    end if;

    new.updated_at := now();
  end if;

  return new;
end;
$$;

create function dastak_v1.validate_order_composition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_retail_count integer;
  v_food_count integer;
begin
  if tg_table_name = 'orders' then
    v_order_id := coalesce(new.id, old.id);
  else
    v_order_id := coalesce(new.order_id, old.order_id);
  end if;

  select * into v_order from dastak_v1.orders where id = v_order_id;
  if not found then
    return null;
  end if;

  if v_order.restaurant_organization_id is not null
    and not exists (
      select 1
      from dastak_v1.merchant_organizations organization
      where organization.id = v_order.restaurant_organization_id
        and organization.merchant_type = 'RESTAURANT_CAFE'
    ) then
    raise exception 'food orders require a restaurant organization';
  end if;

  select
    count(*) filter (where line_type = 'RETAIL_SKU'),
    count(*) filter (where line_type = 'FOOD_MENU_ITEM')
  into v_retail_count, v_food_count
  from dastak_v1.order_lines
  where order_id = v_order_id;

  if v_order.order_type = 'RETAIL_ONLY' and (v_retail_count = 0 or v_food_count <> 0) then
    raise exception 'RETAIL_ONLY order requires retail lines only';
  elsif v_order.order_type = 'FOOD_ONLY' and (v_food_count = 0 or v_retail_count <> 0) then
    raise exception 'FOOD_ONLY order requires food lines only';
  elsif v_order.order_type = 'MIXED' and (v_food_count = 0 or v_retail_count = 0) then
    raise exception 'MIXED order requires both retail and food lines';
  end if;

  return null;
end;
$$;

create function dastak_v1.guard_retail_line_allocation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line dastak_v1.order_lines%rowtype;
  v_merchant_type dastak_v1.merchant_type;
begin
  select * into v_line
  from dastak_v1.order_lines
  where id = new.order_line_id;

  if not found or v_line.line_type <> 'RETAIL_SKU' then
    raise exception 'only a retail order line can be allocated';
  end if;

  if new.allocated_quantity <> v_line.quantity then
    raise exception 'a retail line must be allocated as its complete quantity';
  end if;

  select organization.merchant_type into v_merchant_type
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
  where branch.id = new.merchant_branch_id;

  if v_merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception 'retail lines can only be allocated to retail branches';
  end if;

  if tg_op = 'UPDATE' then
    if new.order_line_id is distinct from old.order_line_id
      or new.merchant_branch_id is distinct from old.merchant_branch_id
      or new.allocated_quantity is distinct from old.allocated_quantity
      or new.created_at is distinct from old.created_at then
      raise exception 'retail allocation identity and quantity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'retail allocation version must increment exactly once';
    end if;
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create function dastak_v1.guard_outbox_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.event_key is distinct from old.event_key
    or new.aggregate_type is distinct from old.aggregate_type
    or new.aggregate_id is distinct from old.aggregate_id
    or new.aggregate_version is distinct from old.aggregate_version
    or new.event_type is distinct from old.event_type
    or new.actor_id is distinct from old.actor_id
    or new.payload is distinct from old.payload
    or new.occurred_at is distinct from old.occurred_at then
    raise exception 'outbox event content is immutable';
  end if;

  if new.attempts < old.attempts then
    raise exception 'outbox attempts cannot decrease';
  end if;

  return new;
end;
$$;

create function dastak_v1.validate_setting_value(
  p_setting_key text,
  p_value jsonb
)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_definition dastak_v1.setting_definitions%rowtype;
  v_number numeric;
begin
  select * into v_definition
  from dastak_v1.setting_definitions
  where setting_key = p_setting_key;

  if not found or p_value is null then
    return false;
  end if;

  if v_definition.value_type = 'BOOLEAN' and jsonb_typeof(p_value) <> 'boolean' then
    return false;
  elsif v_definition.value_type in ('INTEGER', 'NUMERIC', 'DURATION_SECONDS') then
    if jsonb_typeof(p_value) <> 'number' then
      return false;
    end if;
    v_number := (p_value #>> '{}')::numeric;
    if v_definition.value_type in ('INTEGER', 'DURATION_SECONDS')
      and trunc(v_number) <> v_number then
      return false;
    end if;
    if v_definition.value_type = 'DURATION_SECONDS' and v_number < 0 then
      return false;
    end if;
    if v_definition.validation_rules ? 'minimum'
      and v_number < (v_definition.validation_rules ->> 'minimum')::numeric then
      return false;
    end if;
    if v_definition.validation_rules ? 'maximum'
      and v_number > (v_definition.validation_rules ->> 'maximum')::numeric then
      return false;
    end if;
  elsif v_definition.value_type = 'TEXT' and jsonb_typeof(p_value) <> 'string' then
    return false;
  elsif v_definition.value_type = 'JSON'
    and jsonb_typeof(p_value) not in ('object', 'array') then
    return false;
  end if;

  if v_definition.validation_rules ? 'allowedValues'
    and not (v_definition.validation_rules -> 'allowedValues') @> jsonb_build_array(p_value) then
    return false;
  end if;

  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

create function dastak_v1.guard_platform_setting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not dastak_v1.validate_setting_value(new.setting_key, new.setting_value) then
    raise exception 'invalid value for setting %', new.setting_key;
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
      or new.setting_key is distinct from old.setting_key
      or new.scope_type is distinct from old.scope_type
      or new.scope_id is distinct from old.scope_id
      or new.created_at is distinct from old.created_at then
      raise exception 'setting identity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'setting version must increment exactly once';
    end if;
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create function dastak_v1.record_platform_setting_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into dastak_v1.platform_setting_history (
    platform_setting_id,
    setting_key,
    scope_type,
    scope_id,
    setting_value,
    version,
    actor_id,
    reason
  ) values (
    new.id,
    new.setting_key,
    new.scope_type,
    new.scope_id,
    new.setting_value,
    new.version,
    new.updated_by,
    new.update_reason
  );
  return new;
end;
$$;

create function dastak_v1.guard_merchant_sku_selection()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type dastak_v1.merchant_type;
begin
  select organization.merchant_type into v_type
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
  where branch.id = new.branch_id;

  if v_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception 'only retail branches can select canonical retail SKUs';
  end if;

  if tg_op = 'UPDATE' then
    if new.branch_id is distinct from old.branch_id
      or new.sku_id is distinct from old.sku_id
      or new.created_at is distinct from old.created_at then
      raise exception 'merchant SKU selection identity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'merchant SKU selection version must increment exactly once';
    end if;
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create function dastak_v1.guard_permission_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope dastak_v1.permission_bundle_scope;
begin
  select scope into v_scope
  from dastak_v1.permission_bundles
  where id = new.bundle_id and active;

  if v_scope is null then
    raise exception 'permission bundle is missing or inactive';
  end if;
  if v_scope <> 'MERCHANT' then
    raise exception 'platform permission bundles cannot be granted to merchant users';
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
      or new.merchant_user_id is distinct from old.merchant_user_id
      or new.organization_id is distinct from old.organization_id
      or new.bundle_id is distinct from old.bundle_id
      or new.branch_id is distinct from old.branch_id
      or new.granted_by is distinct from old.granted_by
      or new.grant_reason is distinct from old.grant_reason
      or new.granted_at is distinct from old.granted_at then
      raise exception 'permission grant identity cannot change';
    end if;
    if old.revoked_at is not null then
      raise exception 'a revoked permission grant is immutable';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'permission grant version must increment exactly once';
    end if;
  end if;

  return new;
end;
$$;

create function dastak_v1.record_permission_grant_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into dastak_v1.merchant_permission_grant_history (
    grant_id,
    action,
    actor_id,
    grant_snapshot
  ) values (
    new.id,
    case when new.revoked_at is null then 'GRANTED' else 'REVOKED' end,
    coalesce(new.revoked_by, new.granted_by),
    to_jsonb(new)
  );
  return new;
end;
$$;

create trigger merchant_permission_grants_guard
before insert or update on dastak_v1.merchant_permission_grants
for each row execute function dastak_v1.guard_permission_grant();
create trigger merchant_permission_grants_history
after insert or update on dastak_v1.merchant_permission_grants
for each row execute function dastak_v1.record_permission_grant_history();

create trigger platform_settings_guard
before insert or update on dastak_v1.platform_settings
for each row execute function dastak_v1.guard_platform_setting();
create trigger platform_settings_history
after insert or update on dastak_v1.platform_settings
for each row execute function dastak_v1.record_platform_setting_history();

create trigger merchant_sku_selections_guard
before insert or update on dastak_v1.merchant_sku_selections
for each row execute function dastak_v1.guard_merchant_sku_selection();

create trigger orders_update_guard
before update on dastak_v1.orders
for each row execute function dastak_v1.guard_order_update();
create trigger orders_no_delete
before delete on dastak_v1.orders
for each row execute function dastak_v1.reject_delete();

create trigger order_lines_write_guard
before insert or update on dastak_v1.order_lines
for each row execute function dastak_v1.guard_order_line_write();
create trigger order_lines_no_delete
before delete on dastak_v1.order_lines
for each row execute function dastak_v1.reject_delete();

create constraint trigger orders_composition_guard
after insert or update on dastak_v1.orders
deferrable initially deferred
for each row execute function dastak_v1.validate_order_composition();
create constraint trigger order_lines_composition_guard
after insert or update on dastak_v1.order_lines
deferrable initially deferred
for each row execute function dastak_v1.validate_order_composition();

create trigger retail_line_allocations_guard
before insert or update on dastak_v1.retail_line_allocations
for each row execute function dastak_v1.guard_retail_line_allocation();
create trigger retail_line_allocations_no_delete
before delete on dastak_v1.retail_line_allocations
for each row execute function dastak_v1.reject_delete();

create trigger order_context_snapshots_immutable
before update or delete on dastak_v1.order_context_snapshots
for each row execute function dastak_v1.reject_mutation();
create trigger order_price_snapshots_immutable
before update or delete on dastak_v1.order_price_snapshots
for each row execute function dastak_v1.reject_mutation();
create trigger order_state_journal_immutable
before update or delete on dastak_v1.order_state_journal
for each row execute function dastak_v1.reject_mutation();
create trigger idempotency_records_immutable
before update or delete on dastak_v1.idempotency_records
for each row execute function dastak_v1.reject_mutation();
create trigger merchant_permission_grant_history_immutable
before update or delete on dastak_v1.merchant_permission_grant_history
for each row execute function dastak_v1.reject_mutation();
create trigger platform_setting_history_immutable
before update or delete on dastak_v1.platform_setting_history
for each row execute function dastak_v1.reject_mutation();
create trigger audit_events_immutable
before update or delete on dastak_v1.audit_events
for each row execute function dastak_v1.reject_mutation();
create trigger domain_events_outbox_guard
before update on dastak_v1.domain_events_outbox
for each row execute function dastak_v1.guard_outbox_update();
create trigger domain_events_outbox_no_delete
before delete on dastak_v1.domain_events_outbox
for each row execute function dastak_v1.reject_delete();

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values
  ('merchant.organization.manage', 'Manage the merchant organization profile.', 'SENSITIVE'),
  ('merchant.branch.manage', 'Manage branches and branch capacity.', 'SENSITIVE'),
  ('merchant.users.manage', 'Invite, suspend and revoke merchant users.', 'SENSITIVE'),
  ('merchant.permissions.manage', 'Grant and revoke merchant permission bundles.', 'HIGHLY_SENSITIVE'),
  ('merchant.catalogue.selection.manage', 'Manage branch selections from the Dastak catalogue.', 'STANDARD'),
  ('merchant.opportunities.respond', 'Respond to matching opportunities.', 'STANDARD'),
  ('merchant.fulfilment.manage', 'Prepare and mark owned fulfilments Ready.', 'SENSITIVE'),
  ('merchant.earnings.read', 'Read merchant earnings and settlement status.', 'SENSITIVE'),
  ('merchant.audit.read', 'Read the merchant audit trail.', 'HIGHLY_SENSITIVE'),
  ('platform.catalogue.manage', 'Manage the canonical Dastak retail catalogue.', 'HIGHLY_SENSITIVE'),
  ('platform.settings.manage', 'Manage protected platform settings.', 'HIGHLY_SENSITIVE'),
  ('platform.permissions.manage', 'Manage platform permission bundles.', 'HIGHLY_SENSITIVE');

insert into dastak_v1.permission_bundles (
  id, bundle_key, display_name, scope, description
) values
  ('10000000-0000-4000-8000-000000000001', 'merchant_owner', 'Merchant owner', 'MERCHANT', 'Full merchant organization administration.'),
  ('10000000-0000-4000-8000-000000000002', 'branch_manager', 'Branch manager', 'MERCHANT', 'Branch catalogue and fulfilment operations.'),
  ('10000000-0000-4000-8000-000000000003', 'catalogue_operator', 'Catalogue operator', 'MERCHANT', 'Branch SKU selection only.'),
  ('10000000-0000-4000-8000-000000000004', 'fulfilment_operator', 'Fulfilment operator', 'MERCHANT', 'Opportunity and fulfilment operations.'),
  ('10000000-0000-4000-8000-000000000005', 'earnings_viewer', 'Earnings viewer', 'MERCHANT', 'Read-only earnings access.');

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
select '10000000-0000-4000-8000-000000000001'::uuid, permission_key
from dastak_v1.permission_definitions
where permission_key like 'merchant.%';

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key) values
  ('10000000-0000-4000-8000-000000000002', 'merchant.branch.manage'),
  ('10000000-0000-4000-8000-000000000002', 'merchant.catalogue.selection.manage'),
  ('10000000-0000-4000-8000-000000000002', 'merchant.opportunities.respond'),
  ('10000000-0000-4000-8000-000000000002', 'merchant.fulfilment.manage'),
  ('10000000-0000-4000-8000-000000000003', 'merchant.catalogue.selection.manage'),
  ('10000000-0000-4000-8000-000000000004', 'merchant.opportunities.respond'),
  ('10000000-0000-4000-8000-000000000004', 'merchant.fulfilment.manage'),
  ('10000000-0000-4000-8000-000000000005', 'merchant.earnings.read');

insert into dastak_v1.setting_definitions (
  setting_key,
  value_type,
  description,
  default_value,
  validation_rules,
  protected,
  requires_explicit_value
) values
  ('matching.wave1_timeout_seconds', 'DURATION_SECONDS', 'Authoritative Wave 1 matching window.', '180', '{"minimum":180,"maximum":180}', true, false),
  ('matching.wave2_max_retail_merchants', 'INTEGER', 'Maximum retail merchants in a Wave 2 plan.', '3', '{"minimum":3,"maximum":3}', true, false),
  ('retail.branch_default_capacity', 'INTEGER', 'Default concurrent retail fulfilment capacity.', '5', '{"minimum":1}', true, false),
  ('commerce.currency_code', 'TEXT', 'Marketplace settlement currency.', '"INR"', '{"allowedValues":["INR"]}', true, false),
  ('commerce.prepaid_only', 'BOOLEAN', 'Require payment before fulfilment preparation.', 'true', '{}', true, false),
  ('commerce.allow_cod', 'BOOLEAN', 'Allow cash on delivery.', 'false', '{"allowedValues":[false]}', true, false),
  ('commerce.allow_substitutions', 'BOOLEAN', 'Allow product substitutions.', 'false', '{"allowedValues":[false]}', true, false),
  ('commerce.allow_scheduled_orders', 'BOOLEAN', 'Allow scheduled orders.', 'false', '{"allowedValues":[false]}', true, false),
  ('customer.allow_postpayment_cancellation', 'BOOLEAN', 'Allow customer cancellation after payment.', 'false', '{"allowedValues":[false]}', true, false),
  ('matching.wave2_timeout_seconds', 'DURATION_SECONDS', 'Wave 2 matching window.', null, '{"minimum":1}', true, true),
  ('matching.wave2_hold_seconds', 'DURATION_SECONDS', 'Wave 2 provisional inventory hold duration.', null, '{"minimum":1}', true, true),
  ('payment.reservation_seconds', 'DURATION_SECONDS', 'Customer payment reservation duration.', null, '{"minimum":1}', true, true),
  ('delivery.rider_offer_timeout_seconds', 'DURATION_SECONDS', 'Delivery rider offer response window.', null, '{"minimum":1}', true, true);

create function dastak_v1_api.actor_has_merchant_permission(
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
  select public.is_active_owner(p_actor_id)
    or exists (
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
    );
$$;

create function dastak_v1_api.grant_merchant_permission_bundle(
  p_actor_id uuid,
  p_merchant_user_id uuid,
  p_bundle_id uuid,
  p_branch_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
  v_grant_id uuid;
begin
  select organization_id into v_organization_id
  from dastak_v1.merchant_users
  where id = p_merchant_user_id;

  if v_organization_id is null then
    raise exception 'merchant user not found';
  end if;

  if not dastak_v1_api.actor_has_merchant_permission(
    p_actor_id,
    v_organization_id,
    'merchant.permissions.manage',
    p_branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  insert into dastak_v1.merchant_permission_grants (
    merchant_user_id,
    organization_id,
    bundle_id,
    branch_id,
    granted_by,
    grant_reason
  ) values (
    p_merchant_user_id,
    v_organization_id,
    p_bundle_id,
    p_branch_id,
    p_actor_id,
    p_reason
  ) returning id into v_grant_id;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'MERCHANT_PERMISSION_GRANTED',
    'merchant_permission_grant',
    v_grant_id,
    jsonb_build_object(
      'organizationId', v_organization_id,
      'merchantUserId', p_merchant_user_id,
      'bundleId', p_bundle_id,
      'branchId', p_branch_id
    )
  );

  return v_grant_id;
end;
$$;

create function dastak_v1_api.revoke_merchant_permission_grant(
  p_actor_id uuid,
  p_grant_id uuid,
  p_expected_version bigint,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant dastak_v1.merchant_permission_grants%rowtype;
begin
  select * into v_grant
  from dastak_v1.merchant_permission_grants
  where id = p_grant_id
  for update;

  if not found then
    raise exception 'permission grant not found';
  end if;
  if v_grant.revoked_at is not null then
    return;
  end if;
  if v_grant.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale permission grant version';
  end if;
  if not dastak_v1_api.actor_has_merchant_permission(
    p_actor_id,
    v_grant.organization_id,
    'merchant.permissions.manage',
    v_grant.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  update dastak_v1.merchant_permission_grants
  set revoked_by = p_actor_id,
      revoke_reason = p_reason,
      revoked_at = now(),
      version = version + 1
  where id = p_grant_id;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'MERCHANT_PERMISSION_REVOKED',
    'merchant_permission_grant',
    p_grant_id,
    jsonb_build_object('organizationId', v_grant.organization_id)
  );
end;
$$;

create function dastak_v1_api.set_platform_setting(
  p_actor_id uuid,
  p_setting_key text,
  p_scope_type dastak_v1.setting_scope_type,
  p_scope_id uuid,
  p_value jsonb,
  p_expected_version bigint,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setting dastak_v1.platform_settings%rowtype;
  v_id uuid;
begin
  if not public.is_active_owner(p_actor_id) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if not dastak_v1.validate_setting_value(p_setting_key, p_value) then
    raise exception 'invalid setting value';
  end if;

  select * into v_setting
  from dastak_v1.platform_settings
  where setting_key = p_setting_key
    and scope_type = p_scope_type
    and scope_id is not distinct from p_scope_id
  for update;

  if found then
    if v_setting.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'stale setting version';
    end if;
    update dastak_v1.platform_settings
    set setting_value = p_value,
        updated_by = p_actor_id,
        update_reason = p_reason,
        version = version + 1
    where id = v_setting.id
    returning id into v_id;
  else
    if p_expected_version <> 0 then
      raise exception using errcode = '40001', message = 'setting does not exist';
    end if;
    insert into dastak_v1.platform_settings (
      setting_key,
      scope_type,
      scope_id,
      setting_value,
      updated_by,
      update_reason
    ) values (
      p_setting_key,
      p_scope_type,
      p_scope_id,
      p_value,
      p_actor_id,
      p_reason
    ) returning id into v_id;
  end if;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'PLATFORM_SETTING_CHANGED',
    'platform_setting',
    v_id,
    jsonb_build_object('settingKey', p_setting_key, 'scopeType', p_scope_type)
  );

  return v_id;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'merchant_organizations',
    'merchant_branches',
    'merchant_users',
    'permission_definitions',
    'permission_bundles',
    'permission_bundle_permissions',
    'merchant_permission_grants',
    'merchant_permission_grant_history',
    'setting_definitions',
    'platform_settings',
    'platform_setting_history',
    'categories',
    'subcategories',
    'brands',
    'skus',
    'merchant_sku_selections',
    'orders',
    'order_context_snapshots',
    'order_lines',
    'order_price_snapshots',
    'retail_line_allocations',
    'order_state_journal',
    'idempotency_records',
    'domain_events_outbox',
    'audit_events'
  ] loop
    execute format('alter table dastak_v1.%I enable row level security', v_table);
  end loop;
end;
$$;

revoke all on all tables in schema dastak_v1
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema dastak_v1
  from public, anon, authenticated, service_role;
grant select on all tables in schema dastak_v1 to service_role;

revoke execute on all functions in schema dastak_v1
  from public, anon, authenticated, service_role;
revoke execute on all functions in schema dastak_v1_api
  from public, anon, authenticated, service_role;

grant execute on function dastak_v1_api.actor_has_merchant_permission(uuid, uuid, text, uuid)
  to service_role;
grant execute on function dastak_v1_api.grant_merchant_permission_bundle(uuid, uuid, uuid, uuid, text)
  to service_role;
grant execute on function dastak_v1_api.revoke_merchant_permission_grant(uuid, uuid, bigint, text)
  to service_role;
grant execute on function dastak_v1_api.set_platform_setting(uuid, text, dastak_v1.setting_scope_type, uuid, jsonb, bigint, text)
  to service_role;

comment on schema dastak_v1 is
  'Additive Dastak V1 domain. Legacy commerce remains read-only history.';
comment on table dastak_v1.retail_line_allocations is
  'A retail line can have at most one whole-quantity merchant allocation.';
comment on table dastak_v1.domain_events_outbox is
  'Transactional domain outbox. Delivery workers are added in a later batch.';
