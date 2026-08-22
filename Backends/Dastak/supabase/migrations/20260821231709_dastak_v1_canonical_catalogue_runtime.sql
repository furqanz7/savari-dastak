-- Canonical retail catalogue runtime for the first Dastak V1 launch slice.
-- Retail merchant identity remains private; clients receive only Dastak-owned
-- category, subcategory, brand and SKU projections.

create function dastak_v1.is_valid_sku_logistics(p_attributes jsonb)
returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_key text;
begin
  if pg_catalog.jsonb_typeof(p_attributes) <> 'object' then
    return false;
  end if;

  for v_key in select pg_catalog.jsonb_object_keys(p_attributes)
  loop
    if v_key not in (
      'weightGrams',
      'lengthMillimetres',
      'widthMillimetres',
      'heightMillimetres',
      'temperatureClass',
      'fragile',
      'bulky'
    ) then
      return false;
    end if;
  end loop;

  if p_attributes ? 'weightGrams' and (
    pg_catalog.jsonb_typeof(p_attributes -> 'weightGrams') <> 'number'
    or p_attributes ->> 'weightGrams' !~ '^[1-9][0-9]*$'
    or (p_attributes ->> 'weightGrams')::numeric > 1000000
  ) then
    return false;
  end if;

  if p_attributes ? 'lengthMillimetres' and (
    pg_catalog.jsonb_typeof(p_attributes -> 'lengthMillimetres') <> 'number'
    or p_attributes ->> 'lengthMillimetres' !~ '^[1-9][0-9]*$'
    or (p_attributes ->> 'lengthMillimetres')::numeric > 10000
  ) then
    return false;
  end if;

  if p_attributes ? 'widthMillimetres' and (
    pg_catalog.jsonb_typeof(p_attributes -> 'widthMillimetres') <> 'number'
    or p_attributes ->> 'widthMillimetres' !~ '^[1-9][0-9]*$'
    or (p_attributes ->> 'widthMillimetres')::numeric > 10000
  ) then
    return false;
  end if;

  if p_attributes ? 'heightMillimetres' and (
    pg_catalog.jsonb_typeof(p_attributes -> 'heightMillimetres') <> 'number'
    or p_attributes ->> 'heightMillimetres' !~ '^[1-9][0-9]*$'
    or (p_attributes ->> 'heightMillimetres')::numeric > 10000
  ) then
    return false;
  end if;

  if p_attributes ? 'temperatureClass' and (
    pg_catalog.jsonb_typeof(p_attributes -> 'temperatureClass') <> 'string'
    or p_attributes ->> 'temperatureClass' not in ('AMBIENT', 'CHILLED', 'FROZEN')
  ) then
    return false;
  end if;

  if p_attributes ? 'fragile'
    and pg_catalog.jsonb_typeof(p_attributes -> 'fragile') <> 'boolean' then
    return false;
  end if;
  if p_attributes ? 'bulky'
    and pg_catalog.jsonb_typeof(p_attributes -> 'bulky') <> 'boolean' then
    return false;
  end if;

  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

alter table dastak_v1.skus
  add column barcode text,
  add column logistics_attributes jsonb not null default '{}'::jsonb,
  add column search_document tsvector generated always as (
    pg_catalog.setweight(
      pg_catalog.to_tsvector(
        'pg_catalog.simple'::regconfig,
        coalesce(canonical_name, '')
      ),
      'A'
    )
    || pg_catalog.setweight(
      pg_catalog.to_tsvector(
        'pg_catalog.simple'::regconfig,
        coalesce(variant_name, '') || ' '
          || coalesce(pack_size, '') || ' '
          || coalesce(barcode, '')
      ),
      'B'
    )
    || pg_catalog.setweight(
      pg_catalog.to_tsvector(
        'pg_catalog.simple'::regconfig,
        coalesce(description, '')
      ),
      'C'
    )
  ) stored;

alter table dastak_v1.skus
  add constraint skus_variant_name_length check (
    variant_name is null
    or char_length(trim(variant_name)) between 1 and 100
  ),
  add constraint skus_description_length check (
    description is null or char_length(description) <= 2000
  ),
  add constraint skus_image_key_length check (
    image_key is null or char_length(trim(image_key)) between 1 and 500
  ),
  add constraint skus_barcode_format check (
    barcode is null or barcode ~ '^[0-9A-Za-z][0-9A-Za-z._-]{3,63}$'
  ),
  add constraint skus_logistics_valid check (
    dastak_v1.is_valid_sku_logistics(logistics_attributes)
  );

create unique index skus_barcode_uidx
  on dastak_v1.skus (barcode)
  where barcode is not null;
create index skus_search_gin
  on dastak_v1.skus using gin (search_document);
create index categories_customer_browse_idx
  on dastak_v1.categories (status, sort_order, name, id);
create index subcategories_customer_browse_idx
  on dastak_v1.subcategories (category_id, status, sort_order, name, id);

insert into dastak_v1.permission_definitions (
  permission_key,
  description,
  sensitivity
) values
  ('platform.catalogue.read', 'Read the canonical catalogue and catalogue operating configuration.', 'SENSITIVE'),
  ('platform.settings.read', 'Read protected platform configuration without changing it.', 'SENSITIVE');

insert into dastak_v1.permission_bundles (
  id,
  bundle_key,
  display_name,
  scope,
  description
) values (
  '10000000-0000-4000-8000-000000000006',
  'catalogue_admin',
  'Catalogue admin',
  'PLATFORM',
  'Manage Dastak canonical catalogue truth and inspect catalogue configuration.'
);

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key) values
  ('10000000-0000-4000-8000-000000000006', 'platform.catalogue.read'),
  ('10000000-0000-4000-8000-000000000006', 'platform.catalogue.manage'),
  ('10000000-0000-4000-8000-000000000006', 'platform.settings.read');

create index permission_bundle_permissions_permission_key_idx
  on dastak_v1.permission_bundle_permissions (permission_key);

create table dastak_v1.platform_permission_grants (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id),
  bundle_id uuid not null references dastak_v1.permission_bundles(id),
  granted_by uuid not null references public.accounts(id),
  grant_reason text not null check (char_length(trim(grant_reason)) between 3 and 500),
  granted_at timestamptz not null default now(),
  revoked_by uuid references public.accounts(id),
  revoke_reason text check (
    revoke_reason is null or char_length(trim(revoke_reason)) between 3 and 500
  ),
  revoked_at timestamptz,
  version bigint not null default 1 check (version > 0),
  check (
    (revoked_at is null and revoked_by is null and revoke_reason is null)
    or (revoked_at is not null and revoked_by is not null and revoke_reason is not null)
  )
);

create unique index platform_permission_grants_active_uidx
  on dastak_v1.platform_permission_grants (account_id, bundle_id)
  where revoked_at is null;
create index platform_permission_grants_account_idx
  on dastak_v1.platform_permission_grants (account_id);
create index platform_permission_grants_bundle_idx
  on dastak_v1.platform_permission_grants (bundle_id);
create index platform_permission_grants_granted_by_idx
  on dastak_v1.platform_permission_grants (granted_by);
create index platform_permission_grants_revoked_by_idx
  on dastak_v1.platform_permission_grants (revoked_by);

create table dastak_v1.platform_permission_grant_history (
  id bigint generated always as identity primary key,
  grant_id uuid not null,
  action text not null check (action in ('GRANTED', 'REVOKED')),
  actor_id uuid not null references public.accounts(id),
  grant_snapshot jsonb not null check (jsonb_typeof(grant_snapshot) = 'object'),
  occurred_at timestamptz not null default now()
);

create index platform_permission_grant_history_actor_idx
  on dastak_v1.platform_permission_grant_history (actor_id);

create function dastak_v1.guard_platform_permission_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from dastak_v1.permission_bundles bundle
    where bundle.id = new.bundle_id
      and bundle.scope = 'PLATFORM'
  ) then
    raise exception using errcode = '22023', message = 'platform permission bundle required';
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
      or new.account_id is distinct from old.account_id
      or new.bundle_id is distinct from old.bundle_id
      or new.granted_by is distinct from old.granted_by
      or new.grant_reason is distinct from old.grant_reason
      or new.granted_at is distinct from old.granted_at then
      raise exception 'platform permission grant identity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'platform permission grant version must increment exactly once';
    end if;
    if old.revoked_at is not null then
      raise exception 'revoked platform permission grant is immutable';
    end if;
  end if;

  return new;
end;
$$;

create function dastak_v1.record_platform_permission_grant_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or (old.revoked_at is null and new.revoked_at is not null) then
    insert into dastak_v1.platform_permission_grant_history (
      grant_id,
      action,
      actor_id,
      grant_snapshot
    ) values (
      new.id,
      case when new.revoked_at is null then 'GRANTED' else 'REVOKED' end,
      case when new.revoked_at is null then new.granted_by else new.revoked_by end,
      pg_catalog.to_jsonb(new)
    );
  end if;
  return new;
end;
$$;

create trigger platform_permission_grants_guard
before insert or update on dastak_v1.platform_permission_grants
for each row execute function dastak_v1.guard_platform_permission_grant();
create trigger platform_permission_grants_history
after insert or update on dastak_v1.platform_permission_grants
for each row execute function dastak_v1.record_platform_permission_grant_history();
create trigger platform_permission_grants_no_delete
before delete on dastak_v1.platform_permission_grants
for each row execute function dastak_v1.reject_delete();
create trigger platform_permission_grant_history_immutable
before update or delete on dastak_v1.platform_permission_grant_history
for each row execute function dastak_v1.reject_mutation();

alter table dastak_v1.platform_permission_grants enable row level security;
alter table dastak_v1.platform_permission_grant_history enable row level security;
revoke all on dastak_v1.platform_permission_grants
  from public, anon, authenticated, service_role;
revoke all on dastak_v1.platform_permission_grant_history
  from public, anon, authenticated, service_role;
revoke all on sequence dastak_v1.platform_permission_grant_history_id_seq
  from public, anon, authenticated, service_role;
grant select on dastak_v1.platform_permission_grants to service_role;
grant select on dastak_v1.platform_permission_grant_history to service_role;

create function dastak_v1_api.actor_has_platform_permission(
  p_actor_id uuid,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor_id is not null
    and (
      public.is_active_owner(p_actor_id)
      or exists (
        select 1
        from dastak_v1.platform_permission_grants permission_grant
        join dastak_v1.permission_bundles bundle
          on bundle.id = permission_grant.bundle_id
          and bundle.scope = 'PLATFORM'
          and bundle.active
        join dastak_v1.permission_bundle_permissions bundle_permission
          on bundle_permission.bundle_id = bundle.id
        join private.account_memberships membership
          on membership.account_id = permission_grant.account_id
          and membership.role = 'owner'
        where permission_grant.account_id = p_actor_id
          and permission_grant.revoked_at is null
          and bundle_permission.permission_key = p_permission_key
          and (
            membership.suspended_until is null
            or membership.suspended_until <= pg_catalog.now()
          )
      )
    );
$$;

create function dastak_v1_api.assert_platform_permission(
  p_actor_id uuid,
  p_permission_key text
)
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
  if not dastak_v1_api.actor_has_platform_permission(p_actor_id, p_permission_key) then
    raise exception using errcode = '42501', message = 'platform permission required';
  end if;
end;
$$;

create function dastak_v1.catalogue_prefix_query(p_query text)
returns tsquery
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_query_text text;
begin
  select pg_catalog.string_agg(token || ':*', ' & ' order by ordinal)
  into v_query_text
  from pg_catalog.regexp_split_to_table(
    pg_catalog.btrim(
      pg_catalog.regexp_replace(pg_catalog.lower(p_query), '[^[:alnum:]]+', ' ', 'g')
    ),
    '[[:space:]]+'
  ) with ordinality as tokenized(token, ordinal)
  where token <> '';

  if v_query_text is null then
    return null;
  end if;
  return pg_catalog.to_tsquery('pg_catalog.simple'::regconfig, v_query_text);
end;
$$;

create function dastak_v1_api.customer_catalogue(
  p_actor_id uuid,
  p_query text,
  p_category_id uuid,
  p_subcategory_id uuid,
  p_limit integer,
  p_after_name text,
  p_after_sku_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := nullif(pg_catalog.btrim(coalesce(p_query, '')), '');
  v_search tsquery;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 250);
  v_categories jsonb;
  v_subcategories jsonb;
  v_skus jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
  v_version timestamptz;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);

  if v_query is not null and char_length(v_query) > 80 then
    raise exception using errcode = '22023', message = 'catalogue search is too long';
  end if;
  if (p_after_name is null) <> (p_after_sku_id is null) then
    raise exception using errcode = '22023', message = 'complete catalogue cursor required';
  end if;
  if p_category_id is not null and p_subcategory_id is not null and not exists (
    select 1
    from dastak_v1.subcategories subcategory
    where subcategory.id = p_subcategory_id
      and subcategory.category_id = p_category_id
  ) then
    raise exception using errcode = '22023', message = 'subcategory is outside category';
  end if;

  if v_query is not null then
    v_search := dastak_v1.catalogue_prefix_query(v_query);
    if v_search is null then
      raise exception using errcode = '22023', message = 'catalogue search is invalid';
    end if;
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', category.id,
        'name', category.name,
        'slug', category.slug,
        'imageKey', category.image_key,
        'sortOrder', category.sort_order
      ) order by category.sort_order, category.name, category.id
    ),
    '[]'::jsonb
  ) into v_categories
  from dastak_v1.categories category
  where category.status = 'ACTIVE'
    and exists (
      select 1
      from dastak_v1.subcategories subcategory
      join dastak_v1.skus sku on sku.subcategory_id = subcategory.id
      left join dastak_v1.brands brand on brand.id = sku.brand_id
      where subcategory.category_id = category.id
        and subcategory.status = 'ACTIVE'
        and sku.status = 'ACTIVE'
        and (brand.id is null or brand.status = 'ACTIVE')
    );

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', subcategory.id,
        'categoryId', subcategory.category_id,
        'name', subcategory.name,
        'slug', subcategory.slug,
        'imageKey', subcategory.image_key,
        'sortOrder', subcategory.sort_order
      ) order by category.sort_order, subcategory.sort_order, subcategory.name, subcategory.id
    ),
    '[]'::jsonb
  ) into v_subcategories
  from dastak_v1.subcategories subcategory
  join dastak_v1.categories category on category.id = subcategory.category_id
  where category.status = 'ACTIVE'
    and subcategory.status = 'ACTIVE'
    and exists (
      select 1
      from dastak_v1.skus sku
      left join dastak_v1.brands brand on brand.id = sku.brand_id
      where sku.subcategory_id = subcategory.id
        and sku.status = 'ACTIVE'
        and (brand.id is null or brand.status = 'ACTIVE')
    );

  with matched as materialized (
    select
      sku.id,
      sku.subcategory_id,
      subcategory.category_id,
      sku.canonical_name,
      sku.slug,
      sku.variant_name,
      sku.pack_size,
      sku.description,
      sku.image_key,
      sku.barcode,
      sku.list_price_paise,
      sku.selling_price_paise,
      sku.currency_code,
      sku.logistics_attributes,
      brand.id as brand_id,
      brand.name as brand_name,
      brand.slug as brand_slug
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory
      on subcategory.id = sku.subcategory_id
      and subcategory.status = 'ACTIVE'
    join dastak_v1.categories category
      on category.id = subcategory.category_id
      and category.status = 'ACTIVE'
    left join dastak_v1.brands brand
      on brand.id = sku.brand_id
    where sku.status = 'ACTIVE'
      and (brand.id is null or brand.status = 'ACTIVE')
      and (p_category_id is null or subcategory.category_id = p_category_id)
      and (p_subcategory_id is null or sku.subcategory_id = p_subcategory_id)
      and (
        v_search is null
        or sku.search_document @@ v_search
        or pg_catalog.to_tsvector(
          'pg_catalog.simple'::regconfig,
          coalesce(brand.name, '') || ' ' || subcategory.name || ' ' || category.name
        ) @@ v_search
      )
      and (
        p_after_name is null
        or (pg_catalog.lower(sku.canonical_name), sku.id)
          > (pg_catalog.lower(p_after_name), p_after_sku_id)
      )
    order by pg_catalog.lower(sku.canonical_name), sku.id
    limit v_limit + 1
  ), selected as (
    select *
    from matched
    order by pg_catalog.lower(canonical_name), id
    limit v_limit
  )
  select
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              'id', selected.id,
              'categoryId', selected.category_id,
              'subcategoryId', selected.subcategory_id,
              'brand', case when selected.brand_id is null then null else
                pg_catalog.jsonb_build_object(
                  'id', selected.brand_id,
                  'name', selected.brand_name,
                  'slug', selected.brand_slug
                )
              end,
              'name', selected.canonical_name,
              'slug', selected.slug,
              'variant', selected.variant_name,
              'packSize', selected.pack_size,
              'description', selected.description,
              'imageKey', selected.image_key,
              'barcode', selected.barcode,
              'listPricePaise', selected.list_price_paise,
              'sellingPricePaise', selected.selling_price_paise,
              'currencyCode', selected.currency_code,
              'logisticsAttributes', selected.logistics_attributes
            )
          ) order by pg_catalog.lower(selected.canonical_name), selected.id
        )
        from selected
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from matched),
    (
      select pg_catalog.jsonb_build_object(
        'name', selected.canonical_name,
        'skuId', selected.id
      )
      from selected
      order by pg_catalog.lower(selected.canonical_name) desc, selected.id desc
      limit 1
    )
  into v_skus, v_has_more, v_next_cursor;

  if not v_has_more then
    v_next_cursor := null;
  end if;

  select pg_catalog.max(version_at) into v_version
  from (
    select pg_catalog.max(category.updated_at) as version_at from dastak_v1.categories category
    union all
    select pg_catalog.max(subcategory.updated_at) from dastak_v1.subcategories subcategory
    union all
    select pg_catalog.max(brand.updated_at) from dastak_v1.brands brand
    union all
    select pg_catalog.max(sku.updated_at) from dastak_v1.skus sku
  ) versions;

  return pg_catalog.jsonb_build_object(
    'catalogueVersion', v_version,
    'categories', v_categories,
    'subcategories', v_subcategories,
    'skus', v_skus,
    'nextCursor', v_next_cursor
  );
end;
$$;

create function dastak_v1_api.admin_catalogue_snapshot(
  p_actor_id uuid,
  p_sku_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_sku_limit, 1000), 1), 1000);
  v_sku_count bigint;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.catalogue.read');

  select count(*) into v_sku_count from dastak_v1.skus;

  select pg_catalog.jsonb_build_object(
    'categories', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', category.id,
          'name', category.name,
          'slug', category.slug,
          'imageKey', category.image_key,
          'status', category.status,
          'sortOrder', category.sort_order,
          'version', category.version,
          'updatedAt', category.updated_at
        ) order by category.sort_order, category.name, category.id
      ) from dastak_v1.categories category
    ), '[]'::jsonb),
    'subcategories', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', subcategory.id,
          'categoryId', subcategory.category_id,
          'name', subcategory.name,
          'slug', subcategory.slug,
          'imageKey', subcategory.image_key,
          'status', subcategory.status,
          'sortOrder', subcategory.sort_order,
          'version', subcategory.version,
          'updatedAt', subcategory.updated_at
        ) order by category.sort_order, subcategory.sort_order, subcategory.name
      )
      from dastak_v1.subcategories subcategory
      join dastak_v1.categories category on category.id = subcategory.category_id
    ), '[]'::jsonb),
    'brands', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', brand.id,
          'name', brand.name,
          'slug', brand.slug,
          'imageKey', brand.image_key,
          'status', brand.status,
          'version', brand.version,
          'updatedAt', brand.updated_at
        ) order by brand.name, brand.id
      ) from dastak_v1.brands brand
    ), '[]'::jsonb),
    'skus', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', sku.id,
          'categoryId', subcategory.category_id,
          'subcategoryId', sku.subcategory_id,
          'brandId', sku.brand_id,
          'name', sku.canonical_name,
          'slug', sku.slug,
          'variant', sku.variant_name,
          'packSize', sku.pack_size,
          'description', sku.description,
          'imageKey', sku.image_key,
          'barcode', sku.barcode,
          'listPricePaise', sku.list_price_paise,
          'sellingPricePaise', sku.selling_price_paise,
          'currencyCode', sku.currency_code,
          'taxRateBps', sku.tax_rate_bps,
          'logisticsAttributes', sku.logistics_attributes,
          'status', sku.status,
          'selectionCount', (
            select count(*)
            from dastak_v1.merchant_sku_selections selection
            where selection.sku_id = sku.id
              and selection.state = 'SELECTED'
          ),
          'version', sku.version,
          'updatedAt', sku.updated_at
        ) order by pg_catalog.lower(sku.canonical_name), sku.id
      )
      from (
        select limited_sku.*
        from dastak_v1.skus limited_sku
        order by pg_catalog.lower(limited_sku.canonical_name), limited_sku.id
        limit v_limit
      ) sku
      join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
    ), '[]'::jsonb),
    'skuCount', v_sku_count,
    'truncated', v_sku_count > v_limit,
    'configuration', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', definition.setting_key,
          'value', coalesce(setting.setting_value, definition.default_value),
          'explicit', setting.id is not null,
          'valid', dastak_v1.validate_setting_value(
            definition.setting_key,
            coalesce(setting.setting_value, definition.default_value)
          ),
          'required', definition.requires_explicit_value
        ) order by definition.setting_key
      )
      from dastak_v1.setting_definitions definition
      left join dastak_v1.platform_settings setting
        on setting.setting_key = definition.setting_key
        and setting.scope_type = 'GLOBAL'
        and setting.scope_id is null
      where definition.setting_key in (
        'matching.wave1_timeout_seconds',
        'matching.retail_radius_meters',
        'retail.prep_time_options_minutes',
        'retail.branch_default_capacity',
        'commerce.currency_code',
        'commerce.prepaid_only',
        'commerce.allow_cod',
        'commerce.allow_substitutions',
        'commerce.allow_scheduled_orders'
      )
    ), '[]'::jsonb),
    'branches', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', branch.id,
          'name', branch.display_name,
          'organizationName', organization.display_name,
          'merchantType', organization.merchant_type,
          'status', branch.status,
          'isOpen', coalesce(operating.is_open, false),
          'acceptingOrders', coalesce(operating.accepting_orders, false),
          'capacityLimit', branch.capacity_limit,
          'selectedSkuCount', (
            select count(*)
            from dastak_v1.merchant_sku_selections selection
            where selection.branch_id = branch.id
              and selection.state = 'SELECTED'
          )
        ) order by organization.display_name, branch.display_name, branch.id
      )
      from dastak_v1.merchant_branches branch
      join dastak_v1.merchant_organizations organization
        on organization.id = branch.organization_id
      left join dastak_v1.branch_operational_states operating
        on operating.branch_id = branch.id
      where organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
    ), '[]'::jsonb)
  ) into v_response;

  return v_response;
end;
$$;

create function dastak_v1_api.import_catalogue(
  p_actor_id uuid,
  p_idempotency_key text,
  p_catalogue jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'importCatalogue';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_item jsonb;
  v_slug text;
  v_parent_slug text;
  v_subcategory_slug text;
  v_brand_slug text;
  v_name text;
  v_status dastak_v1.catalogue_status;
  v_category_id uuid;
  v_subcategory_id uuid;
  v_brand_id uuid;
  v_sort_order integer;
  v_list_price bigint;
  v_selling_price bigint;
  v_tax_rate integer;
  v_barcode text;
  v_logistics jsonb;
  v_import_id uuid := gen_random_uuid();
  v_category_count integer := 0;
  v_subcategory_count integer := 0;
  v_brand_count integer := 0;
  v_sku_count integer := 0;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.catalogue.manage');

  if p_idempotency_key is null or char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;
  if p_catalogue is null or pg_catalog.jsonb_typeof(p_catalogue) <> 'object' then
    raise exception using errcode = '22023', message = 'catalogue import must be an object';
  end if;
  if exists (
    select 1 from pg_catalog.jsonb_object_keys(p_catalogue) key
    where key not in ('categories', 'subcategories', 'brands', 'skus')
  ) then
    raise exception using errcode = '22023', message = 'catalogue import contains unknown fields';
  end if;

  if pg_catalog.jsonb_typeof(coalesce(p_catalogue -> 'categories', '[]'::jsonb)) <> 'array'
    or pg_catalog.jsonb_array_length(coalesce(p_catalogue -> 'categories', '[]'::jsonb)) > 50
    or pg_catalog.jsonb_typeof(coalesce(p_catalogue -> 'subcategories', '[]'::jsonb)) <> 'array'
    or pg_catalog.jsonb_array_length(coalesce(p_catalogue -> 'subcategories', '[]'::jsonb)) > 250
    or pg_catalog.jsonb_typeof(coalesce(p_catalogue -> 'brands', '[]'::jsonb)) <> 'array'
    or pg_catalog.jsonb_array_length(coalesce(p_catalogue -> 'brands', '[]'::jsonb)) > 250
    or pg_catalog.jsonb_typeof(coalesce(p_catalogue -> 'skus', '[]'::jsonb)) <> 'array'
    or pg_catalog.jsonb_array_length(coalesce(p_catalogue -> 'skus', '[]'::jsonb)) > 1000 then
    raise exception using errcode = '22023', message = 'catalogue import batch is invalid or too large';
  end if;

  v_request_hash := dastak_v1_api.request_hash(p_catalogue);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-catalogue-write', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select * into v_existing
  from dastak_v1.idempotency_records
  where actor_id = p_actor_id
    and command_name = v_command
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023', message = 'idempotency key conflict';
  end if;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      coalesce(p_catalogue -> 'categories', '[]'::jsonb)
    )
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = '22023', message = 'category must be an object';
    end if;
    v_slug := pg_catalog.lower(pg_catalog.btrim(coalesce(v_item ->> 'slug', '')));
    v_name := pg_catalog.btrim(coalesce(v_item ->> 'name', ''));
    if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      or char_length(v_name) not between 1 and 100
      or coalesce(v_item ->> 'sortOrder', '0') !~ '^[0-9]+$' then
      raise exception using errcode = '22023', message = 'category fields are invalid';
    end if;
    v_sort_order := coalesce((v_item ->> 'sortOrder')::integer, 0);
    if v_sort_order > 10000 then
      raise exception using errcode = '22023', message = 'category sortOrder is invalid';
    end if;
    v_status := upper(coalesce(v_item ->> 'status', 'DRAFT'))::dastak_v1.catalogue_status;

    insert into dastak_v1.categories (
      name, slug, image_key, status, sort_order, created_by
    ) values (
      v_name,
      v_slug,
      nullif(pg_catalog.btrim(v_item ->> 'imageKey'), ''),
      v_status,
      v_sort_order,
      p_actor_id
    )
    on conflict (slug) do update set
      name = excluded.name,
      image_key = excluded.image_key,
      status = excluded.status,
      sort_order = excluded.sort_order,
      updated_at = pg_catalog.now(),
      version = dastak_v1.categories.version + 1;
    v_category_count := v_category_count + 1;
  end loop;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      coalesce(p_catalogue -> 'subcategories', '[]'::jsonb)
    )
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = '22023', message = 'subcategory must be an object';
    end if;
    v_parent_slug := pg_catalog.lower(pg_catalog.btrim(coalesce(v_item ->> 'categorySlug', '')));
    v_slug := pg_catalog.lower(pg_catalog.btrim(coalesce(v_item ->> 'slug', '')));
    v_name := pg_catalog.btrim(coalesce(v_item ->> 'name', ''));
    if v_parent_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      or char_length(v_name) not between 1 and 100
      or coalesce(v_item ->> 'sortOrder', '0') !~ '^[0-9]+$' then
      raise exception using errcode = '22023', message = 'subcategory fields are invalid';
    end if;
    select category.id into v_category_id
    from dastak_v1.categories category
    where category.slug = v_parent_slug;
    if v_category_id is null then
      raise exception using errcode = '22023', message = 'subcategory category was not found';
    end if;
    v_sort_order := coalesce((v_item ->> 'sortOrder')::integer, 0);
    if v_sort_order > 10000 then
      raise exception using errcode = '22023', message = 'subcategory sortOrder is invalid';
    end if;
    v_status := upper(coalesce(v_item ->> 'status', 'DRAFT'))::dastak_v1.catalogue_status;

    insert into dastak_v1.subcategories (
      category_id, name, slug, image_key, status, sort_order, created_by
    ) values (
      v_category_id,
      v_name,
      v_slug,
      nullif(pg_catalog.btrim(v_item ->> 'imageKey'), ''),
      v_status,
      v_sort_order,
      p_actor_id
    )
    on conflict (category_id, slug) do update set
      name = excluded.name,
      image_key = excluded.image_key,
      status = excluded.status,
      sort_order = excluded.sort_order,
      updated_at = pg_catalog.now(),
      version = dastak_v1.subcategories.version + 1;
    v_subcategory_count := v_subcategory_count + 1;
  end loop;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      coalesce(p_catalogue -> 'brands', '[]'::jsonb)
    )
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = '22023', message = 'brand must be an object';
    end if;
    v_slug := pg_catalog.lower(pg_catalog.btrim(coalesce(v_item ->> 'slug', '')));
    v_name := pg_catalog.btrim(coalesce(v_item ->> 'name', ''));
    if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      or char_length(v_name) not between 1 and 100 then
      raise exception using errcode = '22023', message = 'brand fields are invalid';
    end if;
    v_status := upper(coalesce(v_item ->> 'status', 'DRAFT'))::dastak_v1.catalogue_status;

    insert into dastak_v1.brands (
      name, slug, image_key, status, created_by
    ) values (
      v_name,
      v_slug,
      nullif(pg_catalog.btrim(v_item ->> 'imageKey'), ''),
      v_status,
      p_actor_id
    )
    on conflict (slug) do update set
      name = excluded.name,
      image_key = excluded.image_key,
      status = excluded.status,
      updated_at = pg_catalog.now(),
      version = dastak_v1.brands.version + 1;
    v_brand_count := v_brand_count + 1;
  end loop;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      coalesce(p_catalogue -> 'skus', '[]'::jsonb)
    )
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = '22023', message = 'SKU must be an object';
    end if;
    v_parent_slug := pg_catalog.lower(pg_catalog.btrim(coalesce(v_item ->> 'categorySlug', '')));
    v_subcategory_slug := pg_catalog.lower(
      pg_catalog.btrim(coalesce(v_item ->> 'subcategorySlug', ''))
    );
    v_brand_slug := nullif(
      pg_catalog.lower(pg_catalog.btrim(coalesce(v_item ->> 'brandSlug', ''))),
      ''
    );
    v_slug := pg_catalog.lower(pg_catalog.btrim(coalesce(v_item ->> 'slug', '')));
    v_name := pg_catalog.btrim(coalesce(v_item ->> 'canonicalName', ''));
    if v_parent_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      or v_subcategory_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      or char_length(v_name) not between 1 and 160
      or char_length(pg_catalog.btrim(coalesce(v_item ->> 'packSize', ''))) not between 1 and 80
      or coalesce(v_item ->> 'listPricePaise', '') !~ '^[0-9]+$'
      or coalesce(v_item ->> 'sellingPricePaise', '') !~ '^[0-9]+$'
      or coalesce(v_item ->> 'taxRateBps', '0') !~ '^[0-9]+$' then
      raise exception using errcode = '22023', message = 'SKU fields are invalid';
    end if;

    select subcategory.id into v_subcategory_id
    from dastak_v1.subcategories subcategory
    join dastak_v1.categories category on category.id = subcategory.category_id
    where category.slug = v_parent_slug
      and subcategory.slug = v_subcategory_slug;
    if v_subcategory_id is null then
      raise exception using errcode = '22023', message = 'SKU subcategory was not found';
    end if;

    v_brand_id := null;
    if v_brand_slug is not null then
      select brand.id into v_brand_id
      from dastak_v1.brands brand
      where brand.slug = v_brand_slug;
      if v_brand_id is null then
        raise exception using errcode = '22023', message = 'SKU brand was not found';
      end if;
    end if;

    v_list_price := (v_item ->> 'listPricePaise')::bigint;
    v_selling_price := (v_item ->> 'sellingPricePaise')::bigint;
    v_tax_rate := coalesce((v_item ->> 'taxRateBps')::integer, 0);
    if v_list_price > 100000000
      or v_selling_price > v_list_price
      or v_tax_rate > 10000
      or upper(coalesce(v_item ->> 'currencyCode', 'INR')) <> 'INR' then
      raise exception using errcode = '22023', message = 'SKU price fields are invalid';
    end if;

    v_barcode := nullif(pg_catalog.btrim(coalesce(v_item ->> 'barcode', '')), '');
    v_logistics := coalesce(v_item -> 'logisticsAttributes', '{}'::jsonb);
    if not dastak_v1.is_valid_sku_logistics(v_logistics) then
      raise exception using errcode = '22023', message = 'SKU logistics attributes are invalid';
    end if;
    if v_barcode is not null and exists (
      select 1
      from dastak_v1.skus existing_sku
      where existing_sku.barcode = v_barcode
        and existing_sku.slug <> v_slug
    ) then
      raise exception using errcode = '22023', message = 'SKU barcode belongs to another SKU';
    end if;

    v_status := upper(coalesce(v_item ->> 'status', 'DRAFT'))::dastak_v1.catalogue_status;
    insert into dastak_v1.skus (
      subcategory_id,
      brand_id,
      canonical_name,
      slug,
      variant_name,
      pack_size,
      description,
      image_key,
      barcode,
      list_price_paise,
      selling_price_paise,
      currency_code,
      tax_rate_bps,
      logistics_attributes,
      status,
      created_by
    ) values (
      v_subcategory_id,
      v_brand_id,
      v_name,
      v_slug,
      nullif(pg_catalog.btrim(v_item ->> 'variant'), ''),
      pg_catalog.btrim(v_item ->> 'packSize'),
      nullif(pg_catalog.btrim(v_item ->> 'description'), ''),
      nullif(pg_catalog.btrim(v_item ->> 'imageKey'), ''),
      v_barcode,
      v_list_price,
      v_selling_price,
      'INR',
      v_tax_rate,
      v_logistics,
      v_status,
      p_actor_id
    )
    on conflict (slug) do update set
      subcategory_id = excluded.subcategory_id,
      brand_id = excluded.brand_id,
      canonical_name = excluded.canonical_name,
      variant_name = excluded.variant_name,
      pack_size = excluded.pack_size,
      description = excluded.description,
      image_key = excluded.image_key,
      barcode = excluded.barcode,
      list_price_paise = excluded.list_price_paise,
      selling_price_paise = excluded.selling_price_paise,
      currency_code = excluded.currency_code,
      tax_rate_bps = excluded.tax_rate_bps,
      logistics_attributes = excluded.logistics_attributes,
      status = excluded.status,
      updated_at = pg_catalog.now(),
      version = dastak_v1.skus.version + 1;
    v_sku_count := v_sku_count + 1;
  end loop;

  v_response := pg_catalog.jsonb_build_object(
    'importId', v_import_id,
    'counts', pg_catalog.jsonb_build_object(
      'categories', v_category_count,
      'subcategories', v_subcategory_count,
      'brands', v_brand_count,
      'skus', v_sku_count
    ),
    'completedAt', pg_catalog.now()
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'CATALOGUE_IMPORTED',
    'catalogue_import',
    v_import_id,
    pg_catalog.jsonb_build_object(
      'idempotencyKey', p_idempotency_key,
      'counts', v_response -> 'counts'
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
  ) values (
    v_import_id::text || ':CATALOGUE_IMPORTED:1',
    'CATALOGUE_IMPORT',
    v_import_id,
    1,
    'CATALOGUE_IMPORTED',
    p_actor_id,
    v_response
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
    v_import_id
  );

  return v_response;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'catalogue import contains invalid values';
end;
$$;

create function dastak_v1_api.update_catalogue_sku(
  p_actor_id uuid,
  p_sku_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'updateCatalogueSku';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_sku dastak_v1.skus%rowtype;
  v_list_price bigint;
  v_selling_price bigint;
  v_status dastak_v1.catalogue_status;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.catalogue.manage');

  if p_idempotency_key is null or char_length(p_idempotency_key) not between 1 and 200
    or p_patch is null or pg_catalog.jsonb_typeof(p_patch) <> 'object'
    or p_patch = '{}'::jsonb
    or exists (
      select 1 from pg_catalog.jsonb_object_keys(p_patch) key
      where key not in ('listPricePaise', 'sellingPricePaise', 'status')
    ) then
    raise exception using errcode = '22023', message = 'SKU patch is invalid';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'skuId', p_sku_id,
      'expectedVersion', p_expected_version,
      'patch', p_patch
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-catalogue-write', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select * into v_existing
  from dastak_v1.idempotency_records
  where actor_id = p_actor_id
    and command_name = v_command
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023', message = 'idempotency key conflict';
  end if;

  select * into v_sku
  from dastak_v1.skus sku
  where sku.id = p_sku_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SKU not found';
  end if;
  if v_sku.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale SKU version';
  end if;

  if p_patch ? 'listPricePaise'
    and (
      pg_catalog.jsonb_typeof(p_patch -> 'listPricePaise') <> 'number'
      or p_patch ->> 'listPricePaise' !~ '^[0-9]+$'
    ) then
    raise exception using errcode = '22023', message = 'list price is invalid';
  end if;
  if p_patch ? 'sellingPricePaise'
    and (
      pg_catalog.jsonb_typeof(p_patch -> 'sellingPricePaise') <> 'number'
      or p_patch ->> 'sellingPricePaise' !~ '^[0-9]+$'
    ) then
    raise exception using errcode = '22023', message = 'selling price is invalid';
  end if;

  v_list_price := case when p_patch ? 'listPricePaise'
    then (p_patch ->> 'listPricePaise')::bigint else v_sku.list_price_paise end;
  v_selling_price := case when p_patch ? 'sellingPricePaise'
    then (p_patch ->> 'sellingPricePaise')::bigint else v_sku.selling_price_paise end;
  v_status := case when p_patch ? 'status'
    then upper(p_patch ->> 'status')::dastak_v1.catalogue_status else v_sku.status end;

  if v_list_price > 100000000 or v_selling_price > v_list_price then
    raise exception using errcode = '22023', message = 'SKU price exceeds MRP';
  end if;

  update dastak_v1.skus
  set list_price_paise = v_list_price,
      selling_price_paise = v_selling_price,
      status = v_status,
      updated_at = pg_catalog.now(),
      version = version + 1
  where id = v_sku.id
  returning * into v_sku;

  v_response := pg_catalog.jsonb_build_object(
    'id', v_sku.id,
    'name', v_sku.canonical_name,
    'slug', v_sku.slug,
    'listPricePaise', v_sku.list_price_paise,
    'sellingPricePaise', v_sku.selling_price_paise,
    'currencyCode', v_sku.currency_code,
    'status', v_sku.status,
    'version', v_sku.version,
    'updatedAt', v_sku.updated_at
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'CATALOGUE_SKU_UPDATED',
    'catalogue_sku',
    v_sku.id,
    pg_catalog.jsonb_build_object(
      'idempotencyKey', p_idempotency_key,
      'fromVersion', p_expected_version,
      'toVersion', v_sku.version,
      'changedFields', (
        select pg_catalog.jsonb_agg(key order by key)
        from pg_catalog.jsonb_object_keys(p_patch) key
      )
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
  ) values (
    v_sku.id::text || ':CATALOGUE_SKU_UPDATED:' || v_sku.version::text,
    'CATALOGUE_SKU',
    v_sku.id,
    v_sku.version,
    'CATALOGUE_SKU_UPDATED',
    p_actor_id,
    v_response
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
    v_sku.id
  );

  return v_response;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'SKU patch contains invalid values';
end;
$$;

create function public.dastak_v1_customer_catalogue(
  p_query text default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_limit integer default 100,
  p_after_name text default null,
  p_after_sku_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.customer_catalogue(
    auth.uid(),
    p_query,
    p_category_id,
    p_subcategory_id,
    p_limit,
    p_after_name,
    p_after_sku_id
  );
$$;

create function public.dastak_v1_admin_catalogue_snapshot(
  p_sku_limit integer default 1000
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_catalogue_snapshot(auth.uid(), p_sku_limit);
$$;

create function public.dastak_v1_import_catalogue(
  p_idempotency_key text,
  p_catalogue jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.import_catalogue(auth.uid(), p_idempotency_key, p_catalogue);
$$;

create function public.dastak_v1_update_catalogue_sku(
  p_sku_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_patch jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.update_catalogue_sku(
    auth.uid(),
    p_sku_id,
    p_idempotency_key,
    p_expected_version,
    p_patch
  );
$$;

revoke execute on function public.dastak_v1_customer_catalogue(
  text, uuid, uuid, integer, text, uuid
) from public, anon, authenticated;
revoke execute on function public.dastak_v1_admin_catalogue_snapshot(integer)
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_import_catalogue(text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_update_catalogue_sku(
  uuid, text, bigint, jsonb
) from public, anon, authenticated;

grant execute on function dastak_v1_api.actor_has_platform_permission(uuid, text)
  to authenticated;
grant execute on function dastak_v1_api.assert_platform_permission(uuid, text)
  to authenticated;
grant execute on function dastak_v1_api.customer_catalogue(
  uuid, text, uuid, uuid, integer, text, uuid
) to authenticated;
grant execute on function dastak_v1_api.admin_catalogue_snapshot(uuid, integer)
  to authenticated;
grant execute on function dastak_v1_api.import_catalogue(uuid, text, jsonb)
  to authenticated;
grant execute on function dastak_v1_api.update_catalogue_sku(
  uuid, uuid, text, bigint, jsonb
) to authenticated;

grant execute on function public.dastak_v1_customer_catalogue(
  text, uuid, uuid, integer, text, uuid
) to authenticated;
grant execute on function public.dastak_v1_admin_catalogue_snapshot(integer)
  to authenticated;
grant execute on function public.dastak_v1_import_catalogue(text, jsonb)
  to authenticated;
grant execute on function public.dastak_v1_update_catalogue_sku(
  uuid, text, bigint, jsonb
) to authenticated;

comment on function public.dastak_v1_customer_catalogue(
  text, uuid, uuid, integer, text, uuid
) is 'Customer-safe canonical retail catalogue. It cannot expose retail merchant identity.';
comment on function public.dastak_v1_import_catalogue(text, jsonb) is
  'Atomic, idempotent canonical catalogue import restricted to catalogue administrators.';
comment on function public.dastak_v1_update_catalogue_sku(
  uuid, text, bigint, jsonb
) is 'Version-checked Dastak-authoritative SKU price and lifecycle update.';
