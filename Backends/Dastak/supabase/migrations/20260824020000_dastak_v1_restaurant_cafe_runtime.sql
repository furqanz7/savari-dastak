-- Dastak V1 Batch C: Restaurant/Cafe catalogue, commitment and mixed-order runtime.
-- This remains additive to legacy commerce and reuses the V1 fulfilment lifecycle.

create type dastak_v1.restaurant_request_status as enum (
  'OFFERED', 'CONFIRMED', 'DECLINED', 'RELEASED'
);
create type dastak_v1.restaurant_commitment_status as enum (
  'COMMITTED', 'RELEASED'
);

alter table dastak_v1.orders
  add column restaurant_branch_id uuid,
  add constraint orders_restaurant_branch_fk
    foreign key (restaurant_branch_id, restaurant_organization_id)
    references dastak_v1.merchant_branches(id, organization_id),
  add constraint orders_restaurant_branch_required_check check (
    (order_type = 'RETAIL_ONLY' and restaurant_branch_id is null)
    or (order_type in ('FOOD_ONLY', 'MIXED') and restaurant_branch_id is not null)
  );

create index orders_restaurant_branch_idx
  on dastak_v1.orders (restaurant_branch_id, status)
  where restaurant_branch_id is not null;
create index orders_restaurant_branch_fk_idx
  on dastak_v1.orders (restaurant_branch_id, restaurant_organization_id);

alter table dastak_v1.order_lines
  add column food_selection_snapshot jsonb,
  add column food_selection_key text,
  add constraint order_lines_food_selection_check check (
    (line_type = 'RETAIL_SKU'
      and food_selection_snapshot is null and food_selection_key is null)
    or (line_type = 'FOOD_MENU_ITEM'
      and pg_catalog.jsonb_typeof(food_selection_snapshot) = 'object'
      and pg_catalog.char_length(food_selection_key) between 64 and 64)
  );

drop index dastak_v1.order_lines_food_item_uidx;
create unique index order_lines_food_selection_uidx
  on dastak_v1.order_lines (order_id, food_menu_item_id, food_selection_key)
  where line_type = 'FOOD_MENU_ITEM';

create table dastak_v1.restaurant_menu_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 100),
  description text check (
    description is null or pg_catalog.char_length(pg_catalog.btrim(description)) between 1 and 500
  ),
  sort_order integer not null default 0,
  status dastak_v1.catalogue_status not null default 'DRAFT',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  updated_by uuid not null references public.accounts(id),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  foreign key (branch_id, organization_id)
    references dastak_v1.merchant_branches(id, organization_id),
  unique (id, branch_id, organization_id)
);

create index restaurant_menu_categories_branch_idx
  on dastak_v1.restaurant_menu_categories (branch_id, status, sort_order, id);
create index restaurant_menu_categories_organization_idx
  on dastak_v1.restaurant_menu_categories (organization_id, branch_id);
create index restaurant_menu_categories_created_by_idx
  on dastak_v1.restaurant_menu_categories (created_by);
create index restaurant_menu_categories_updated_by_idx
  on dastak_v1.restaurant_menu_categories (updated_by);

create table dastak_v1.restaurant_menu_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null,
  organization_id uuid not null,
  branch_id uuid not null,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 160),
  description text check (
    description is null or pg_catalog.char_length(pg_catalog.btrim(description)) between 1 and 1000
  ),
  image_key text check (
    image_key is null or pg_catalog.char_length(pg_catalog.btrim(image_key)) between 1 and 500
  ),
  base_price_paise bigint not null check (base_price_paise > 0),
  tax_rate_bps integer not null default 0 check (tax_rate_bps between 0 and 10000),
  logistics_attributes jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(logistics_attributes) = 'object'),
  status dastak_v1.catalogue_status not null default 'DRAFT',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  updated_by uuid not null references public.accounts(id),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  foreign key (category_id, branch_id, organization_id)
    references dastak_v1.restaurant_menu_categories(id, branch_id, organization_id),
  unique (id, branch_id, organization_id)
);

create index restaurant_menu_items_category_idx
  on dastak_v1.restaurant_menu_items (category_id, status, name, id);
create index restaurant_menu_items_branch_idx
  on dastak_v1.restaurant_menu_items (branch_id, status, name, id);
create index restaurant_menu_items_organization_idx
  on dastak_v1.restaurant_menu_items (organization_id, branch_id);
create index restaurant_menu_items_category_fk_idx
  on dastak_v1.restaurant_menu_items (category_id, branch_id, organization_id);
create index restaurant_menu_items_created_by_idx
  on dastak_v1.restaurant_menu_items (created_by);
create index restaurant_menu_items_updated_by_idx
  on dastak_v1.restaurant_menu_items (updated_by);

alter table dastak_v1.order_lines
  add constraint order_lines_food_menu_item_fk
  foreign key (food_menu_item_id) references dastak_v1.restaurant_menu_items(id);

create index order_lines_food_menu_item_fk_idx
  on dastak_v1.order_lines (food_menu_item_id);

create type dastak_v1.restaurant_option_selection_type as enum ('SINGLE', 'MULTIPLE');

create table dastak_v1.restaurant_menu_option_groups (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null,
  organization_id uuid not null,
  branch_id uuid not null,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 100),
  selection_type dastak_v1.restaurant_option_selection_type not null,
  minimum_selections integer not null default 0 check (minimum_selections >= 0),
  maximum_selections integer not null check (maximum_selections > 0),
  sort_order integer not null default 0,
  status dastak_v1.catalogue_status not null default 'DRAFT',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  updated_by uuid not null references public.accounts(id),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  foreign key (menu_item_id, branch_id, organization_id)
    references dastak_v1.restaurant_menu_items(id, branch_id, organization_id),
  unique (id, menu_item_id, branch_id, organization_id),
  check (minimum_selections <= maximum_selections),
  check (selection_type <> 'SINGLE' or maximum_selections = 1)
);

create index restaurant_menu_option_groups_item_idx
  on dastak_v1.restaurant_menu_option_groups (menu_item_id, status, sort_order, id);
create index restaurant_menu_option_groups_branch_idx
  on dastak_v1.restaurant_menu_option_groups (branch_id, status);
create index restaurant_menu_option_groups_organization_idx
  on dastak_v1.restaurant_menu_option_groups (organization_id, branch_id);
create index restaurant_menu_option_groups_created_by_idx
  on dastak_v1.restaurant_menu_option_groups (created_by);
create index restaurant_menu_option_groups_updated_by_idx
  on dastak_v1.restaurant_menu_option_groups (updated_by);

create table dastak_v1.restaurant_menu_options (
  id uuid primary key default gen_random_uuid(),
  option_group_id uuid not null,
  menu_item_id uuid not null,
  organization_id uuid not null,
  branch_id uuid not null,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 100),
  price_delta_paise bigint not null default 0 check (price_delta_paise >= 0),
  sort_order integer not null default 0,
  status dastak_v1.catalogue_status not null default 'DRAFT',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  updated_by uuid not null references public.accounts(id),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  foreign key (option_group_id, menu_item_id, branch_id, organization_id)
    references dastak_v1.restaurant_menu_option_groups(
      id, menu_item_id, branch_id, organization_id
    )
);

create index restaurant_menu_options_group_idx
  on dastak_v1.restaurant_menu_options (option_group_id, status, sort_order, id);
create index restaurant_menu_options_item_idx
  on dastak_v1.restaurant_menu_options (menu_item_id, status);
create index restaurant_menu_options_branch_idx
  on dastak_v1.restaurant_menu_options (branch_id, status);
create index restaurant_menu_options_organization_idx
  on dastak_v1.restaurant_menu_options (organization_id, branch_id);
create index restaurant_menu_options_group_fk_idx
  on dastak_v1.restaurant_menu_options (
    option_group_id, menu_item_id, branch_id, organization_id
  );
create index restaurant_menu_options_created_by_idx
  on dastak_v1.restaurant_menu_options (created_by);
create index restaurant_menu_options_updated_by_idx
  on dastak_v1.restaurant_menu_options (updated_by);

create table dastak_v1.restaurant_order_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references dastak_v1.orders(id),
  organization_id uuid not null,
  branch_id uuid not null,
  status dastak_v1.restaurant_request_status not null default 'OFFERED',
  offered_at timestamptz not null default pg_catalog.now(),
  responded_by uuid references public.accounts(id),
  responded_at timestamptz,
  promised_prep_minutes integer check (promised_prep_minutes > 0),
  response_reason text,
  released_at timestamptz,
  release_reason text,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  foreign key (branch_id, organization_id)
    references dastak_v1.merchant_branches(id, organization_id),
  check (
    (status = 'OFFERED' and responded_by is null and responded_at is null
      and promised_prep_minutes is null and released_at is null)
    or (status = 'CONFIRMED' and responded_by is not null and responded_at is not null
      and promised_prep_minutes is not null and released_at is null)
    or (status = 'DECLINED' and responded_by is not null and responded_at is not null
      and promised_prep_minutes is null and response_reason is not null and released_at is null)
    or (status = 'RELEASED' and responded_at is not null
      and released_at is not null and release_reason is not null)
  )
);

create index restaurant_order_requests_branch_idx
  on dastak_v1.restaurant_order_requests (branch_id, status, offered_at, id);
create index restaurant_order_requests_organization_idx
  on dastak_v1.restaurant_order_requests (organization_id, status);
create index restaurant_order_requests_responded_by_idx
  on dastak_v1.restaurant_order_requests (responded_by);
create index restaurant_order_requests_branch_fk_idx
  on dastak_v1.restaurant_order_requests (branch_id, organization_id);

alter table dastak_v1.fulfilments
  drop constraint fulfilments_exactly_one_source_check,
  add column source_restaurant_request_id uuid
    references dastak_v1.restaurant_order_requests(id),
  add constraint fulfilments_exactly_one_source_check check (
    pg_catalog.num_nonnulls(
      source_opportunity_id,
      source_recovery_opportunity_id,
      source_restaurant_request_id
    ) = 1
  );

create unique index fulfilments_restaurant_request_uidx
  on dastak_v1.fulfilments (source_restaurant_request_id)
  where source_restaurant_request_id is not null;
create index fulfilments_restaurant_request_fk_idx
  on dastak_v1.fulfilments (source_restaurant_request_id);

create table dastak_v1.restaurant_capacity_commitments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references dastak_v1.restaurant_order_requests(id),
  fulfilment_id uuid not null unique references dastak_v1.fulfilments(id),
  order_id uuid not null references dastak_v1.orders(id),
  organization_id uuid not null,
  branch_id uuid not null,
  status dastak_v1.restaurant_commitment_status not null default 'COMMITTED',
  soft_threshold_snapshot integer not null check (soft_threshold_snapshot > 0),
  active_order_count_snapshot integer not null check (active_order_count_snapshot >= 0),
  accepted_above_threshold boolean not null,
  committed_at timestamptz not null default pg_catalog.now(),
  released_at timestamptz,
  release_reason text,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  foreign key (branch_id, organization_id)
    references dastak_v1.merchant_branches(id, organization_id),
  check (
    (status = 'COMMITTED' and released_at is null and release_reason is null)
    or (status = 'RELEASED' and released_at is not null and release_reason is not null)
  )
);

create index restaurant_capacity_commitments_order_idx
  on dastak_v1.restaurant_capacity_commitments (order_id, status);
create index restaurant_capacity_commitments_branch_idx
  on dastak_v1.restaurant_capacity_commitments (branch_id, status);
create index restaurant_capacity_commitments_organization_idx
  on dastak_v1.restaurant_capacity_commitments (organization_id, status);
create index restaurant_capacity_commitments_branch_fk_idx
  on dastak_v1.restaurant_capacity_commitments (branch_id, organization_id);

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values (
  'merchant.restaurant.menu.manage',
  'Manage the owned Restaurant/Cafe menu and availability.',
  'SENSITIVE'
);

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
values
  ('10000000-0000-4000-8000-000000000001', 'merchant.restaurant.menu.manage'),
  ('10000000-0000-4000-8000-000000000002', 'merchant.restaurant.menu.manage');

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values (
  'restaurant.soft_active_order_threshold',
  'INTEGER',
  'Soft warning threshold for active Restaurant/Cafe orders; never a hard acceptance cutoff.',
  '5',
  '{"minimum":1}',
  true,
  false
);

create function dastak_v1.guard_restaurant_versioned_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'restaurant menu identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'restaurant menu version must increment exactly once';
  end if;
  if tg_table_name = 'restaurant_menu_items'
    and new.category_id is distinct from old.category_id then
    raise exception 'restaurant menu item category cannot change';
  end if;
  if tg_table_name = 'restaurant_menu_option_groups'
    and new.menu_item_id is distinct from old.menu_item_id then
    raise exception 'restaurant option-group item cannot change';
  end if;
  if tg_table_name = 'restaurant_menu_options'
    and (new.menu_item_id is distinct from old.menu_item_id
      or new.option_group_id is distinct from old.option_group_id) then
    raise exception 'restaurant option identity cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger restaurant_menu_categories_guard
before update on dastak_v1.restaurant_menu_categories
for each row execute function dastak_v1.guard_restaurant_versioned_row();
create trigger restaurant_menu_items_guard
before update on dastak_v1.restaurant_menu_items
for each row execute function dastak_v1.guard_restaurant_versioned_row();
create trigger restaurant_menu_option_groups_guard
before update on dastak_v1.restaurant_menu_option_groups
for each row execute function dastak_v1.guard_restaurant_versioned_row();
create trigger restaurant_menu_options_guard
before update on dastak_v1.restaurant_menu_options
for each row execute function dastak_v1.guard_restaurant_versioned_row();

create trigger restaurant_menu_categories_no_delete
before delete on dastak_v1.restaurant_menu_categories
for each row execute function dastak_v1.reject_delete();
create trigger restaurant_menu_items_no_delete
before delete on dastak_v1.restaurant_menu_items
for each row execute function dastak_v1.reject_delete();
create trigger restaurant_menu_option_groups_no_delete
before delete on dastak_v1.restaurant_menu_option_groups
for each row execute function dastak_v1.reject_delete();
create trigger restaurant_menu_options_no_delete
before delete on dastak_v1.restaurant_menu_options
for each row execute function dastak_v1.reject_delete();
create trigger restaurant_order_requests_no_delete
before delete on dastak_v1.restaurant_order_requests
for each row execute function dastak_v1.reject_delete();
create trigger restaurant_capacity_commitments_no_delete
before delete on dastak_v1.restaurant_capacity_commitments
for each row execute function dastak_v1.reject_delete();

alter table dastak_v1.restaurant_menu_categories enable row level security;
alter table dastak_v1.restaurant_menu_items enable row level security;
alter table dastak_v1.restaurant_menu_option_groups enable row level security;
alter table dastak_v1.restaurant_menu_options enable row level security;
alter table dastak_v1.restaurant_order_requests enable row level security;
alter table dastak_v1.restaurant_capacity_commitments enable row level security;

revoke all on dastak_v1.restaurant_menu_categories,
  dastak_v1.restaurant_menu_items,
  dastak_v1.restaurant_menu_option_groups,
  dastak_v1.restaurant_menu_options,
  dastak_v1.restaurant_order_requests,
  dastak_v1.restaurant_capacity_commitments
from public, anon, authenticated, service_role;
grant select on dastak_v1.restaurant_menu_categories,
  dastak_v1.restaurant_menu_items,
  dastak_v1.restaurant_menu_option_groups,
  dastak_v1.restaurant_menu_options,
  dastak_v1.restaurant_order_requests,
  dastak_v1.restaurant_capacity_commitments
to service_role;

create or replace function dastak_v1.guard_order_update()
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
    or new.restaurant_branch_id is distinct from old.restaurant_branch_id
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
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create or replace function dastak_v1.guard_order_line_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
begin
  select * into v_order from dastak_v1.orders where id = new.order_id;
  if not found then raise exception 'order does not exist'; end if;
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
      or new.food_selection_snapshot is distinct from old.food_selection_snapshot
      or new.food_selection_key is distinct from old.food_selection_key
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
    new.updated_at := pg_catalog.now();
  end if;
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
  v_exact_recovery_release boolean := coalesce(
    pg_catalog.current_setting('dastak_v1.exact_recovery_release', true), ''
  ) = 'true';
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.source_opportunity_id is distinct from old.source_opportunity_id
    or new.source_recovery_opportunity_id is distinct from old.source_recovery_opportunity_id
    or new.source_restaurant_request_id is distinct from old.source_restaurant_request_id
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
    or (old.status = 'PREPARING' and new.status = 'RELEASED'
      and v_exact_recovery_release)
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
  if old.status = 'PREPARING' and new.status = 'RELEASED' and (
    not v_exact_recovery_release
    or new.released_at is null
    or new.release_reason <> 'EXACT_SKU_RECOVERY'
  ) then
    raise exception 'paid fulfilment release requires exact-SKU recovery context';
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
  elsif old.status = 'PICKED_UP' and new.status = 'COMPLETED' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.final_delivery_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then
      v_handoff_id := null;
    end;
    if v_handoff_id is null
      or not exists (
        select 1 from dastak_v1.verification_handoffs handoff
        where handoff.id = v_handoff_id
          and handoff.order_id = new.order_id
          and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
          and handoff.status in ('CONSUMED', 'OVERRIDDEN')
      )
      or (
        select count(*)
        from dastak_v1.packages package
        join dastak_v1.orders customer_order on customer_order.id = package.order_id
        where package.fulfilment_id = new.id
          and package.status = 'DELIVERED'
          and package.current_custody_owner_type = 'CUSTOMER'
          and package.current_custody_owner_id = customer_order.customer_id
      ) <> new.package_count then
      raise exception 'fulfilment completion requires verified Customer custody of every package';
    end if;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1_api.restaurant_menu_json(
  p_branch_id uuid,
  p_include_inactive boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'restaurant', pg_catalog.jsonb_build_object(
      'organizationId', organization.id,
      'branchId', branch.id,
      'name', organization.display_name,
      'branchName', branch.display_name,
      'imageKey', branch.address_snapshot ->> 'imageKey',
      'description', branch.address_snapshot ->> 'description',
      'serviceZoneId', branch.service_zone_id,
      'acceptingOrders', coalesce(operating.accepting_orders, false),
      'isOpen', coalesce(operating.is_open, false),
      'operationalVersion', coalesce(operating.version, 0),
      'branchStatus', branch.status,
      'merchantType', organization.merchant_type,
      'softActiveOrderThreshold', (
        dastak_v1_api.effective_setting_json(
          'restaurant.soft_active_order_threshold',
          branch.id, organization.id, branch.service_zone_id
        ) #>> '{}'
      )::integer,
      'activeOrderCount', (
        select count(*)
        from dastak_v1.restaurant_capacity_commitments commitment
        where commitment.branch_id = branch.id
          and commitment.status = 'COMMITTED'
      )
    ),
    'categories', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', category.id,
          'name', category.name,
          'description', category.description,
          'sortOrder', category.sort_order,
          'status', category.status,
          'version', category.version,
          'items', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'id', item.id,
                'name', item.name,
                'description', item.description,
                'imageKey', item.image_key,
                'basePricePaise', item.base_price_paise,
                'currencyCode', 'INR',
                'taxRateBps', item.tax_rate_bps,
                'logisticsAttributes', item.logistics_attributes,
                'status', item.status,
                'version', item.version,
                'optionGroups', coalesce((
                  select pg_catalog.jsonb_agg(
                    pg_catalog.jsonb_build_object(
                      'id', option_group.id,
                      'name', option_group.name,
                      'selectionType', option_group.selection_type,
                      'minimumSelections', option_group.minimum_selections,
                      'maximumSelections', option_group.maximum_selections,
                      'sortOrder', option_group.sort_order,
                      'status', option_group.status,
                      'version', option_group.version,
                      'options', coalesce((
                        select pg_catalog.jsonb_agg(
                          pg_catalog.jsonb_build_object(
                            'id', option.id,
                            'name', option.name,
                            'priceDeltaPaise', option.price_delta_paise,
                            'sortOrder', option.sort_order,
                            'status', option.status,
                            'version', option.version
                          ) order by option.sort_order, option.name, option.id
                        )
                        from dastak_v1.restaurant_menu_options option
                        where option.option_group_id = option_group.id
                          and (p_include_inactive or option.status = 'ACTIVE')
                      ), '[]'::jsonb)
                    ) order by option_group.sort_order, option_group.name, option_group.id
                  )
                  from dastak_v1.restaurant_menu_option_groups option_group
                  where option_group.menu_item_id = item.id
                    and (p_include_inactive or option_group.status = 'ACTIVE')
                ), '[]'::jsonb)
              ) order by item.name, item.id
            )
            from dastak_v1.restaurant_menu_items item
            where item.category_id = category.id
              and (p_include_inactive or item.status = 'ACTIVE')
          ), '[]'::jsonb)
        ) order by category.sort_order, category.name, category.id
      )
      from dastak_v1.restaurant_menu_categories category
      where category.branch_id = branch.id
        and (p_include_inactive or category.status = 'ACTIVE')
    ), '[]'::jsonb)
  )
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
   and organization.merchant_type = 'RESTAURANT_CAFE'
  left join dastak_v1.branch_operational_states operating
    on operating.branch_id = branch.id
  where branch.id = p_branch_id;
$$;

create function dastak_v1_api.list_customer_restaurants(
  p_actor_id uuid,
  p_query text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'invalid restaurant limit';
  end if;
  return pg_catalog.jsonb_build_object(
    'restaurants', coalesce((
      select pg_catalog.jsonb_agg(
        dastak_v1_api.restaurant_menu_json(visible.id, false)
        order by visible.display_name, visible.id
      )
      from (
        select branch.id, organization.display_name
        from dastak_v1.merchant_branches branch
        join dastak_v1.merchant_organizations organization
          on organization.id = branch.organization_id
        join dastak_v1.branch_operational_states operating
          on operating.branch_id = branch.id
        join public.service_zones zone
          on zone.id = branch.service_zone_id and zone.active
        where organization.merchant_type = 'RESTAURANT_CAFE'
          and organization.status = 'ACTIVE'
          and branch.status = 'ACTIVE'
          and operating.is_open and operating.accepting_orders
          and (
            p_query is null
            or organization.display_name ilike '%' || p_query || '%'
            or branch.display_name ilike '%' || p_query || '%'
            or exists (
              select 1 from dastak_v1.restaurant_menu_items item
              where item.branch_id = branch.id and item.status = 'ACTIVE'
                and item.name ilike '%' || p_query || '%'
            )
          )
          and not exists (
            select 1 from dastak_v1.operational_pause_controls control
            where control.active and (
              (control.scope = 'MERCHANT_BRANCH' and control.branch_id = branch.id)
              or (control.scope = 'ZONE_FOOD' and control.service_zone_id = branch.service_zone_id)
            )
          )
          and exists (
            select 1 from dastak_v1.restaurant_menu_items item
            join dastak_v1.restaurant_menu_categories category
              on category.id = item.category_id and category.status = 'ACTIVE'
            where item.branch_id = branch.id and item.status = 'ACTIVE'
          )
        order by organization.display_name, branch.id
        limit p_limit
      ) visible
    ), '[]'::jsonb)
  );
end;
$$;

create function dastak_v1_api.merchant_restaurant_menu(
  p_actor_id uuid,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch_id uuid := p_branch_id;
  v_organization_id uuid;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if v_branch_id is null then
    select branch.id, branch.organization_id
      into v_branch_id, v_organization_id
    from dastak_v1.merchant_branches branch
    join dastak_v1.merchant_organizations organization
      on organization.id = branch.organization_id
     and organization.merchant_type = 'RESTAURANT_CAFE'
    where dastak_v1_api.actor_has_wave1_merchant_permission(
      p_actor_id, branch.organization_id,
      'merchant.restaurant.menu.manage', branch.id
    )
    order by branch.created_at, branch.id limit 1;
  else
    select branch.organization_id into v_organization_id
    from dastak_v1.merchant_branches branch
    join dastak_v1.merchant_organizations organization
      on organization.id = branch.organization_id
     and organization.merchant_type = 'RESTAURANT_CAFE'
    where branch.id = v_branch_id;
  end if;
  if v_branch_id is null or v_organization_id is null then
    raise exception using errcode = 'P0002', message = 'Restaurant/Cafe branch not found';
  end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_organization_id,
    'merchant.restaurant.menu.manage', v_branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  return dastak_v1_api.restaurant_menu_json(v_branch_id, true);
end;
$$;

create function dastak_v1_api.upsert_restaurant_menu_entity(
  p_actor_id uuid,
  p_branch_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_expected_version bigint,
  p_payload jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command text := 'upsertRestaurantMenu:' || coalesce(p_entity_type, '');
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_id uuid := coalesce(p_entity_id, gen_random_uuid());
  v_status dastak_v1.catalogue_status;
  v_result jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_entity_type not in ('CATEGORY', 'ITEM', 'OPTION_GROUP', 'OPTION')
    or p_expected_version is null or p_expected_version < 0
    or p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid restaurant menu command';
  end if;
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
   and organization.merchant_type = 'RESTAURANT_CAFE'
  where branch.id = p_branch_id for update of branch;
  if not found then
    raise exception using errcode = 'P0002', message = 'Restaurant/Cafe branch not found';
  end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_branch.organization_id,
    'merchant.restaurant.menu.manage', v_branch.id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  begin
    v_status := coalesce((p_payload ->> 'status')::dastak_v1.catalogue_status, 'DRAFT');
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid menu status';
  end;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'branchId', p_branch_id, 'entityType', p_entity_type,
    'entityId', v_id, 'expectedVersion', p_expected_version, 'payload', p_payload
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select * into v_existing from dastak_v1.idempotency_records
  where actor_id = p_actor_id and command_name = v_command
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  if p_entity_type = 'CATEGORY' then
    if p_expected_version = 0 then
      insert into dastak_v1.restaurant_menu_categories (
        id, organization_id, branch_id, name, description, sort_order,
        status, created_by, updated_by
      ) values (
        v_id, v_branch.organization_id, v_branch.id,
        pg_catalog.btrim(p_payload ->> 'name'),
        nullif(pg_catalog.btrim(p_payload ->> 'description'), ''),
        coalesce((p_payload ->> 'sortOrder')::integer, 0),
        v_status, p_actor_id, p_actor_id
      );
    else
      update dastak_v1.restaurant_menu_categories category
      set name = pg_catalog.btrim(p_payload ->> 'name'),
          description = nullif(pg_catalog.btrim(p_payload ->> 'description'), ''),
          sort_order = coalesce((p_payload ->> 'sortOrder')::integer, category.sort_order),
          status = v_status, updated_by = p_actor_id, version = category.version + 1
      where category.id = v_id and category.branch_id = v_branch.id
        and category.version = p_expected_version;
      if not found then raise exception using errcode = '40001', message = 'STALE_MENU_VERSION'; end if;
    end if;
  elsif p_entity_type = 'ITEM' then
    if p_expected_version = 0 then
      insert into dastak_v1.restaurant_menu_items (
        id, category_id, organization_id, branch_id, name, description,
        image_key, base_price_paise, tax_rate_bps, logistics_attributes,
        status, created_by, updated_by
      ) values (
        v_id, (p_payload ->> 'categoryId')::uuid,
        v_branch.organization_id, v_branch.id,
        pg_catalog.btrim(p_payload ->> 'name'),
        nullif(pg_catalog.btrim(p_payload ->> 'description'), ''),
        nullif(pg_catalog.btrim(p_payload ->> 'imageKey'), ''),
        (p_payload ->> 'basePricePaise')::bigint,
        coalesce((p_payload ->> 'taxRateBps')::integer, 0),
        coalesce(p_payload -> 'logisticsAttributes', '{}'::jsonb),
        v_status, p_actor_id, p_actor_id
      );
    else
      update dastak_v1.restaurant_menu_items item
      set name = pg_catalog.btrim(p_payload ->> 'name'),
          description = nullif(pg_catalog.btrim(p_payload ->> 'description'), ''),
          image_key = nullif(pg_catalog.btrim(p_payload ->> 'imageKey'), ''),
          base_price_paise = (p_payload ->> 'basePricePaise')::bigint,
          tax_rate_bps = coalesce((p_payload ->> 'taxRateBps')::integer, item.tax_rate_bps),
          logistics_attributes = coalesce(
            p_payload -> 'logisticsAttributes', item.logistics_attributes
          ),
          status = v_status, updated_by = p_actor_id, version = item.version + 1
      where item.id = v_id and item.branch_id = v_branch.id
        and item.version = p_expected_version
        and item.category_id = (p_payload ->> 'categoryId')::uuid;
      if not found then raise exception using errcode = '40001', message = 'STALE_MENU_VERSION'; end if;
    end if;
  elsif p_entity_type = 'OPTION_GROUP' then
    if p_expected_version = 0 then
      insert into dastak_v1.restaurant_menu_option_groups (
        id, menu_item_id, organization_id, branch_id, name, selection_type,
        minimum_selections, maximum_selections, sort_order, status,
        created_by, updated_by
      ) values (
        v_id, (p_payload ->> 'menuItemId')::uuid,
        v_branch.organization_id, v_branch.id,
        pg_catalog.btrim(p_payload ->> 'name'),
        (p_payload ->> 'selectionType')::dastak_v1.restaurant_option_selection_type,
        coalesce((p_payload ->> 'minimumSelections')::integer, 0),
        (p_payload ->> 'maximumSelections')::integer,
        coalesce((p_payload ->> 'sortOrder')::integer, 0),
        v_status, p_actor_id, p_actor_id
      );
    else
      update dastak_v1.restaurant_menu_option_groups option_group
      set name = pg_catalog.btrim(p_payload ->> 'name'),
          selection_type = (p_payload ->> 'selectionType')::dastak_v1.restaurant_option_selection_type,
          minimum_selections = coalesce(
            (p_payload ->> 'minimumSelections')::integer, option_group.minimum_selections
          ),
          maximum_selections = (p_payload ->> 'maximumSelections')::integer,
          sort_order = coalesce((p_payload ->> 'sortOrder')::integer, option_group.sort_order),
          status = v_status, updated_by = p_actor_id, version = option_group.version + 1
      where option_group.id = v_id and option_group.branch_id = v_branch.id
        and option_group.version = p_expected_version
        and option_group.menu_item_id = (p_payload ->> 'menuItemId')::uuid;
      if not found then raise exception using errcode = '40001', message = 'STALE_MENU_VERSION'; end if;
    end if;
  else
    if p_expected_version = 0 then
      insert into dastak_v1.restaurant_menu_options (
        id, option_group_id, menu_item_id, organization_id, branch_id,
        name, price_delta_paise, sort_order, status, created_by, updated_by
      )
      select v_id, option_group.id, option_group.menu_item_id,
        v_branch.organization_id, v_branch.id,
        pg_catalog.btrim(p_payload ->> 'name'),
        coalesce((p_payload ->> 'priceDeltaPaise')::bigint, 0),
        coalesce((p_payload ->> 'sortOrder')::integer, 0),
        v_status, p_actor_id, p_actor_id
      from dastak_v1.restaurant_menu_option_groups option_group
      where option_group.id = (p_payload ->> 'optionGroupId')::uuid
        and option_group.branch_id = v_branch.id;
      if not found then raise exception using errcode = '22023', message = 'invalid option group'; end if;
    else
      update dastak_v1.restaurant_menu_options option
      set name = pg_catalog.btrim(p_payload ->> 'name'),
          price_delta_paise = coalesce(
            (p_payload ->> 'priceDeltaPaise')::bigint, option.price_delta_paise
          ),
          sort_order = coalesce((p_payload ->> 'sortOrder')::integer, option.sort_order),
          status = v_status, updated_by = p_actor_id, version = option.version + 1
      where option.id = v_id and option.branch_id = v_branch.id
        and option.version = p_expected_version
        and option.option_group_id = (p_payload ->> 'optionGroupId')::uuid;
      if not found then raise exception using errcode = '40001', message = 'STALE_MENU_VERSION'; end if;
    end if;
  end if;

  v_result := pg_catalog.jsonb_build_object(
    'entityId', v_id, 'entityType', p_entity_type,
    'menu', dastak_v1_api.restaurant_menu_json(v_branch.id, true)
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (p_actor_id, v_command, p_idempotency_key, v_hash, v_result, 200, v_id);
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'RESTAURANT_MENU_ENTITY_UPSERTED',
    'restaurant_menu_' || lower(p_entity_type), v_id,
    pg_catalog.jsonb_build_object(
      'branchId', v_branch.id, 'expectedVersion', p_expected_version,
      'idempotencyKey', p_idempotency_key
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_id::text || ':RESTAURANT_MENU_UPDATED:' ||
      coalesce(nullif(p_expected_version, 0) + 1, 1)::text,
    'RESTAURANT_MENU_ENTITY', v_id,
    coalesce(nullif(p_expected_version, 0) + 1, 1),
    'RESTAURANT_MENU_UPDATED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'branchId', v_branch.id, 'entityType', p_entity_type, 'entityId', v_id
    )
  );
  return v_result;
exception
  when invalid_text_representation or numeric_value_out_of_range
    or not_null_violation or check_violation or foreign_key_violation then
    raise exception using errcode = '22023', message = 'invalid restaurant menu payload';
end;
$$;

create function dastak_v1_api.restaurant_selection_snapshot(
  p_branch_id uuid,
  p_menu_item_id uuid,
  p_option_ids jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_option_ids uuid[] := '{}'::uuid[];
  v_option_count integer;
  v_group record;
  v_selected integer;
  v_options jsonb;
  v_snapshot jsonb;
  v_unit_price bigint;
begin
  if p_option_ids is null then p_option_ids := '[]'::jsonb; end if;
  if pg_catalog.jsonb_typeof(p_option_ids) <> 'array' then
    raise exception using errcode = '22023', message = 'optionIds must be an array';
  end if;
  select coalesce(pg_catalog.array_agg(value::uuid order by value::uuid), '{}'::uuid[]),
         count(*)
    into v_option_ids, v_option_count
  from pg_catalog.jsonb_array_elements_text(p_option_ids) selected(value);
  if pg_catalog.cardinality(v_option_ids) <> (
    select count(distinct option_id) from pg_catalog.unnest(v_option_ids) option_id
  ) then
    raise exception using errcode = '22023', message = 'duplicate menu option';
  end if;
  select item.*, category.status as category_status,
         branch.organization_id, branch.status as branch_status,
         organization.status as organization_status,
         operating.is_open, operating.accepting_orders
    into v_item
  from dastak_v1.restaurant_menu_items item
  join dastak_v1.restaurant_menu_categories category
    on category.id = item.category_id and category.branch_id = item.branch_id
  join dastak_v1.merchant_branches branch on branch.id = item.branch_id
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
   and organization.merchant_type = 'RESTAURANT_CAFE'
  join dastak_v1.branch_operational_states operating
    on operating.branch_id = branch.id
  where item.id = p_menu_item_id and item.branch_id = p_branch_id;
  if not found or v_item.status <> 'ACTIVE' or v_item.category_status <> 'ACTIVE'
    or v_item.branch_status <> 'ACTIVE' or v_item.organization_status <> 'ACTIVE'
    or not v_item.is_open or not v_item.accepting_orders then
    raise exception using errcode = '22023', message = 'menu item unavailable';
  end if;
  if exists (
    select 1 from pg_catalog.unnest(v_option_ids) selected(option_id)
    where not exists (
      select 1 from dastak_v1.restaurant_menu_options option
      join dastak_v1.restaurant_menu_option_groups option_group
        on option_group.id = option.option_group_id
       and option_group.status = 'ACTIVE'
      where option.id = selected.option_id
        and option.menu_item_id = v_item.id
        and option.branch_id = p_branch_id
        and option.status = 'ACTIVE'
    )
  ) then
    raise exception using errcode = '22023', message = 'menu option unavailable';
  end if;
  for v_group in
    select option_group.*
    from dastak_v1.restaurant_menu_option_groups option_group
    where option_group.menu_item_id = v_item.id
      and option_group.status = 'ACTIVE'
    order by option_group.sort_order, option_group.id
  loop
    select count(*) into v_selected
    from dastak_v1.restaurant_menu_options option
    where option.option_group_id = v_group.id
      and option.id = any(v_option_ids)
      and option.status = 'ACTIVE';
    if v_selected < v_group.minimum_selections
      or v_selected > v_group.maximum_selections then
      raise exception using errcode = '22023',
        message = 'menu option selection does not satisfy group rules';
    end if;
  end loop;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', option.id, 'groupId', option.option_group_id,
    'groupName', option_group.name, 'name', option.name,
    'priceDeltaPaise', option.price_delta_paise
  ) order by option_group.sort_order, option.sort_order, option.id), '[]'::jsonb),
  coalesce(sum(option.price_delta_paise), 0)
  into v_options, v_unit_price
  from dastak_v1.restaurant_menu_options option
  join dastak_v1.restaurant_menu_option_groups option_group
    on option_group.id = option.option_group_id
  where option.id = any(v_option_ids);
  v_unit_price := v_item.base_price_paise + v_unit_price;
  v_snapshot := pg_catalog.jsonb_build_object(
    'menuItemId', v_item.id,
    'name', v_item.name,
    'basePricePaise', v_item.base_price_paise,
    'unitPricePaise', v_unit_price,
    'taxRateBps', v_item.tax_rate_bps,
    'options', v_options
  );
  return v_snapshot || pg_catalog.jsonb_build_object(
    'selectionKey', pg_catalog.encode(dastak_v1_api.request_hash(
      pg_catalog.jsonb_build_object('menuItemId', v_item.id, 'options', v_options)
    ), 'hex'),
    'organizationId', v_item.organization_id,
    'branchId', p_branch_id,
    'logisticsAttributes', v_item.logistics_attributes
  );
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid menu option identifier';
end;
$$;

create or replace function dastak_v1_api.submit_order(
  p_actor_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_order jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'submitOrder';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_account public.accounts%rowtype;
  v_delivery_input jsonb;
  v_recipient_input jsonb;
  v_address jsonb;
  v_recipient jsonb;
  v_address_line text;
  v_recipient_name text;
  v_recipient_phone text;
  v_country_code text;
  v_latitude numeric;
  v_longitude numeric;
  v_line_input jsonb;
  v_sku_id uuid;
  v_quantity_bigint bigint;
  v_quantity integer;
  v_sku dastak_v1.skus%rowtype;
  v_food_snapshot jsonb;
  v_menu_item_id uuid;
  v_restaurant_branch dastak_v1.merchant_branches%rowtype;
  v_restaurant_organization_id uuid;
  v_retail_count integer := 0;
  v_food_count integer := 0;
  v_order_type dastak_v1.order_type;
  v_order_id uuid := gen_random_uuid();
  v_display_order_number text;
  v_subtotal_paise bigint := 0;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_expected_version is distinct from 0 then
    raise exception using errcode = '40001', message = 'new order expectedVersion must be 0';
  end if;
  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200
    or p_order is null or pg_catalog.jsonb_typeof(p_order) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid order submission';
  end if;
  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'expectedVersion', p_expected_version, 'order', p_order
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select * into v_existing from dastak_v1.idempotency_records
  where actor_id = p_actor_id and command_name = v_command
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select * into v_account from public.accounts where id = p_actor_id;
  v_delivery_input := p_order -> 'deliveryAddress';
  if v_delivery_input is null or pg_catalog.jsonb_typeof(v_delivery_input) <> 'object' then
    raise exception using errcode = '22023', message = 'deliveryAddress is required';
  end if;
  v_address_line := nullif(pg_catalog.btrim(coalesce(
    v_delivery_input ->> 'line1', v_delivery_input ->> 'formattedAddress', ''
  )), '');
  v_country_code := upper(pg_catalog.btrim(coalesce(v_delivery_input ->> 'countryCode', '')));
  if v_address_line is null or pg_catalog.char_length(v_address_line) > 300
    or v_country_code !~ '^[A-Z]{2}$' then
    raise exception using errcode = '22023', message = 'a valid delivery address is required';
  end if;
  if pg_catalog.jsonb_typeof(v_delivery_input -> 'latitude') <> 'number'
    or pg_catalog.jsonb_typeof(v_delivery_input -> 'longitude') <> 'number' then
    raise exception using errcode = '22023', message = 'latitude and longitude are required';
  end if;
  v_latitude := (v_delivery_input ->> 'latitude')::numeric;
  v_longitude := (v_delivery_input ->> 'longitude')::numeric;
  if v_latitude not between -90 and 90 or v_longitude not between -180 and 180 then
    raise exception using errcode = '22023', message = 'delivery coordinates are out of range';
  end if;
  v_address := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'label', nullif(pg_catalog.btrim(v_delivery_input ->> 'label'), ''),
    'line1', v_address_line,
    'line2', nullif(pg_catalog.btrim(v_delivery_input ->> 'line2'), ''),
    'landmark', nullif(pg_catalog.btrim(v_delivery_input ->> 'landmark'), ''),
    'locality', nullif(pg_catalog.btrim(v_delivery_input ->> 'locality'), ''),
    'city', nullif(pg_catalog.btrim(v_delivery_input ->> 'city'), ''),
    'state', nullif(pg_catalog.btrim(v_delivery_input ->> 'state'), ''),
    'postalCode', nullif(pg_catalog.btrim(v_delivery_input ->> 'postalCode'), ''),
    'countryCode', v_country_code, 'latitude', v_latitude, 'longitude', v_longitude,
    'instructions', nullif(pg_catalog.btrim(v_delivery_input ->> 'instructions'), '')
  ));
  v_recipient_input := coalesce(p_order -> 'recipient', '{}'::jsonb);
  if pg_catalog.jsonb_typeof(v_recipient_input) <> 'object' then
    raise exception using errcode = '22023', message = 'recipient must be an object';
  end if;
  v_recipient_name := pg_catalog.btrim(coalesce(
    v_recipient_input ->> 'name', v_account.display_name
  ));
  v_recipient_phone := pg_catalog.btrim(coalesce(
    v_recipient_input ->> 'phoneNumber', v_account.phone_number
  ));
  if pg_catalog.char_length(v_recipient_name) not between 1 and 80
    or v_recipient_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception using errcode = '22023', message = 'valid recipient details are required';
  end if;
  v_recipient := pg_catalog.jsonb_build_object(
    'name', v_recipient_name, 'phoneNumber', v_recipient_phone
  );
  if coalesce(pg_catalog.jsonb_typeof(p_order -> 'lines'), '') <> 'array'
    or pg_catalog.jsonb_array_length(p_order -> 'lines') = 0 then
    raise exception using errcode = '22023', message = 'at least one order line is required';
  end if;
  for v_line_input in select value from pg_catalog.jsonb_array_elements(p_order -> 'lines')
  loop
    if pg_catalog.jsonb_typeof(v_line_input) <> 'object'
      or coalesce(v_line_input ->> 'lineType', '') not in ('RETAIL_SKU', 'FOOD_MENU_ITEM')
      or pg_catalog.jsonb_typeof(v_line_input -> 'quantity') <> 'number'
      or (v_line_input ->> 'quantity') !~ '^[1-9][0-9]*$' then
      raise exception using errcode = '22023', message = 'invalid order line';
    end if;
    if v_line_input ->> 'lineType' = 'RETAIL_SKU' then
      v_retail_count := v_retail_count + 1;
      if coalesce(v_line_input ->> 'skuId', '')
        !~ '^[0-9a-fA-F-]{36}$' then
        raise exception using errcode = '22023', message = 'line skuId is invalid';
      end if;
    else
      v_food_count := v_food_count + 1;
      if coalesce(v_line_input ->> 'menuItemId', '') !~ '^[0-9a-fA-F-]{36}$' then
        raise exception using errcode = '22023', message = 'line menuItemId is invalid';
      end if;
    end if;
  end loop;
  if v_food_count > 0 then
    begin
      select branch.* into v_restaurant_branch
      from dastak_v1.merchant_branches branch
      join dastak_v1.merchant_organizations organization
        on organization.id = branch.organization_id
       and organization.merchant_type = 'RESTAURANT_CAFE'
      join dastak_v1.branch_operational_states operating
        on operating.branch_id = branch.id
      where branch.id = (p_order ->> 'restaurantBranchId')::uuid
        and branch.status = 'ACTIVE' and organization.status = 'ACTIVE'
        and operating.is_open and operating.accepting_orders
      for update of branch, operating;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'invalid restaurantBranchId';
    end;
    if not found then
      raise exception using errcode = '55000', message = 'RESTAURANT_NOT_ACCEPTING_ORDERS';
    end if;
    if v_restaurant_branch.service_zone_id is null then
      raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
        detail = 'Restaurant/Cafe branch requires an active service zone.';
    end if;
    if not exists (
      select 1 from public.service_zones zone
      where zone.id = v_restaurant_branch.service_zone_id and zone.active
        and extensions.st_covers(
          zone.boundary,
          extensions.st_setsrid(extensions.st_makepoint(
            v_longitude::double precision, v_latitude::double precision
          ), 4326)
        )
    ) then
      raise exception using errcode = '22023', message = 'RESTAURANT_OUTSIDE_SERVICE_ZONE';
    end if;
    if exists (
      select 1 from dastak_v1.operational_pause_controls control
      where control.active and (
        (control.scope = 'MERCHANT_BRANCH' and control.branch_id = v_restaurant_branch.id)
        or (control.scope = case when v_retail_count > 0
              then 'ZONE_MIXED'::dastak_v1.operational_pause_scope
              else 'ZONE_FOOD'::dastak_v1.operational_pause_scope end
          and control.service_zone_id = v_restaurant_branch.service_zone_id)
      )
    ) then
      raise exception using errcode = '55000', message = 'RESTAURANT_NOT_ACCEPTING_ORDERS';
    end if;
    v_restaurant_organization_id := v_restaurant_branch.organization_id;
  elsif p_order ? 'restaurantBranchId' then
    raise exception using errcode = '22023', message = 'retail-only order cannot select a restaurant';
  end if;
  v_order_type := case
    when v_food_count > 0 and v_retail_count > 0 then 'MIXED'::dastak_v1.order_type
    when v_food_count > 0 then 'FOOD_ONLY'::dastak_v1.order_type
    else 'RETAIL_ONLY'::dastak_v1.order_type
  end;
  v_display_order_number := 'DSK-' || pg_catalog.to_char(pg_catalog.now(), 'YYMMDD')
    || '-' || pg_catalog.lpad(
      pg_catalog.nextval('dastak_v1.order_number_sequence'::regclass)::text, 8, '0'
    );
  insert into dastak_v1.orders (
    id, display_order_number, customer_id, order_type,
    restaurant_organization_id, restaurant_branch_id,
    status, submitted_at, version
  ) values (
    v_order_id, v_display_order_number, p_actor_id, v_order_type,
    v_restaurant_organization_id, v_restaurant_branch.id,
    'CREATED', pg_catalog.now(), 1
  );
  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version, command_name, actor_id, reason
  ) values (v_order_id, null, 'CREATED', 1, v_command, p_actor_id, 'Customer submitted an order.');
  insert into dastak_v1.order_context_snapshots (
    order_id, delivery_address, recipient, snapshot_hash
  ) values (
    v_order_id, v_address, v_recipient,
    dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
      'deliveryAddress', v_address, 'recipient', v_recipient
    ))
  );

  for v_sku_id, v_quantity_bigint in
    select (value ->> 'skuId')::uuid, sum((value ->> 'quantity')::bigint)
    from pg_catalog.jsonb_array_elements(p_order -> 'lines')
    where value ->> 'lineType' = 'RETAIL_SKU'
    group by (value ->> 'skuId')::uuid order by (value ->> 'skuId')::uuid
  loop
    if v_quantity_bigint > 2147483647 then
      raise exception using errcode = '22003', message = 'line quantity is too large';
    end if;
    v_quantity := v_quantity_bigint::integer;
    select sku.* into v_sku
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory
      on subcategory.id = sku.subcategory_id and subcategory.status = 'ACTIVE'
    join dastak_v1.categories category
      on category.id = subcategory.category_id and category.status = 'ACTIVE'
    left join dastak_v1.brands brand on brand.id = sku.brand_id
    where sku.id = v_sku_id and sku.status = 'ACTIVE'
      and (brand.id is null or brand.status = 'ACTIVE') for share of sku;
    if not found then
      raise exception using errcode = '22023', message = 'one or more SKUs are unavailable';
    end if;
    insert into dastak_v1.order_lines (
      order_id, line_type, sku_id, product_name_snapshot, variant_snapshot,
      pack_size_snapshot, quantity, unit_price_paise, tax_rate_bps, status
    ) values (
      v_order_id, 'RETAIL_SKU', v_sku.id, v_sku.canonical_name,
      v_sku.variant_name, v_sku.pack_size, v_quantity,
      v_sku.selling_price_paise, v_sku.tax_rate_bps, 'ORDERED'
    );
    v_subtotal_paise := v_subtotal_paise + v_quantity::bigint * v_sku.selling_price_paise;
  end loop;

  for v_line_input in
    select value from pg_catalog.jsonb_array_elements(p_order -> 'lines')
    where value ->> 'lineType' = 'FOOD_MENU_ITEM'
  loop
    v_quantity_bigint := (v_line_input ->> 'quantity')::bigint;
    if v_quantity_bigint > 2147483647 then
      raise exception using errcode = '22003', message = 'line quantity is too large';
    end if;
    v_quantity := v_quantity_bigint::integer;
    v_menu_item_id := (v_line_input ->> 'menuItemId')::uuid;
    v_food_snapshot := dastak_v1_api.restaurant_selection_snapshot(
      v_restaurant_branch.id, v_menu_item_id,
      coalesce(v_line_input -> 'optionIds', '[]'::jsonb)
    );
    if (v_food_snapshot ->> 'organizationId')::uuid
      is distinct from v_restaurant_organization_id then
      raise exception using errcode = '22023', message = 'food lines must use the selected restaurant';
    end if;
    insert into dastak_v1.order_lines (
      order_id, line_type, food_menu_item_id, restaurant_organization_id,
      food_selection_snapshot, food_selection_key,
      product_name_snapshot, variant_snapshot, pack_size_snapshot,
      quantity, unit_price_paise, tax_rate_bps, status
    ) values (
      v_order_id, 'FOOD_MENU_ITEM', v_menu_item_id, v_restaurant_organization_id,
      v_food_snapshot - 'organizationId' - 'branchId' - 'selectionKey',
      v_food_snapshot ->> 'selectionKey', v_food_snapshot ->> 'name',
      nullif((select pg_catalog.string_agg(value ->> 'name', ', ')
        from pg_catalog.jsonb_array_elements(v_food_snapshot -> 'options')), ''),
      null, v_quantity, (v_food_snapshot ->> 'unitPricePaise')::bigint,
      (v_food_snapshot ->> 'taxRateBps')::integer, 'ORDERED'
    );
    v_subtotal_paise := v_subtotal_paise
      + v_quantity::bigint * (v_food_snapshot ->> 'unitPricePaise')::bigint;
  end loop;

  insert into dastak_v1.order_price_snapshots (
    order_id, snapshot_kind, subtotal_paise, delivery_fee_paise,
    platform_fee_paise, discount_paise, tax_paise, total_paise,
    currency_code, calculation_details
  ) values (
    v_order_id, 'SUBMITTED', v_subtotal_paise, 0, 0, 0, 0,
    v_subtotal_paise, 'INR', pg_catalog.jsonb_build_object(
      'retailPriceAuthority', case when v_retail_count > 0 then 'DASTAK' end,
      'restaurantMenuCommitment', v_food_count > 0,
      'taxIncludedInUnitPrice', true
    )
  );
  update dastak_v1.orders set status = 'MATCHING', version = version + 1
  where id = v_order_id;
  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, actor_id, reason
  ) values (
    v_order_id, 'CREATED', 'MATCHING', 2, v_command, p_actor_id,
    'Submission accepted; every required fulfilment must confirm before payment.'
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_order_id::text || ':ORDER_SUBMITTED:2', 'ORDER', v_order_id, 2,
    'ORDER_SUBMITTED', p_actor_id, pg_catalog.jsonb_build_object(
      'orderId', v_order_id, 'customerId', p_actor_id,
      'orderType', v_order_type, 'status', 'MATCHING', 'version', 2,
      'restaurantOrganizationId', v_restaurant_organization_id,
      'restaurantBranchId', v_restaurant_branch.id
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'ORDER_SUBMITTED', 'order', v_order_id,
    pg_catalog.jsonb_build_object(
      'idempotencyKey', p_idempotency_key, 'version', 2,
      'orderType', v_order_type
    )
  );
  v_response := dastak_v1_api.order_json(v_order_id, p_actor_id);
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 201, v_order_id
  );
  return v_response;
exception
  when unique_violation then
    raise exception using errcode = '22023',
      message = 'duplicate food selection is not allowed; combine its quantity';
end;
$$;

create function dastak_v1.guard_restaurant_order_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id or new.order_id is distinct from old.order_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.offered_at is distinct from old.offered_at then
    raise exception 'restaurant request identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'restaurant request version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'OFFERED' and new.status in ('CONFIRMED', 'DECLINED', 'RELEASED'))
    or (old.status = 'CONFIRMED' and new.status = 'RELEASED')
  ) then
    raise exception 'invalid restaurant request transition: % -> %', old.status, new.status;
  end if;
  if old.responded_at is not null
    and new.responded_at is distinct from old.responded_at then
    raise exception 'restaurant response time cannot change';
  end if;
  if old.promised_prep_minutes is not null
    and new.promised_prep_minutes is distinct from old.promised_prep_minutes then
    raise exception 'restaurant preparation promise cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger restaurant_order_requests_guard
before update on dastak_v1.restaurant_order_requests
for each row execute function dastak_v1.guard_restaurant_order_request();

create function dastak_v1.guard_restaurant_capacity_commitment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id or new.request_id is distinct from old.request_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.order_id is distinct from old.order_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.soft_threshold_snapshot is distinct from old.soft_threshold_snapshot
    or new.active_order_count_snapshot is distinct from old.active_order_count_snapshot
    or new.accepted_above_threshold is distinct from old.accepted_above_threshold
    or new.committed_at is distinct from old.committed_at then
    raise exception 'restaurant capacity commitment identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'restaurant capacity commitment version must increment exactly once';
  end if;
  if new.status is distinct from old.status
    and not (old.status = 'COMMITTED' and new.status = 'RELEASED') then
    raise exception 'invalid restaurant capacity commitment transition';
  end if;
  if old.released_at is not null and new.released_at is distinct from old.released_at then
    raise exception 'restaurant capacity release time cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger restaurant_capacity_commitments_guard
before update on dastak_v1.restaurant_capacity_commitments
for each row execute function dastak_v1.guard_restaurant_capacity_commitment();

create function dastak_v1.start_restaurant_request_after_order_matching()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid;
begin
  if new.status = 'MATCHING' and old.status is distinct from new.status
    and new.order_type in ('FOOD_ONLY', 'MIXED') then
    insert into dastak_v1.restaurant_order_requests (
      order_id, organization_id, branch_id, status, offered_at
    ) values (
      new.id, new.restaurant_organization_id, new.restaurant_branch_id,
      'OFFERED', pg_catalog.clock_timestamp()
    ) returning id into v_request_id;
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_request_id::text || ':RESTAURANT_REQUEST_OFFERED:1',
      'RESTAURANT_ORDER_REQUEST', v_request_id, 1,
      'RESTAURANT_REQUEST_OFFERED', new.customer_id,
      pg_catalog.jsonb_build_object(
        'requestId', v_request_id, 'orderId', new.id,
        'organizationId', new.restaurant_organization_id,
        'branchId', new.restaurant_branch_id
      )
    );
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      new.customer_id, 'RESTAURANT_REQUEST_OFFERED',
      'restaurant_order_request', v_request_id,
      pg_catalog.jsonb_build_object('orderId', new.id, 'branchId', new.restaurant_branch_id)
    );
  end if;
  return new;
end;
$$;

create trigger orders_start_restaurant_request
after update of status on dastak_v1.orders
for each row execute function dastak_v1.start_restaurant_request_after_order_matching();

create function dastak_v1_api.restaurant_request_json(
  p_actor_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_request dastak_v1.restaurant_order_requests%rowtype;
  v_threshold integer;
  v_active integer;
begin
  select request.* into v_request
  from dastak_v1.restaurant_order_requests request
  where request.id = p_request_id;
  if not found then raise exception using errcode = 'P0002', message = 'request not found'; end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_request.organization_id,
    'merchant.opportunities.respond', v_request.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  v_threshold := (
    dastak_v1_api.effective_setting_json(
      'restaurant.soft_active_order_threshold', v_request.branch_id,
      v_request.organization_id,
      (select service_zone_id from dastak_v1.merchant_branches where id = v_request.branch_id)
    ) #>> '{}'
  )::integer;
  select count(*) into v_active
  from dastak_v1.restaurant_capacity_commitments commitment
  where commitment.branch_id = v_request.branch_id and commitment.status = 'COMMITTED';
  return pg_catalog.jsonb_build_object(
    'id', v_request.id, 'orderId', v_request.order_id,
    'displayOrderNumber', customer_order.display_order_number,
    'status', v_request.status, 'version', v_request.version,
    'offeredAt', v_request.offered_at, 'respondedAt', v_request.responded_at,
    'promisedPrepMinutes', v_request.promised_prep_minutes,
    'responseReason', v_request.response_reason,
    'softActiveOrderThreshold', v_threshold,
    'activeOrderCount', v_active,
    'softThresholdWarning', v_active >= v_threshold,
    'softThresholdIsBlocking', false,
    'branch', pg_catalog.jsonb_build_object(
      'id', branch.id, 'displayName', branch.display_name,
      'isOpen', operating.is_open, 'acceptingOrders', operating.accepting_orders,
      'operationalVersion', operating.version
    ),
    'lines', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'orderLineId', line.id, 'menuItemId', line.food_menu_item_id,
        'name', line.product_name_snapshot, 'variant', line.variant_snapshot,
        'quantity', line.quantity, 'unitPricePaise', line.unit_price_paise,
        'selection', line.food_selection_snapshot
      ) order by line.created_at, line.id)
      from dastak_v1.order_lines line
      where line.order_id = v_request.order_id and line.line_type = 'FOOD_MENU_ITEM'
    ), '[]'::jsonb),
    'fulfilmentId', (
      select fulfilment.id from dastak_v1.fulfilments fulfilment
      where fulfilment.source_restaurant_request_id = v_request.id
    )
  )
  from dastak_v1.orders customer_order
  join dastak_v1.merchant_branches branch on branch.id = v_request.branch_id
  join dastak_v1.branch_operational_states operating on operating.branch_id = branch.id
  where customer_order.id = v_request.order_id;
end;
$$;

create function dastak_v1_api.list_restaurant_requests(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'invalid request limit';
  end if;
  return pg_catalog.jsonb_build_object('requests', coalesce((
    select pg_catalog.jsonb_agg(
      dastak_v1_api.restaurant_request_json(p_actor_id, visible.id)
      order by visible.offered_at desc, visible.id desc
    )
    from (
      select request.id, request.offered_at
      from dastak_v1.restaurant_order_requests request
      where request.status in ('OFFERED', 'CONFIRMED', 'DECLINED', 'RELEASED')
        and dastak_v1_api.actor_has_wave1_merchant_permission(
          p_actor_id, request.organization_id,
          'merchant.opportunities.respond', request.branch_id
        )
      order by request.offered_at desc, request.id desc limit p_limit
    ) visible
  ), '[]'::jsonb));
end;
$$;

create function dastak_v1_api.respond_restaurant_request(
  p_actor_id uuid,
  p_request_id uuid,
  p_response text,
  p_promised_prep_minutes integer,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'respondRestaurantRequest';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_request dastak_v1.restaurant_order_requests%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_threshold integer;
  v_active integer;
  v_fulfilment_id uuid;
  v_result jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_response not in ('CONFIRM', 'DECLINE')
    or p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200
    or (p_response = 'CONFIRM' and (p_promised_prep_minutes is null
      or p_promised_prep_minutes not between 1 and 240))
    or (p_response = 'DECLINE' and pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500) then
    raise exception using errcode = '22023', message = 'invalid restaurant response';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'requestId', p_request_id, 'response', p_response,
    'promisedPrepMinutes', p_promised_prep_minutes, 'reason', p_reason,
    'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select * into v_existing from dastak_v1.idempotency_records
  where actor_id = p_actor_id and command_name = v_command
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  join dastak_v1.restaurant_order_requests request on request.order_id = customer_order.id
  where request.id = p_request_id for update of customer_order;
  if not found then raise exception using errcode = 'P0002', message = 'request not found'; end if;
  select request.* into v_request
  from dastak_v1.restaurant_order_requests request
  where request.id = p_request_id for update;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_request.organization_id,
    'merchant.opportunities.respond', v_request.branch_id
  ) then raise exception using errcode = '42501', message = 'permission denied'; end if;
  if v_request.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'STALE_RESTAURANT_REQUEST_VERSION';
  end if;
  if v_request.status <> 'OFFERED' or v_order.status <> 'MATCHING' then
    raise exception using errcode = '55000', message = 'RESTAURANT_REQUEST_NOT_OPEN';
  end if;
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id and organization.status = 'ACTIVE'
  join dastak_v1.branch_operational_states operating
    on operating.branch_id = branch.id
  where branch.id = v_request.branch_id and branch.status = 'ACTIVE'
  for update of branch, operating;
  if not found then raise exception using errcode = '55000', message = 'RESTAURANT_NOT_OPERATIONAL'; end if;

  if p_response = 'DECLINE' then
    update dastak_v1.restaurant_order_requests request
    set status = 'DECLINED', responded_by = p_actor_id, responded_at = v_now,
        response_reason = pg_catalog.btrim(p_reason), version = request.version + 1
    where request.id = v_request.id returning * into v_request;
    update dastak_v1.orders customer_order
    set status = 'UNAVAILABLE', version = customer_order.version + 1
    where customer_order.id = v_order.id returning * into v_order;
    perform dastak_v1_api.release_order_prepayment_resources(
      v_order.id, p_actor_id, v_order.version, 'RESTAURANT_DECLINED'
    );
    insert into dastak_v1.order_state_journal (
      order_id, from_status, to_status, order_version,
      command_name, actor_id, reason
    ) values (
      v_order.id, 'MATCHING', 'UNAVAILABLE', v_order.version,
      v_command, p_actor_id, 'The selected Restaurant/Cafe declined; food is never rerouted.'
    );
  else
    if not exists (
      select 1 from dastak_v1.branch_operational_states operating
      where operating.branch_id = v_branch.id and operating.is_open
        and operating.accepting_orders
    ) or exists (
      select 1 from dastak_v1.operational_pause_controls control
      where control.active and control.scope = 'MERCHANT_BRANCH'
        and control.branch_id = v_branch.id
    ) then
      raise exception using errcode = '55000', message = 'RESTAURANT_NOT_ACCEPTING_ORDERS';
    end if;
    -- Revalidate every exact menu commitment while holding item rows.
    perform item.id
    from dastak_v1.order_lines line
    join dastak_v1.restaurant_menu_items item
      on item.id = line.food_menu_item_id and item.status = 'ACTIVE'
    join dastak_v1.restaurant_menu_categories category
      on category.id = item.category_id and category.status = 'ACTIVE'
    where line.order_id = v_order.id and line.line_type = 'FOOD_MENU_ITEM'
      and item.branch_id = v_branch.id
    order by item.id for share of item;
    if (select count(*) from dastak_v1.order_lines line
        where line.order_id = v_order.id and line.line_type = 'FOOD_MENU_ITEM')
      <> (select count(*) from dastak_v1.order_lines line
          join dastak_v1.restaurant_menu_items item
            on item.id = line.food_menu_item_id and item.status = 'ACTIVE'
          join dastak_v1.restaurant_menu_categories category
            on category.id = item.category_id and category.status = 'ACTIVE'
          where line.order_id = v_order.id and line.line_type = 'FOOD_MENU_ITEM'
            and item.branch_id = v_branch.id) then
      raise exception using errcode = '55000', message = 'MENU_COMMITMENT_NO_LONGER_AVAILABLE';
    end if;
    v_threshold := (
      dastak_v1_api.effective_setting_json(
        'restaurant.soft_active_order_threshold', v_branch.id,
        v_branch.organization_id, v_branch.service_zone_id
      ) #>> '{}'
    )::integer;
    if v_threshold < 1 then
      raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR';
    end if;
    select count(*) into v_active
    from dastak_v1.restaurant_capacity_commitments commitment
    where commitment.branch_id = v_branch.id and commitment.status = 'COMMITTED';
    update dastak_v1.restaurant_order_requests request
    set status = 'CONFIRMED', responded_by = p_actor_id, responded_at = v_now,
        promised_prep_minutes = p_promised_prep_minutes,
        response_reason = null, version = request.version + 1
    where request.id = v_request.id returning * into v_request;
    insert into dastak_v1.fulfilments (
      order_id, organization_id, branch_id,
      source_opportunity_id, source_recovery_opportunity_id,
      source_restaurant_request_id, fulfilment_type, status,
      promised_prep_minutes, committed_at
    ) values (
      v_order.id, v_branch.organization_id, v_branch.id,
      null, null, v_request.id, 'FOOD', 'RESERVED_PREPAYMENT',
      p_promised_prep_minutes, v_now
    ) returning id into v_fulfilment_id;
    insert into dastak_v1.fulfilment_lines (
      fulfilment_id, order_line_id, confirmed_quantity
    )
    select v_fulfilment_id, line.id, line.quantity
    from dastak_v1.order_lines line
    where line.order_id = v_order.id and line.line_type = 'FOOD_MENU_ITEM'
    order by line.id;
    update dastak_v1.order_lines line
    set status = 'RESERVED', version = line.version + 1
    where line.order_id = v_order.id and line.line_type = 'FOOD_MENU_ITEM'
      and line.status = 'ORDERED';
    insert into dastak_v1.restaurant_capacity_commitments (
      request_id, fulfilment_id, order_id, organization_id, branch_id,
      soft_threshold_snapshot, active_order_count_snapshot,
      accepted_above_threshold, committed_at
    ) values (
      v_request.id, v_fulfilment_id, v_order.id,
      v_branch.organization_id, v_branch.id, v_threshold, v_active + 1,
      v_active >= v_threshold, v_now
    );
    perform dastak_v1_api.coordinate_fully_secured(v_order.id, p_actor_id);
  end if;
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_request.id::text || ':RESTAURANT_' || p_response || ':' || v_request.version::text,
    'RESTAURANT_ORDER_REQUEST', v_request.id, v_request.version,
    'RESTAURANT_REQUEST_' || case when p_response = 'CONFIRM' then 'CONFIRMED' else 'DECLINED' end,
    p_actor_id, pg_catalog.jsonb_build_object(
      'orderId', v_order.id, 'requestId', v_request.id,
      'fulfilmentId', v_fulfilment_id,
      'softThresholdExceeded', p_response = 'CONFIRM' and v_active >= v_threshold
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'RESTAURANT_REQUEST_' || p_response,
    'restaurant_order_request', v_request.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id, 'fulfilmentId', v_fulfilment_id,
      'idempotencyKey', p_idempotency_key
    )
  );
  v_result := dastak_v1_api.restaurant_request_json(p_actor_id, v_request.id);
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_result, 200, v_request.id
  );
  return v_result;
end;
$$;

create function dastak_v1.release_restaurant_commitment_after_fulfilment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_reason text;
begin
  if new.source_restaurant_request_id is null
    or new.status = old.status
    or new.status not in ('RELEASED', 'PICKED_UP', 'COMPLETED') then
    return new;
  end if;
  v_reason := case new.status
    when 'RELEASED' then coalesce(new.release_reason, 'PREPAYMENT_RELEASED')
    when 'PICKED_UP' then 'PICKED_UP'
    else 'COMPLETED'
  end;
  update dastak_v1.restaurant_capacity_commitments commitment
  set status = 'RELEASED', released_at = v_now, release_reason = v_reason,
      version = commitment.version + 1
  where commitment.fulfilment_id = new.id and commitment.status = 'COMMITTED';
  if new.status = 'RELEASED' then
    update dastak_v1.restaurant_order_requests request
    set status = 'RELEASED',
        responded_at = coalesce(request.responded_at, v_now),
        released_at = v_now, release_reason = v_reason,
        version = request.version + 1
    where request.id = new.source_restaurant_request_id
      and request.status in ('OFFERED', 'CONFIRMED');
  end if;
  return new;
end;
$$;

create trigger fulfilments_release_restaurant_commitment
after update of status on dastak_v1.fulfilments
for each row execute function dastak_v1.release_restaurant_commitment_after_fulfilment();

create function dastak_v1.release_unconfirmed_restaurant_request_after_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if new.status is distinct from old.status
    and new.status in ('UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT') then
    update dastak_v1.restaurant_order_requests request
    set status = 'RELEASED',
        responded_at = coalesce(request.responded_at, v_now),
        released_at = v_now, release_reason = new.status::text,
        version = request.version + 1
    where request.order_id = new.id and request.status in ('OFFERED', 'CONFIRMED');
  end if;
  return new;
end;
$$;

create trigger orders_release_restaurant_request
after update of status on dastak_v1.orders
for each row execute function dastak_v1.release_unconfirmed_restaurant_request_after_order();

-- Prepared-food issues may be investigated and refunded, but must never enter
-- either reverse-custody path as a physical return.
create function dastak_v1.reject_prepared_food_return_line()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from dastak_v1.returns customer_return
    join dastak_v1.order_lines line on line.id = new.order_line_id
    where customer_return.id = new.return_id
      and customer_return.order_id = line.order_id
      and customer_return.physical_return_required
      and line.line_type = 'FOOD_MENU_ITEM'
  ) then
    raise exception using errcode = '55000',
      message = 'PREPARED_FOOD_PHYSICAL_RETURN_FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger return_lines_reject_prepared_food
before insert on dastak_v1.return_lines
for each row execute function dastak_v1.reject_prepared_food_return_line();

create function dastak_v1.reject_prepared_food_return_activation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.physical_return_required and exists (
    select 1
    from dastak_v1.return_lines return_line
    join dastak_v1.order_lines line on line.id = return_line.order_line_id
    where return_line.return_id = new.id and line.line_type = 'FOOD_MENU_ITEM'
  ) then
    raise exception using errcode = '55000',
      message = 'PREPARED_FOOD_PHYSICAL_RETURN_FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger returns_reject_prepared_food_activation
before update of physical_return_required on dastak_v1.returns
for each row execute function dastak_v1.reject_prepared_food_return_activation();

revoke all on function dastak_v1.reject_prepared_food_return_line(),
  dastak_v1.reject_prepared_food_return_activation()
from public, anon, authenticated, service_role;

create or replace function dastak_v1_api.pickup_route_distance_meters(
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
  v_branch_ids uuid[];
  v_distance numeric;
begin
  select pg_catalog.array_agg(branch_id order by branch_id)
    into v_branch_ids
  from (select distinct branch_id from pg_catalog.unnest(p_branch_ids) branch_id) unique_branch;
  if pg_catalog.cardinality(v_branch_ids) not between 1 and 4 then
    raise exception using errcode = '22023',
      message = 'pickup route requires one to four unique branches';
  end if;
  with recursive route(path, last_branch_id, remaining, distance_meters) as (
    select array[branch_id], branch_id,
      pg_catalog.array_remove(v_branch_ids, branch_id), 0::numeric
    from pg_catalog.unnest(v_branch_ids) branch_id
    union all
    select route.path || next_branch.branch_id,
      next_branch.branch_id,
      pg_catalog.array_remove(route.remaining, next_branch.branch_id),
      route.distance_meters + dastak_v1_api.branch_distance_meters(
        route.last_branch_id, next_branch.branch_id
      )
    from route
    cross join lateral pg_catalog.unnest(route.remaining) next_branch(branch_id)
    where pg_catalog.cardinality(route.remaining) > 0
  )
  select min(route.distance_meters
    + dastak_v1_api.branch_customer_distance_meters(p_order_id, route.last_branch_id))
    into v_distance
  from route where pg_catalog.cardinality(route.remaining) = 0;
  if v_distance is null then return null; end if;
  return pg_catalog.round(v_distance)::bigint;
end;
$$;

create or replace function dastak_v1_api.order_transport_snapshot(p_order_id uuid)
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
  v_package_count integer := 1;
  v_package_count_final boolean := false;
  v_fulfilment_count integer := 0;
  v_line record;
  v_attributes jsonb;
  v_weight numeric;
  v_volume numeric;
  v_longest numeric;
begin
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_default := v_configuration -> 'defaultSkuLogistics';
  v_profiles := v_configuration -> 'transportLoadProfiles';
  for v_line in
    select line.quantity,
      case when line.line_type = 'RETAIL_SKU' then sku.logistics_attributes
        else line.food_selection_snapshot -> 'logisticsAttributes' end as logistics_attributes
    from dastak_v1.order_lines line
    left join dastak_v1.skus sku on sku.id = line.sku_id
    where line.order_id = p_order_id
    order by line.id
  loop
    v_attributes := coalesce(v_line.logistics_attributes, '{}'::jsonb);
    if pg_catalog.jsonb_typeof(v_attributes -> 'weightGrams') = 'number'
      and pg_catalog.jsonb_typeof(v_attributes -> 'lengthMillimetres') = 'number'
      and pg_catalog.jsonb_typeof(v_attributes -> 'widthMillimetres') = 'number'
      and pg_catalog.jsonb_typeof(v_attributes -> 'heightMillimetres') = 'number'
      and (v_attributes ->> 'weightGrams')::numeric > 0
      and (v_attributes ->> 'lengthMillimetres')::numeric > 0
      and (v_attributes ->> 'widthMillimetres')::numeric > 0
      and (v_attributes ->> 'heightMillimetres')::numeric > 0 then
      v_weight := (v_attributes ->> 'weightGrams')::numeric;
      v_volume := (v_attributes ->> 'lengthMillimetres')::numeric
        * (v_attributes ->> 'widthMillimetres')::numeric
        * (v_attributes ->> 'heightMillimetres')::numeric;
      v_longest := greatest(
        (v_attributes ->> 'lengthMillimetres')::numeric,
        (v_attributes ->> 'widthMillimetres')::numeric,
        (v_attributes ->> 'heightMillimetres')::numeric
      );
    else
      v_weight := (v_default ->> 'weightGrams')::numeric;
      v_volume := (v_default ->> 'volumeCubicMillimetres')::numeric;
      v_longest := (v_default ->> 'longestSideMillimetres')::numeric;
    end if;
    v_total_weight := v_total_weight + v_weight * v_line.quantity;
    v_total_volume := v_total_volume + v_volume * v_line.quantity;
    v_longest_side := greatest(v_longest_side, v_longest);
  end loop;
  select count(*), coalesce(sum(coalesce(fulfilment.package_count, 1)), 0),
    coalesce(bool_and(fulfilment.package_count is not null), false)
  into v_fulfilment_count, v_package_count, v_package_count_final
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id and fulfilment.status <> 'RELEASED';
  if v_fulfilment_count = 0 then
    v_package_count := 1; v_package_count_final := false;
  end if;
  if v_total_weight <= 0 or v_total_volume <= 0 or v_longest_side <= 0 then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Order logistics could not be calculated from authoritative or locked fallback data.';
  end if;
  return dastak_v1_api.transport_load_snapshot(
    v_total_weight, v_total_volume, v_package_count, v_longest_side,
    v_package_count_final, v_profiles
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Order logistics or locked transport limits contain invalid numbers.';
end;
$$;

create or replace function dastak_v1_api.food_security_snapshot(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_request dastak_v1.restaurant_order_requests%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_line_count integer;
  v_secured_count integer;
  v_branch_ids uuid[];
  v_configuration jsonb;
  v_route_distance bigint;
  v_transport jsonb;
  v_reasons text[] := '{}'::text[];
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order where customer_order.id = p_order_id;
  if not found then raise exception using errcode = 'P0002', message = 'order not found'; end if;
  if v_order.order_type not in ('FOOD_ONLY', 'MIXED') then
    return pg_catalog.jsonb_build_object('required', false, 'secured', true, 'reasons', '[]'::jsonb);
  end if;
  select request.* into v_request
  from dastak_v1.restaurant_order_requests request where request.order_id = p_order_id;
  if not found or v_request.status <> 'CONFIRMED'
    or v_request.branch_id is distinct from v_order.restaurant_branch_id
    or v_request.organization_id is distinct from v_order.restaurant_organization_id then
    v_reasons := pg_catalog.array_append(v_reasons, 'RESTAURANT_CONFIRMATION_INCOMPLETE');
  end if;
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id and fulfilment.fulfilment_type = 'FOOD'
    and fulfilment.status = 'RESERVED_PREPAYMENT';
  if not found or v_fulfilment.source_restaurant_request_id is distinct from v_request.id
    or v_fulfilment.branch_id is distinct from v_order.restaurant_branch_id then
    v_reasons := pg_catalog.array_append(v_reasons, 'FOOD_FULFILMENT_NOT_RESERVED');
  end if;
  select count(*) into v_line_count from dastak_v1.order_lines line
  where line.order_id = p_order_id and line.line_type = 'FOOD_MENU_ITEM';
  select count(*) into v_secured_count
  from dastak_v1.order_lines line
  where line.order_id = p_order_id and line.line_type = 'FOOD_MENU_ITEM'
    and exists (
      select 1 from dastak_v1.fulfilment_lines fulfilment_line
      where fulfilment_line.fulfilment_id = v_fulfilment.id
        and fulfilment_line.order_line_id = line.id
        and fulfilment_line.confirmed_quantity = line.quantity
    );
  if v_line_count = 0 or v_secured_count <> v_line_count
    or (select count(*) from dastak_v1.fulfilment_lines fulfilment_line
        where fulfilment_line.fulfilment_id = v_fulfilment.id) <> v_line_count then
    v_reasons := pg_catalog.array_append(v_reasons, 'FOOD_LINE_COMMITMENT_INCOMPLETE');
  end if;
  if not exists (
    select 1 from dastak_v1.restaurant_capacity_commitments commitment
    where commitment.request_id = v_request.id
      and commitment.fulfilment_id = v_fulfilment.id
      and commitment.status = 'COMMITTED'
  ) then
    v_reasons := pg_catalog.array_append(v_reasons, 'RESTAURANT_CAPACITY_NOT_COMMITTED');
  end if;
  if not exists (
    select 1 from dastak_v1.merchant_branches branch
    join dastak_v1.merchant_organizations organization
      on organization.id = branch.organization_id
    where branch.id = v_order.restaurant_branch_id
      and branch.status = 'ACTIVE' and organization.status = 'ACTIVE'
  ) then
    v_reasons := pg_catalog.array_append(v_reasons, 'RESTAURANT_NOT_OPERATIONAL');
  end if;
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(p_order_id);
  if not (v_transport ->> 'feasible')::boolean then
    v_reasons := pg_catalog.array_append(v_reasons, 'TRANSPORT_LOAD_INFEASIBLE');
  end if;
  select pg_catalog.array_agg(distinct fulfilment.branch_id order by fulfilment.branch_id)
    into v_branch_ids
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = p_order_id and fulfilment.status = 'RESERVED_PREPAYMENT';
  if pg_catalog.cardinality(v_branch_ids) not between 1 and 4 then
    v_reasons := pg_catalog.array_append(v_reasons, 'PICKUP_STOP_COUNT_INVALID');
  else
    v_route_distance := dastak_v1_api.pickup_route_distance_meters(p_order_id, v_branch_ids);
    if v_route_distance is null
      or v_route_distance > (v_configuration ->> 'maxPickupRouteMeters')::bigint then
      v_reasons := pg_catalog.array_append(v_reasons, 'PICKUP_ROUTE_INFEASIBLE');
    end if;
  end if;
  return pg_catalog.jsonb_build_object(
    'required', true, 'secured', pg_catalog.cardinality(v_reasons) = 0,
    'reasons', pg_catalog.to_jsonb(v_reasons),
    'foodLineCount', v_line_count, 'securedFoodLineCount', v_secured_count,
    'restaurantBranchId', v_order.restaurant_branch_id,
    'pickupBranchCount', pg_catalog.cardinality(v_branch_ids),
    'routeDistanceMeters', v_route_distance, 'transport', v_transport,
    'softCapacity', true
  );
end;
$$;

alter function dastak_v1_api.order_json(uuid, uuid)
  rename to order_json_pre_restaurant;

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
  v_result jsonb;
  v_order dastak_v1.orders%rowtype;
begin
  v_result := dastak_v1_api.order_json_pre_restaurant(p_order_id, p_customer_id);
  if v_result is null then return null; end if;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id and customer_order.customer_id = p_customer_id;
  v_result := pg_catalog.jsonb_set(v_result, '{lines}', coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(
      pg_catalog.jsonb_build_object(
        'id', line.id, 'lineType', line.line_type,
        'skuId', line.sku_id, 'menuItemId', line.food_menu_item_id,
        'name', line.product_name_snapshot, 'variant', line.variant_snapshot,
        'packSize', line.pack_size_snapshot, 'quantity', line.quantity,
        'unitPricePaise', line.unit_price_paise,
        'lineTotalPaise', line.line_total_paise, 'status', line.status,
        'foodSelection', line.food_selection_snapshot
      )
    ) order by line.created_at, line.id)
    from dastak_v1.order_lines line where line.order_id = p_order_id
  ), '[]'::jsonb), true);
  if v_order.order_type in ('FOOD_ONLY', 'MIXED') then
    v_result := v_result || pg_catalog.jsonb_build_object(
      'restaurant', (
        select pg_catalog.jsonb_build_object(
          'organizationId', organization.id,
          'branchId', branch.id,
          'name', organization.display_name,
          'branchName', branch.display_name,
          'imageKey', branch.address_snapshot ->> 'imageKey'
        )
        from dastak_v1.merchant_organizations organization
        join dastak_v1.merchant_branches branch
          on branch.id = v_order.restaurant_branch_id
         and branch.organization_id = organization.id
        where organization.id = v_order.restaurant_organization_id
      )
    );
  end if;
  return v_result;
end;
$$;

alter function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  rename to merchant_fulfilment_json_pre_restaurant;

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
begin
  v_result := dastak_v1_api.merchant_fulfilment_json_pre_restaurant(
    p_actor_id, p_fulfilment_id
  );
  select fulfilment.* into v_fulfilment from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;
  if v_fulfilment.fulfilment_type = 'FOOD' then
    v_result := pg_catalog.jsonb_set(v_result, '{lines}', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'orderLineId', line.id, 'menuItemId', line.food_menu_item_id,
        'name', line.product_name_snapshot, 'variant', line.variant_snapshot,
        'quantity', fulfilment_line.confirmed_quantity,
        'selection', line.food_selection_snapshot
      ) order by line.created_at, line.id)
      from dastak_v1.fulfilment_lines fulfilment_line
      join dastak_v1.order_lines line on line.id = fulfilment_line.order_line_id
      where fulfilment_line.fulfilment_id = p_fulfilment_id
    ), '[]'::jsonb), true);
  end if;
  return v_result;
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_pre_restaurant;

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
  v_trace := dastak_v1_api.admin_execution_trace_pre_restaurant(p_actor_id, p_order_id);
  v_trace := pg_catalog.jsonb_set(
    v_trace,
    '{order,orderType}',
    (
      select pg_catalog.to_jsonb(parent_order.order_type::text)
      from dastak_v1.orders parent_order
      where parent_order.id = p_order_id
    ),
    true
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace,
    '{failureAndFinance,customerIssues}',
    coalesce((
      select pg_catalog.jsonb_agg(
        issue_value || pg_catalog.jsonb_build_object(
          'lineType', line.line_type,
          'preparedFood', line.line_type = 'FOOD_MENU_ITEM',
          'physicalReturnAllowed', line.line_type = 'RETAIL_SKU'
        ) order by issue_value ->> 'reportedAt', issue_value ->> 'id'
      )
      from pg_catalog.jsonb_array_elements(
        coalesce(v_trace #> '{failureAndFinance,customerIssues}', '[]'::jsonb)
      ) issue_value
      left join dastak_v1.order_lines line
        on line.id = (issue_value ->> 'orderLineId')::uuid
    ), '[]'::jsonb),
    true
  );
  return v_trace || pg_catalog.jsonb_build_object(
    'restaurant', pg_catalog.jsonb_build_object(
      'request', (
        select pg_catalog.jsonb_build_object(
          'id', request.id, 'organizationId', request.organization_id,
          'restaurantName', organization.display_name,
          'branchId', request.branch_id, 'branchName', branch.display_name,
          'status', request.status,
          'offeredAt', request.offered_at, 'respondedBy', request.responded_by,
          'respondedAt', request.responded_at,
          'promisedPrepMinutes', request.promised_prep_minutes,
          'responseReason', request.response_reason,
          'releasedAt', request.released_at, 'releaseReason', request.release_reason,
          'version', request.version
        ) from dastak_v1.restaurant_order_requests request
        join dastak_v1.merchant_organizations organization
          on organization.id = request.organization_id
        join dastak_v1.merchant_branches branch on branch.id = request.branch_id
        where request.order_id = p_order_id
      ),
      'commitment', (
        select pg_catalog.jsonb_build_object(
          'id', commitment.id, 'fulfilmentId', commitment.fulfilment_id,
          'status', commitment.status,
          'softThreshold', commitment.soft_threshold_snapshot,
          'activeOrderCountAtAcceptance', commitment.active_order_count_snapshot,
          'acceptedAboveThreshold', commitment.accepted_above_threshold,
          'committedAt', commitment.committed_at,
          'releasedAt', commitment.released_at,
          'releaseReason', commitment.release_reason,
          'version', commitment.version
        ) from dastak_v1.restaurant_capacity_commitments commitment
        where commitment.order_id = p_order_id
      ),
      'foodLines', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', line.id, 'menuItemId', line.food_menu_item_id,
          'name', line.product_name_snapshot, 'quantity', line.quantity,
          'unitPricePaise', line.unit_price_paise,
          'selection', line.food_selection_snapshot, 'status', line.status
        ) order by line.created_at, line.id)
        from dastak_v1.order_lines line
        where line.order_id = p_order_id and line.line_type = 'FOOD_MENU_ITEM'
      ), '[]'::jsonb),
      'preparedFoodPhysicallyReturnable', false
    )
  );
end;
$$;

create function public.dastak_v1_customer_restaurants(
  p_query text default null,
  p_limit integer default 50
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.list_customer_restaurants(auth.uid(), p_query, p_limit);
$$;

create function public.dastak_v1_merchant_restaurant_menu(p_branch_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.merchant_restaurant_menu(auth.uid(), p_branch_id);
$$;

create function public.dastak_v1_upsert_restaurant_menu_entity(
  p_branch_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_expected_version bigint,
  p_payload jsonb,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.upsert_restaurant_menu_entity(
    auth.uid(), p_branch_id, p_entity_type, p_entity_id,
    p_expected_version, p_payload, p_idempotency_key
  );
$$;

create function public.dastak_v1_restaurant_requests(p_limit integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.list_restaurant_requests(auth.uid(), p_limit);
$$;

create function public.dastak_v1_respond_restaurant_request(
  p_request_id uuid,
  p_response text,
  p_promised_prep_minutes integer,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.respond_restaurant_request(
    auth.uid(), p_request_id, p_response, p_promised_prep_minutes,
    p_reason, p_expected_version, p_idempotency_key
  );
$$;

revoke all on function dastak_v1_api.restaurant_menu_json(uuid, boolean),
  dastak_v1_api.list_customer_restaurants(uuid, text, integer),
  dastak_v1_api.merchant_restaurant_menu(uuid, uuid),
  dastak_v1_api.upsert_restaurant_menu_entity(uuid, uuid, text, uuid, bigint, jsonb, text),
  dastak_v1_api.restaurant_selection_snapshot(uuid, uuid, jsonb),
  dastak_v1_api.restaurant_request_json(uuid, uuid),
  dastak_v1_api.list_restaurant_requests(uuid, integer),
  dastak_v1_api.respond_restaurant_request(uuid, uuid, text, integer, text, bigint, text),
  dastak_v1_api.order_json_pre_restaurant(uuid, uuid),
  dastak_v1_api.order_json(uuid, uuid),
  dastak_v1_api.merchant_fulfilment_json_pre_restaurant(uuid, uuid),
  dastak_v1_api.merchant_fulfilment_json(uuid, uuid),
  dastak_v1_api.admin_execution_trace_pre_restaurant(uuid, uuid),
  dastak_v1_api.admin_execution_trace(uuid, uuid)
from public, anon, authenticated, service_role;

revoke all on function public.dastak_v1_customer_restaurants(text, integer),
  public.dastak_v1_merchant_restaurant_menu(uuid),
  public.dastak_v1_upsert_restaurant_menu_entity(uuid, text, uuid, bigint, jsonb, text),
  public.dastak_v1_restaurant_requests(integer),
  public.dastak_v1_respond_restaurant_request(uuid, text, integer, text, bigint, text)
from public, anon, authenticated;

grant execute on function dastak_v1_api.restaurant_menu_json(uuid, boolean),
  dastak_v1_api.list_customer_restaurants(uuid, text, integer),
  dastak_v1_api.merchant_restaurant_menu(uuid, uuid),
  dastak_v1_api.upsert_restaurant_menu_entity(uuid, uuid, text, uuid, bigint, jsonb, text),
  dastak_v1_api.restaurant_selection_snapshot(uuid, uuid, jsonb),
  dastak_v1_api.restaurant_request_json(uuid, uuid),
  dastak_v1_api.list_restaurant_requests(uuid, integer),
  dastak_v1_api.respond_restaurant_request(uuid, uuid, text, integer, text, bigint, text),
  dastak_v1_api.order_json_pre_restaurant(uuid, uuid),
  dastak_v1_api.order_json(uuid, uuid),
  dastak_v1_api.merchant_fulfilment_json_pre_restaurant(uuid, uuid),
  dastak_v1_api.merchant_fulfilment_json(uuid, uuid),
  dastak_v1_api.admin_execution_trace_pre_restaurant(uuid, uuid),
  dastak_v1_api.admin_execution_trace(uuid, uuid)
to authenticated;

grant execute on function public.dastak_v1_customer_restaurants(text, integer),
  public.dastak_v1_merchant_restaurant_menu(uuid),
  public.dastak_v1_upsert_restaurant_menu_entity(uuid, text, uuid, bigint, jsonb, text),
  public.dastak_v1_restaurant_requests(integer),
  public.dastak_v1_respond_restaurant_request(uuid, text, integer, text, bigint, text)
to authenticated;

comment on table dastak_v1.restaurant_capacity_commitments is
  'Binding pre-payment Restaurant/Cafe operational commitments. The threshold snapshot is advisory and never a hard cutoff.';
comment on function public.dastak_v1_respond_restaurant_request(
  uuid, text, integer, text, bigint, text
) is 'Confirm or decline the selected Restaurant/Cafe request. Confirmation never reroutes and may exceed the soft active-order threshold.';
