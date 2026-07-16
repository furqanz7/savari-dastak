create table private.merchant_stores (
  id uuid primary key default gen_random_uuid(),
  merchant_account_id uuid not null unique references public.accounts(id) on delete cascade,
  service_zone_id uuid not null references public.service_zones(id),
  name text not null check (char_length(trim(name)) between 1 and 120),
  address text not null check (char_length(trim(address)) between 1 and 300),
  location extensions.geometry(Point, 4326) not null,
  is_published boolean not null default false,
  accepting_orders boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not accepting_orders or is_published)
);

create index merchant_stores_location_gix
  on private.merchant_stores using gist (location);
create index merchant_stores_service_zone_idx
  on private.merchant_stores (service_zone_id, is_published);

create table private.catalogue_categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references private.merchant_stores(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  display_order integer not null default 0 check (display_order between 0 and 10000),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, id)
);

create unique index catalogue_categories_store_name_uidx
  on private.catalogue_categories (store_id, lower(name));

create table private.catalogue_products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references private.merchant_stores(id) on delete cascade,
  category_id uuid not null,
  name text not null check (char_length(trim(name)) between 1 and 160),
  description text check (
    description is null or char_length(description) between 1 and 1000
  ),
  unit_label text not null check (char_length(trim(unit_label)) between 1 and 40),
  price_paise integer not null check (price_paise between 1 and 100000000),
  image_object_path text,
  availability text not null check (availability in ('in_stock', 'out_of_stock')),
  catalogue_kind text not null check (
    catalogue_kind in ('general', 'otc_medicine', 'prescription_medicine', 'paan_corner')
  ),
  restricted_approval_state text not null check (
    restricted_approval_state in (
      'not_applicable', 'pending', 'approved', 'rejected', 'suspended'
    )
  ),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (store_id, category_id)
    references private.catalogue_categories(store_id, id),
  check (
    (catalogue_kind = 'general' and restricted_approval_state = 'not_applicable')
    or (
      catalogue_kind <> 'general'
      and restricted_approval_state in ('pending', 'approved', 'rejected', 'suspended')
    )
  )
);

create index catalogue_products_store_category_idx
  on private.catalogue_products (store_id, category_id, is_active);

alter table private.merchant_stores enable row level security;
alter table private.catalogue_categories enable row level security;
alter table private.catalogue_products enable row level security;

revoke all on table private.merchant_stores from public, anon, authenticated;
revoke all on table private.catalogue_categories from public, anon, authenticated;
revoke all on table private.catalogue_products from public, anon, authenticated;

grant select, insert, update on table private.merchant_stores to service_role;
grant select, insert, update on table private.catalogue_categories to service_role;
grant select, insert, update on table private.catalogue_products to service_role;

create policy dastak_catalogue_image_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-catalogue'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'merchant'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(btrim(split_part(name, '/', 3)), '') is not null
  and split_part(name, '/', 3) not in ('.', '..')
);

create policy dastak_catalogue_image_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-catalogue'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'merchant'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(btrim(split_part(name, '/', 3)), '') is not null
  and split_part(name, '/', 3) not in ('.', '..')
);

create policy dastak_catalogue_image_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'dastak-catalogue'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'merchant'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(btrim(split_part(name, '/', 3)), '') is not null
  and split_part(name, '/', 3) not in ('.', '..')
)
with check (
  bucket_id = 'dastak-catalogue'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'merchant'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(btrim(split_part(name, '/', 3)), '') is not null
  and split_part(name, '/', 3) not in ('.', '..')
);

create or replace function private.catalogue_store_json(
  store_row private.merchant_stores
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'storeId', (store_row).id,
    'name', (store_row).name,
    'address', (store_row).address,
    'location', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((store_row).location),
      'longitude', extensions.st_x((store_row).location)
    ),
    'serviceZoneId', (store_row).service_zone_id,
    'isPublished', (store_row).is_published,
    'acceptingOrders', (store_row).accepting_orders
  );
$$;

create or replace function private.catalogue_category_json(
  category_row private.catalogue_categories
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'categoryId', (category_row).id,
    'storeId', (category_row).store_id,
    'name', (category_row).name,
    'displayOrder', (category_row).display_order,
    'isActive', (category_row).is_active
  );
$$;

create or replace function private.catalogue_product_json(
  product_row private.catalogue_products
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'productId', (product_row).id,
    'storeId', (product_row).store_id,
    'categoryId', (product_row).category_id,
    'name', (product_row).name,
    'description', (product_row).description,
    'unitLabel', (product_row).unit_label,
    'price', pg_catalog.jsonb_build_object('paise', (product_row).price_paise),
    'imageObjectPath', (product_row).image_object_path,
    'availability', (product_row).availability,
    'catalogueKind', (product_row).catalogue_kind,
    'restrictedApprovalState', (product_row).restricted_approval_state,
    'isActive', (product_row).is_active
  );
$$;

revoke execute on function private.catalogue_store_json(private.merchant_stores)
  from public, anon, authenticated;
revoke execute on function private.catalogue_category_json(private.catalogue_categories)
  from public, anon, authenticated;
revoke execute on function private.catalogue_product_json(private.catalogue_products)
  from public, anon, authenticated;
grant execute on function private.catalogue_store_json(private.merchant_stores)
  to service_role;
grant execute on function private.catalogue_category_json(private.catalogue_categories)
  to service_role;
grant execute on function private.catalogue_product_json(private.catalogue_products)
  to service_role;

create or replace function public.upsert_merchant_store(
  p_account_id uuid,
  p_name text,
  p_address text,
  p_latitude double precision,
  p_longitude double precision,
  p_is_published boolean,
  p_accepting_orders boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_merchant_store';
  v_existing_dedup private.request_deduplication%rowtype;
  v_store private.merchant_stores%rowtype;
  v_before_state jsonb;
  v_zone_id uuid;
  v_location extensions.geometry(Point, 4326);
  v_response_body jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_name is null
    or pg_catalog.char_length(pg_catalog.btrim(p_name)) not between 1 and 120
    or p_address is null
    or pg_catalog.char_length(pg_catalog.btrim(p_address)) not between 1 and 300
    or p_latitude is null or p_latitude < -90 or p_latitude > 90
    or p_longitude is null or p_longitude < -180 or p_longitude > 180
    or p_is_published is null or p_accepting_orders is null
    or (p_accepting_orders and not p_is_published)
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant store request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing_dedup.request_digest = p_request_digest then
      response_body := v_existing_dedup.response_body;
      response_status := v_existing_dedup.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_location := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude),
    4326
  );

  select zone.id
  into v_zone_id
  from public.service_zones as zone
  where zone.active = true
    and extensions.st_covers(zone.boundary, v_location)
  order by zone.created_at, zone.id
  limit 1;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'The store must be inside an active Dastak service area.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  select store.*
  into v_store
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id
  for update;

  if found then
    v_before_state := private.catalogue_store_json(v_store);
    update private.merchant_stores as store
    set service_zone_id = v_zone_id,
        name = p_name,
        address = p_address,
        location = v_location,
        is_published = p_is_published,
        accepting_orders = p_accepting_orders,
        updated_at = pg_catalog.now()
    where store.id = v_store.id
    returning store.* into v_store;
  else
    insert into private.merchant_stores (
      merchant_account_id,
      service_zone_id,
      name,
      address,
      location,
      is_published,
      accepting_orders
    ) values (
      p_account_id,
      v_zone_id,
      p_name,
      p_address,
      v_location,
      p_is_published,
      p_accepting_orders
    )
    returning * into v_store;
  end if;

  v_response_body := private.catalogue_store_json(v_store);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id,
    'merchant_store_upserted',
    'merchant_store',
    v_store.id,
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.upsert_catalogue_category(
  p_account_id uuid,
  p_category_id uuid,
  p_name text,
  p_display_order integer,
  p_is_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_catalogue_category';
  v_existing_dedup private.request_deduplication%rowtype;
  v_store private.merchant_stores%rowtype;
  v_category private.catalogue_categories%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_name is null
    or pg_catalog.char_length(pg_catalog.btrim(p_name)) not between 1 and 80
    or p_display_order is null or p_display_order not between 0 and 10000
    or p_is_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The catalogue category request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing_dedup.request_digest = p_request_digest then
      response_body := v_existing_dedup.response_body;
      response_status := v_existing_dedup.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select store.*
  into v_store
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'store_required',
        'message', 'Create the merchant store before adding catalogue categories.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if exists (
    select 1
    from private.catalogue_categories as category
    where category.store_id = v_store.id
      and pg_catalog.lower(category.name) = pg_catalog.lower(p_name)
      and (p_category_id is null or category.id <> p_category_id)
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_name_conflict',
        'message', 'A category with this name already exists.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if p_category_id is null then
    insert into private.catalogue_categories (
      store_id, name, display_order, is_active
    ) values (
      v_store.id, p_name, p_display_order, p_is_active
    )
    returning * into v_category;
  else
    select category.*
    into v_category
    from private.catalogue_categories as category
    where category.id = p_category_id
      and category.store_id = v_store.id
    for update;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'catalogue_category_not_found',
          'message', 'The catalogue category was not found.'
        )
      );
      response_status := 404;
      return next;
      return;
    end if;

    v_before_state := private.catalogue_category_json(v_category);
    update private.catalogue_categories as category
    set name = p_name,
        display_order = p_display_order,
        is_active = p_is_active,
        updated_at = pg_catalog.now()
    where category.id = v_category.id
    returning category.* into v_category;
  end if;

  v_response_body := private.catalogue_category_json(v_category);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id,
    'catalogue_category_upserted',
    'catalogue_category',
    v_category.id,
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.upsert_catalogue_product(
  p_account_id uuid,
  p_product_id uuid,
  p_category_id uuid,
  p_name text,
  p_description text,
  p_unit_label text,
  p_price_paise integer,
  p_image_object_path text,
  p_availability text,
  p_catalogue_kind text,
  p_is_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_catalogue_product';
  v_existing_dedup private.request_deduplication%rowtype;
  v_store private.merchant_stores%rowtype;
  v_product private.catalogue_products%rowtype;
  v_before_state jsonb;
  v_restricted_state text;
  v_response_body jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_category_id is null
    or p_name is null
    or pg_catalog.char_length(pg_catalog.btrim(p_name)) not between 1 and 160
    or (
      p_description is not null
      and pg_catalog.char_length(p_description) not between 1 and 1000
    )
    or p_unit_label is null
    or pg_catalog.char_length(pg_catalog.btrim(p_unit_label)) not between 1 and 40
    or p_price_paise is null or p_price_paise not between 1 and 100000000
    or p_availability is null
    or p_availability not in ('in_stock', 'out_of_stock')
    or p_catalogue_kind is null
    or p_catalogue_kind not in (
      'general', 'otc_medicine', 'prescription_medicine', 'paan_corner'
    )
    or p_is_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The catalogue product request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if p_image_object_path is not null and (
    p_image_object_path <> (
      'merchant/' || p_account_id::text || '/' ||
      pg_catalog.split_part(p_image_object_path, '/', 3)
    )
    or pg_catalog.array_length(
      pg_catalog.string_to_array(p_image_object_path, '/'),
      1
    ) <> 3
    or nullif(
      pg_catalog.btrim(pg_catalog.split_part(p_image_object_path, '/', 3)),
      ''
    ) is null
    or pg_catalog.split_part(p_image_object_path, '/', 3) in ('.', '..')
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The catalogue image path is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing_dedup.request_digest = p_request_digest then
      response_body := v_existing_dedup.response_body;
      response_status := v_existing_dedup.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select store.*
  into v_store
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'store_required',
        'message', 'Create the merchant store before adding catalogue products.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if not exists (
    select 1
    from private.catalogue_categories as category
    where category.id = p_category_id
      and category.store_id = v_store.id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_category_not_found',
        'message', 'The catalogue category was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  if p_image_object_path is not null and not exists (
    select 1
    from storage.objects as object
    where object.bucket_id = 'dastak-catalogue'
      and object.name = p_image_object_path
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_image_not_found',
        'message', 'Upload the catalogue image before assigning it to a product.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  v_restricted_state := case
    when p_catalogue_kind = 'general' then 'not_applicable'
    else 'pending'
  end;

  if p_product_id is null then
    insert into private.catalogue_products (
      store_id,
      category_id,
      name,
      description,
      unit_label,
      price_paise,
      image_object_path,
      availability,
      catalogue_kind,
      restricted_approval_state,
      is_active
    ) values (
      v_store.id,
      p_category_id,
      p_name,
      p_description,
      p_unit_label,
      p_price_paise,
      p_image_object_path,
      p_availability,
      p_catalogue_kind,
      v_restricted_state,
      p_is_active
    )
    returning * into v_product;
  else
    select product.*
    into v_product
    from private.catalogue_products as product
    where product.id = p_product_id
      and product.store_id = v_store.id
    for update;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'catalogue_product_not_found',
          'message', 'The catalogue product was not found.'
        )
      );
      response_status := 404;
      return next;
      return;
    end if;

    v_before_state := private.catalogue_product_json(v_product);
    update private.catalogue_products as product
    set category_id = p_category_id,
        name = p_name,
        description = p_description,
        unit_label = p_unit_label,
        price_paise = p_price_paise,
        image_object_path = p_image_object_path,
        availability = p_availability,
        catalogue_kind = p_catalogue_kind,
        restricted_approval_state = v_restricted_state,
        is_active = p_is_active,
        updated_at = pg_catalog.now()
    where product.id = v_product.id
    returning product.* into v_product;
  end if;

  v_response_body := private.catalogue_product_json(v_product);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id,
    'catalogue_product_upserted',
    'catalogue_product',
    v_product.id,
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_merchant_catalogue(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_store private.merchant_stores%rowtype;
  v_categories jsonb;
  v_products jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  select store.*
  into v_store
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'serviceZoneId', null,
      'stores', '[]'::jsonb,
      'categories', '[]'::jsonb,
      'products', '[]'::jsonb
    );
    response_status := 200;
    return next;
    return;
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_category_json(category)
      order by category.display_order, category.id
    ),
    '[]'::jsonb
  )
  into v_categories
  from private.catalogue_categories as category
  where category.store_id = v_store.id;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_product_json(product)
      order by product.name, product.id
    ),
    '[]'::jsonb
  )
  into v_products
  from private.catalogue_products as product
  where product.store_id = v_store.id;

  response_body := pg_catalog.jsonb_build_object(
    'serviceZoneId', v_store.service_zone_id,
    'stores', pg_catalog.jsonb_build_array(private.catalogue_store_json(v_store)),
    'categories', v_categories,
    'products', v_products
  );
  response_status := 200;
  return next;
end;
$$;

create or replace function public.browse_catalogue(
  p_account_id uuid,
  p_latitude double precision,
  p_longitude double precision
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_zone_id uuid;
  v_location extensions.geometry(Point, 4326);
  v_stores jsonb;
  v_categories jsonb;
  v_products jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_latitude is null or p_latitude < -90 or p_latitude > 90
    or p_longitude is null or p_longitude < -180 or p_longitude > 180
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The catalogue location is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  v_location := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude),
    4326
  );

  select zone.id
  into v_zone_id
  from public.service_zones as zone
  where zone.active = true
    and extensions.st_covers(zone.boundary, v_location)
  order by zone.created_at, zone.id
  limit 1;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'Dastak is not available at this location.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_store_json(store)
      order by store.name, store.id
    ),
    '[]'::jsonb
  )
  into v_stores
  from private.merchant_stores as store
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  where store.service_zone_id = v_zone_id
    and store.is_published = true;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_category_json(category)
      order by store.name, category.display_order, category.id
    ),
    '[]'::jsonb
  )
  into v_categories
  from private.catalogue_categories as category
  join private.merchant_stores as store on store.id = category.store_id
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  where store.service_zone_id = v_zone_id
    and store.is_published = true
    and category.is_active = true;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_product_json(product)
      order by store.name, category.display_order, product.name, product.id
    ),
    '[]'::jsonb
  )
  into v_products
  from private.catalogue_products as product
  join private.catalogue_categories as category
    on category.id = product.category_id
    and category.store_id = product.store_id
  join private.merchant_stores as store on store.id = product.store_id
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  where store.service_zone_id = v_zone_id
    and store.is_published = true
    and category.is_active = true
    and product.is_active = true
    and product.catalogue_kind = 'general'
    and product.restricted_approval_state = 'not_applicable';

  response_body := pg_catalog.jsonb_build_object(
    'serviceZoneId', v_zone_id,
    'stores', v_stores,
    'categories', v_categories,
    'products', v_products
  );
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.upsert_merchant_store(
  uuid, text, text, double precision, double precision,
  boolean, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_merchant_store(
  uuid, text, text, double precision, double precision,
  boolean, boolean, text, text
) to service_role;

revoke execute on function public.upsert_catalogue_category(
  uuid, uuid, text, integer, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_catalogue_category(
  uuid, uuid, text, integer, boolean, text, text
) to service_role;

revoke execute on function public.upsert_catalogue_product(
  uuid, uuid, uuid, text, text, text, integer,
  text, text, text, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_catalogue_product(
  uuid, uuid, uuid, text, text, text, integer,
  text, text, text, boolean, text, text
) to service_role;

revoke execute on function public.get_merchant_catalogue(uuid)
  from public, anon, authenticated;
grant execute on function public.get_merchant_catalogue(uuid) to service_role;

revoke execute on function public.browse_catalogue(
  uuid, double precision, double precision
) from public, anon, authenticated;
grant execute on function public.browse_catalogue(
  uuid, double precision, double precision
) to service_role;
