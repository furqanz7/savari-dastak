-- One image-rich catalogue contract for Customer, Merchant and Admin.
-- Customer and Merchant projections expose only verified, rights-cleared imagery.

create or replace function dastak_v1_api.customer_catalogue(
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
  v_category_types jsonb;
  v_categories jsonb;
  v_subcategories jsonb;
  v_skus jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
  v_version timestamptz;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);

  if v_query is not null and pg_catalog.char_length(v_query) > 80 then
    raise exception using errcode = '22023', message = 'catalogue search is too long';
  end if;
  if (p_after_name is null) <> (p_after_sku_id is null) then
    raise exception using errcode = '22023', message = 'complete catalogue cursor required';
  end if;
  if p_category_id is not null and p_subcategory_id is not null and not exists (
    select 1 from dastak_v1.subcategories subcategory
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

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', category_type.id,
    'name', category_type.name,
    'slug', category_type.slug,
    'imageKey', category_type.image_key,
    'previewImageKeys', coalesce((
      select pg_catalog.jsonb_agg(preview.image_key order by preview.sort_order, preview.name, preview.sku_id)
      from (
        select distinct on (sku.id) image.image_key, category.sort_order, sku.canonical_name as name, sku.id as sku_id
        from dastak_v1.categories category
        join dastak_v1.subcategories subcategory on subcategory.category_id = category.id and subcategory.status = 'ACTIVE'
        join dastak_v1.skus sku on sku.subcategory_id = subcategory.id and sku.status = 'ACTIVE'
        join dastak_v1.sku_images image on image.sku_id = sku.id and image.role = 'PRIMARY'
          and image.status = 'VERIFIED' and image.rights_status = 'CLEARED'
        where category.category_type_id = category_type.id and category.status = 'ACTIVE'
        order by sku.id, image.sort_order, image.id
        limit 4
      ) preview
    ), '[]'::jsonb),
    'sortOrder', category_type.sort_order
  ) order by category_type.sort_order, category_type.name, category_type.id), '[]'::jsonb)
  into v_category_types
  from dastak_v1.category_types category_type
  where category_type.status = 'ACTIVE'
    and exists (
      select 1 from dastak_v1.categories category
      join dastak_v1.subcategories subcategory on subcategory.category_id = category.id and subcategory.status = 'ACTIVE'
      join dastak_v1.skus sku on sku.subcategory_id = subcategory.id and sku.status = 'ACTIVE'
      where category.category_type_id = category_type.id and category.status = 'ACTIVE'
    );

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', category.id,
    'categoryTypeId', category.category_type_id,
    'name', category.name,
    'slug', category.slug,
    'imageKey', category.image_key,
    'previewImageKeys', coalesce((
      select pg_catalog.jsonb_agg(preview.image_key order by preview.sort_order, preview.name, preview.sku_id)
      from (
        select distinct on (sku.id) image.image_key, subcategory.sort_order, sku.canonical_name as name, sku.id as sku_id
        from dastak_v1.subcategories subcategory
        join dastak_v1.skus sku on sku.subcategory_id = subcategory.id and sku.status = 'ACTIVE'
        join dastak_v1.sku_images image on image.sku_id = sku.id and image.role = 'PRIMARY'
          and image.status = 'VERIFIED' and image.rights_status = 'CLEARED'
        where subcategory.category_id = category.id and subcategory.status = 'ACTIVE'
        order by sku.id, image.sort_order, image.id
        limit 4
      ) preview
    ), '[]'::jsonb),
    'sortOrder', category.sort_order
  ) order by category_type.sort_order, category.sort_order, category.name, category.id), '[]'::jsonb)
  into v_categories
  from dastak_v1.categories category
  join dastak_v1.category_types category_type on category_type.id = category.category_type_id and category_type.status = 'ACTIVE'
  where category.status = 'ACTIVE'
    and exists (
      select 1 from dastak_v1.subcategories subcategory
      join dastak_v1.skus sku on sku.subcategory_id = subcategory.id and sku.status = 'ACTIVE'
      where subcategory.category_id = category.id and subcategory.status = 'ACTIVE'
    );

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', subcategory.id,
    'categoryId', subcategory.category_id,
    'name', subcategory.name,
    'slug', subcategory.slug,
    'imageKey', subcategory.image_key,
    'previewImageKeys', coalesce((
      select pg_catalog.jsonb_agg(preview.image_key order by preview.name, preview.sku_id)
      from (
        select distinct on (sku.id) image.image_key, sku.canonical_name as name, sku.id as sku_id
        from dastak_v1.skus sku
        join dastak_v1.sku_images image on image.sku_id = sku.id and image.role = 'PRIMARY'
          and image.status = 'VERIFIED' and image.rights_status = 'CLEARED'
        where sku.subcategory_id = subcategory.id and sku.status = 'ACTIVE'
        order by sku.id, image.sort_order, image.id
        limit 4
      ) preview
    ), '[]'::jsonb),
    'sortOrder', subcategory.sort_order
  ) order by category_type.sort_order, category.sort_order, subcategory.sort_order, subcategory.name, subcategory.id), '[]'::jsonb)
  into v_subcategories
  from dastak_v1.subcategories subcategory
  join dastak_v1.categories category on category.id = subcategory.category_id and category.status = 'ACTIVE'
  join dastak_v1.category_types category_type on category_type.id = category.category_type_id and category_type.status = 'ACTIVE'
  where subcategory.status = 'ACTIVE'
    and exists (select 1 from dastak_v1.skus sku where sku.subcategory_id = subcategory.id and sku.status = 'ACTIVE');

  with matched as materialized (
    select sku.id, sku.subcategory_id, subcategory.category_id,
      category.category_type_id, sku.canonical_name, sku.slug, sku.variant_name,
      sku.pack_size, sku.description, sku.barcode, sku.quantity_value,
      sku.quantity_unit, sku.pack_count, sku.manufacturer_name,
      sku.country_of_origin_code, sku.diet_type, sku.shelf_life_days,
      sku.attribute_data, sku.list_price_paise, sku.selling_price_paise,
      sku.currency_code, sku.logistics_attributes,
      brand.id as brand_id, brand.name as brand_name, brand.slug as brand_slug,
      primary_image.image_key,
      coalesce((select pg_catalog.jsonb_agg(gallery.image_key order by gallery.sort_order, gallery.id)
        from dastak_v1.sku_images gallery
        where gallery.sku_id = sku.id and gallery.role = 'GALLERY'
          and gallery.status = 'VERIFIED' and gallery.rights_status = 'CLEARED'), '[]'::jsonb) as gallery_image_keys
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id and subcategory.status = 'ACTIVE'
    join dastak_v1.categories category on category.id = subcategory.category_id and category.status = 'ACTIVE'
    join dastak_v1.category_types category_type on category_type.id = category.category_type_id and category_type.status = 'ACTIVE'
    left join dastak_v1.brands brand on brand.id = sku.brand_id
    join lateral (
      select image.image_key from dastak_v1.sku_images image
      where image.sku_id = sku.id and image.role = 'PRIMARY'
        and image.status = 'VERIFIED' and image.rights_status = 'CLEARED'
      order by image.sort_order, image.id limit 1
    ) primary_image on true
    where sku.status = 'ACTIVE' and (brand.id is null or brand.status = 'ACTIVE')
      and (p_category_id is null or subcategory.category_id = p_category_id)
      and (p_subcategory_id is null or sku.subcategory_id = p_subcategory_id)
      and (
        v_search is null or sku.search_document @@ v_search
        or exists (select 1 from dastak_v1.sku_search_aliases alias where alias.sku_id = sku.id and alias.search_document @@ v_search)
        or exists (select 1 from dastak_v1.sku_identifiers identifier where identifier.sku_id = sku.id
          and identifier.normalized_value like pg_catalog.upper(v_query) || '%')
        or pg_catalog.to_tsvector('pg_catalog.simple'::regconfig,
          coalesce(brand.name, '') || ' ' || subcategory.name || ' ' || category.name || ' ' || category_type.name
        ) @@ v_search
      )
      and (p_after_name is null or (pg_catalog.lower(sku.canonical_name), sku.id) > (pg_catalog.lower(p_after_name), p_after_sku_id))
    order by pg_catalog.lower(sku.canonical_name), sku.id
    limit v_limit + 1
  ), selected as (
    select * from matched order by pg_catalog.lower(canonical_name), id limit v_limit
  )
  select coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'id', selected.id, 'categoryTypeId', selected.category_type_id,
      'categoryId', selected.category_id, 'subcategoryId', selected.subcategory_id,
      'brand', case when selected.brand_id is null then null else pg_catalog.jsonb_build_object(
        'id', selected.brand_id, 'name', selected.brand_name, 'slug', selected.brand_slug) end,
      'name', selected.canonical_name, 'slug', selected.slug, 'variant', selected.variant_name,
      'packSize', selected.pack_size, 'description', selected.description,
      'imageKey', selected.image_key, 'galleryImageKeys', selected.gallery_image_keys,
      'barcode', selected.barcode, 'quantityValue', selected.quantity_value,
      'quantityUnit', selected.quantity_unit, 'packCount', selected.pack_count,
      'manufacturerName', selected.manufacturer_name,
      'countryOfOriginCode', selected.country_of_origin_code,
      'dietType', selected.diet_type, 'shelfLifeDays', selected.shelf_life_days,
      'attributes', selected.attribute_data,
      'listPricePaise', selected.list_price_paise, 'sellingPricePaise', selected.selling_price_paise,
      'currencyCode', selected.currency_code, 'logisticsAttributes', selected.logistics_attributes
    )) order by pg_catalog.lower(selected.canonical_name), selected.id) from selected), '[]'::jsonb),
    (select pg_catalog.count(*) > v_limit from matched),
    (select pg_catalog.jsonb_build_object('name', selected.canonical_name, 'skuId', selected.id)
      from selected order by pg_catalog.lower(selected.canonical_name) desc, selected.id desc limit 1)
  into v_skus, v_has_more, v_next_cursor;
  if not v_has_more then v_next_cursor := null; end if;

  select pg_catalog.max(version_at) into v_version from (
    select pg_catalog.max(updated_at) version_at from dastak_v1.category_types union all
    select pg_catalog.max(updated_at) from dastak_v1.categories union all
    select pg_catalog.max(updated_at) from dastak_v1.subcategories union all
    select pg_catalog.max(updated_at) from dastak_v1.brands union all
    select pg_catalog.max(updated_at) from dastak_v1.skus union all
    select pg_catalog.max(created_at) from dastak_v1.sku_images
  ) versions;
  return pg_catalog.jsonb_build_object('catalogueVersion', v_version,
    'categoryTypes', v_category_types, 'categories', v_categories,
    'subcategories', v_subcategories, 'skus', v_skus, 'nextCursor', v_next_cursor);
end;
$$;

create or replace function dastak_v1_api.merchant_canonical_catalogue_snapshot(
  p_actor_id uuid, p_branch_id uuid default null, p_limit integer default 1000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_state dastak_v1.branch_operational_states%rowtype;
  v_limit integer := least(greatest(coalesce(p_limit, 1000), 1), 1000);
  v_capacity_held integer;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_branch_id is null then
    select branch.* into v_branch from dastak_v1.merchant_branches branch
    where branch.status not in ('CLOSED', 'SUSPENDED')
      and dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id, branch.organization_id,
        'merchant.catalogue.selection.manage', branch.id)
    order by branch.created_at, branch.id limit 1;
  else
    select branch.* into v_branch from dastak_v1.merchant_branches branch where branch.id = p_branch_id;
  end if;
  if not found then raise exception using errcode = 'P0002', message = 'merchant branch not found'; end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id, v_branch.organization_id,
    'merchant.catalogue.selection.manage', v_branch.id) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  select organization.* into strict v_organization from dastak_v1.merchant_organizations organization
    where organization.id = v_branch.organization_id;
  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception using errcode = '22023', message = 'canonical SKU selection is retail-only';
  end if;
  select state.* into v_state from dastak_v1.branch_operational_states state where state.branch_id = v_branch.id;
  select pg_catalog.count(*) into v_capacity_held from dastak_v1.retail_capacity_slots slot
    where slot.branch_id = v_branch.id and slot.status = 'HELD';

  return pg_catalog.jsonb_build_object(
    'branch', pg_catalog.jsonb_build_object(
      'branchId', v_branch.id, 'branchName', v_branch.display_name,
      'branchStatus', v_branch.status, 'branchVersion', v_branch.version,
      'organizationId', v_organization.id, 'organizationName', v_organization.display_name,
      'merchantType', v_organization.merchant_type,
      'operationalState', pg_catalog.jsonb_build_object('isOpen', coalesce(v_state.is_open, false),
        'acceptingOrders', coalesce(v_state.accepting_orders, false), 'version', coalesce(v_state.version, 0),
        'updatedAt', v_state.updated_at),
      'capacity', pg_catalog.jsonb_build_object('limit', v_branch.capacity_limit,
        'held', v_capacity_held, 'available', greatest(v_branch.capacity_limit - v_capacity_held, 0))
    ),
    'categoryTypes', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'categoryTypeId', type.id, 'name', type.name, 'slug', type.slug,
      'imageKey', type.image_key, 'sortOrder', type.sort_order
    ) order by type.sort_order, type.name, type.id) from dastak_v1.category_types type where type.status = 'ACTIVE'), '[]'::jsonb),
    'categories', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'categoryId', category.id, 'categoryTypeId', category.category_type_id,
      'name', category.name, 'slug', category.slug, 'imageKey', category.image_key,
      'sortOrder', category.sort_order
    ) order by type.sort_order, category.sort_order, category.name, category.id)
      from dastak_v1.categories category join dastak_v1.category_types type on type.id = category.category_type_id
      where category.status = 'ACTIVE' and type.status = 'ACTIVE'), '[]'::jsonb),
    'subcategories', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'subcategoryId', subcategory.id, 'categoryId', subcategory.category_id,
      'name', subcategory.name, 'slug', subcategory.slug, 'imageKey', subcategory.image_key,
      'sortOrder', subcategory.sort_order
    ) order by category.sort_order, subcategory.sort_order, subcategory.name, subcategory.id)
      from dastak_v1.subcategories subcategory join dastak_v1.categories category on category.id = subcategory.category_id
      where subcategory.status = 'ACTIVE' and category.status = 'ACTIVE'), '[]'::jsonb),
    'skus', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'skuId', sku.id, 'categoryTypeId', category.category_type_id,
      'categoryId', subcategory.category_id, 'subcategoryId', sku.subcategory_id,
      'brandName', brand.name, 'name', sku.canonical_name, 'variant', sku.variant_name,
      'packSize', sku.pack_size, 'description', sku.description,
      'imageKey', primary_image.image_key,
      'galleryImageKeys', coalesce((select pg_catalog.jsonb_agg(gallery.image_key order by gallery.sort_order, gallery.id)
        from dastak_v1.sku_images gallery where gallery.sku_id = sku.id and gallery.role = 'GALLERY'
          and gallery.status = 'VERIFIED' and gallery.rights_status = 'CLEARED'), '[]'::jsonb),
      'quantityValue', sku.quantity_value, 'quantityUnit', sku.quantity_unit,
      'packCount', sku.pack_count, 'dietType', sku.diet_type,
      'searchTerms', coalesce((select pg_catalog.jsonb_agg(alias.alias order by alias.alias)
        from dastak_v1.sku_search_aliases alias where alias.sku_id = sku.id), '[]'::jsonb),
      'listPricePaise', sku.list_price_paise, 'sellingPricePaise', sku.selling_price_paise,
      'currencyCode', sku.currency_code, 'catalogueStatus', sku.status,
      'selected', coalesce(selection.state = 'SELECTED', false), 'selectionState', selection.state,
      'selectionVersion', coalesce(selection.version, 0), 'selectionUpdatedAt', selection.updated_at
    ) order by type.sort_order, category.sort_order, subcategory.sort_order,
      pg_catalog.lower(sku.canonical_name), sku.id)
      from (select source.* from dastak_v1.skus source where source.status = 'ACTIVE'
        or exists (select 1 from dastak_v1.merchant_sku_selections existing
          where existing.branch_id = v_branch.id and existing.sku_id = source.id)
        order by pg_catalog.lower(source.canonical_name), source.id limit v_limit) sku
      join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
      join dastak_v1.categories category on category.id = subcategory.category_id
      left join dastak_v1.category_types type on type.id = category.category_type_id
      left join dastak_v1.brands brand on brand.id = sku.brand_id
      left join dastak_v1.merchant_sku_selections selection on selection.branch_id = v_branch.id and selection.sku_id = sku.id
      left join lateral (select image.image_key from dastak_v1.sku_images image
        where image.sku_id = sku.id and image.role = 'PRIMARY' and image.status = 'VERIFIED'
          and image.rights_status = 'CLEARED' order by image.sort_order, image.id limit 1) primary_image on true
    ), '[]'::jsonb),
    'truncated', (select pg_catalog.count(*) > v_limit from dastak_v1.skus sku where sku.status = 'ACTIVE'
      or exists (select 1 from dastak_v1.merchant_sku_selections existing
        where existing.branch_id = v_branch.id and existing.sku_id = sku.id))
  );
end;
$$;

create or replace function dastak_v1_api.update_catalogue_sku(
  p_actor_id uuid, p_sku_id uuid, p_idempotency_key text,
  p_expected_version bigint, p_patch jsonb
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
  v_response jsonb;
  v_allowed constant text[] := array[
    'name','variant','packSize','description','subcategoryId','brandId','barcode',
    'quantityValue','quantityUnit','packCount','manufacturerName','countryOfOriginCode',
    'hsnCode','dietType','shelfLifeDays','attributes','listPricePaise',
    'sellingPricePaise','taxRateBps','logisticsAttributes','qaStatus','status'
  ];
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.catalogue.manage');
  if p_idempotency_key is null or pg_catalog.char_length(p_idempotency_key) not between 1 and 200
    or p_patch is null or pg_catalog.jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb
    or exists (select 1 from pg_catalog.jsonb_object_keys(p_patch) key where not (key = any(v_allowed))) then
    raise exception using errcode = '22023', message = 'SKU patch is invalid';
  end if;
  if p_patch ? 'name' and pg_catalog.char_length(pg_catalog.btrim(p_patch->>'name')) not between 1 and 160 then
    raise exception using errcode = '22023', message = 'SKU name is invalid';
  end if;
  if p_patch ? 'packSize' and pg_catalog.char_length(pg_catalog.btrim(p_patch->>'packSize')) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'pack size is invalid';
  end if;
  if p_patch ? 'attributes' and pg_catalog.jsonb_typeof(p_patch->'attributes') <> 'object' then
    raise exception using errcode = '22023', message = 'attributes must be an object';
  end if;
  if p_patch ? 'logisticsAttributes' and pg_catalog.jsonb_typeof(p_patch->'logisticsAttributes') <> 'object' then
    raise exception using errcode = '22023', message = 'logistics attributes must be an object';
  end if;
  if exists (select 1 from (values ('listPricePaise'),('sellingPricePaise'),('taxRateBps'),('packCount'),('shelfLifeDays')) field(name)
    where p_patch ? field.name and p_patch->field.name <> 'null'::jsonb
      and (pg_catalog.jsonb_typeof(p_patch->field.name) <> 'number' or p_patch->>field.name !~ '^[0-9]+$')) then
    raise exception using errcode = '22023', message = 'numeric SKU field is invalid';
  end if;
  if p_patch ? 'quantityValue' and p_patch->'quantityValue' <> 'null'::jsonb
    and (pg_catalog.jsonb_typeof(p_patch->'quantityValue') <> 'number' or (p_patch->>'quantityValue')::numeric <= 0) then
    raise exception using errcode = '22023', message = 'quantity is invalid';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'skuId', p_sku_id, 'expectedVersion', p_expected_version, 'patch', p_patch));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dastak-v1-catalogue-write', 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0));
  select * into v_existing from dastak_v1.idempotency_records
    where actor_id = p_actor_id and command_name = v_command and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key conflict';
  end if;
  select * into v_sku from dastak_v1.skus where id = p_sku_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'SKU not found'; end if;
  if v_sku.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale SKU version';
  end if;

  update dastak_v1.skus set
    canonical_name = case when p_patch ? 'name' then pg_catalog.btrim(p_patch->>'name') else canonical_name end,
    variant_name = case when p_patch ? 'variant' then nullif(pg_catalog.btrim(p_patch->>'variant'),'') else variant_name end,
    pack_size = case when p_patch ? 'packSize' then pg_catalog.btrim(p_patch->>'packSize') else pack_size end,
    description = case when p_patch ? 'description' then nullif(pg_catalog.btrim(p_patch->>'description'),'') else description end,
    subcategory_id = case when p_patch ? 'subcategoryId' then (p_patch->>'subcategoryId')::uuid else subcategory_id end,
    brand_id = case when p_patch ? 'brandId' then nullif(p_patch->>'brandId','')::uuid else brand_id end,
    barcode = case when p_patch ? 'barcode' then nullif(pg_catalog.btrim(p_patch->>'barcode'),'') else barcode end,
    quantity_value = case when p_patch ? 'quantityValue' then nullif(p_patch->>'quantityValue','')::numeric else quantity_value end,
    quantity_unit = case when p_patch ? 'quantityUnit' then nullif(pg_catalog.btrim(p_patch->>'quantityUnit'),'') else quantity_unit end,
    pack_count = case when p_patch ? 'packCount' then nullif(p_patch->>'packCount','')::integer else pack_count end,
    manufacturer_name = case when p_patch ? 'manufacturerName' then nullif(pg_catalog.btrim(p_patch->>'manufacturerName'),'') else manufacturer_name end,
    country_of_origin_code = case when p_patch ? 'countryOfOriginCode' then nullif(pg_catalog.upper(pg_catalog.btrim(p_patch->>'countryOfOriginCode')),'') else country_of_origin_code end,
    hsn_code = case when p_patch ? 'hsnCode' then nullif(pg_catalog.btrim(p_patch->>'hsnCode'),'') else hsn_code end,
    diet_type = case when p_patch ? 'dietType' then pg_catalog.upper(p_patch->>'dietType') else diet_type end,
    shelf_life_days = case when p_patch ? 'shelfLifeDays' then nullif(p_patch->>'shelfLifeDays','')::integer else shelf_life_days end,
    attribute_data = case when p_patch ? 'attributes' then p_patch->'attributes' else attribute_data end,
    list_price_paise = case when p_patch ? 'listPricePaise' then (p_patch->>'listPricePaise')::bigint else list_price_paise end,
    selling_price_paise = case when p_patch ? 'sellingPricePaise' then (p_patch->>'sellingPricePaise')::bigint else selling_price_paise end,
    tax_rate_bps = case when p_patch ? 'taxRateBps' then (p_patch->>'taxRateBps')::integer else tax_rate_bps end,
    logistics_attributes = case when p_patch ? 'logisticsAttributes' then p_patch->'logisticsAttributes' else logistics_attributes end,
    qa_status = case when p_patch ? 'qaStatus' then pg_catalog.upper(p_patch->>'qaStatus') else qa_status end,
    qa_verified_at = case when p_patch ? 'qaStatus' and pg_catalog.upper(p_patch->>'qaStatus') = 'VERIFIED'
      then pg_catalog.now() when p_patch ? 'qaStatus' then null else qa_verified_at end,
    qa_verified_by = case when p_patch ? 'qaStatus' and pg_catalog.upper(p_patch->>'qaStatus') = 'VERIFIED'
      then p_actor_id when p_patch ? 'qaStatus' then null else qa_verified_by end,
    status = case when p_patch ? 'status' then pg_catalog.upper(p_patch->>'status')::dastak_v1.catalogue_status else status end,
    updated_at = pg_catalog.now(), version = version + 1
  where id = v_sku.id returning * into v_sku;
  if v_sku.selling_price_paise > v_sku.list_price_paise or v_sku.list_price_paise > 100000000 then
    raise exception using errcode = '22023', message = 'SKU price exceeds MRP';
  end if;

  v_response := pg_catalog.jsonb_build_object('id', v_sku.id, 'name', v_sku.canonical_name,
    'slug', v_sku.slug, 'listPricePaise', v_sku.list_price_paise,
    'sellingPricePaise', v_sku.selling_price_paise, 'currencyCode', v_sku.currency_code,
    'status', v_sku.status, 'qaStatus', v_sku.qa_status,
    'version', v_sku.version, 'updatedAt', v_sku.updated_at);
  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
    values (p_actor_id, 'CATALOGUE_SKU_UPDATED', 'catalogue_sku', v_sku.id,
      pg_catalog.jsonb_build_object('idempotencyKey', p_idempotency_key,
        'fromVersion', p_expected_version, 'toVersion', v_sku.version,
        'changedFields', (select pg_catalog.jsonb_agg(key order by key) from pg_catalog.jsonb_object_keys(p_patch) key)));
  insert into dastak_v1.domain_events_outbox(event_key, aggregate_type, aggregate_id,
    aggregate_version, event_type, actor_id, payload)
    values (v_sku.id::text || ':CATALOGUE_SKU_UPDATED:' || v_sku.version::text,
      'CATALOGUE_SKU', v_sku.id, v_sku.version, 'CATALOGUE_SKU_UPDATED', p_actor_id, v_response);
  insert into dastak_v1.idempotency_records(actor_id, command_name, idempotency_key,
    request_hash, response_body, response_status, resource_id)
    values (p_actor_id, v_command, p_idempotency_key, v_request_hash, v_response, 200, v_sku.id);
  return v_response;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception using errcode = '22023', message = 'SKU patch contains invalid values';
end;
$$;

revoke execute on function dastak_v1_api.customer_catalogue(uuid,text,uuid,uuid,integer,text,uuid) from public, anon;
revoke execute on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer) from public, anon;
revoke execute on function dastak_v1_api.update_catalogue_sku(uuid,uuid,text,bigint,jsonb) from public, anon;
grant execute on function dastak_v1_api.customer_catalogue(uuid,text,uuid,uuid,integer,text,uuid) to authenticated;
grant execute on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer) to authenticated;
grant execute on function dastak_v1_api.update_catalogue_sku(uuid,uuid,text,bigint,jsonb) to authenticated;

comment on function public.dastak_v1_customer_catalogue(text,uuid,uuid,integer,text,uuid) is
  'Customer-safe image-rich catalogue with department hierarchy and alias-aware search.';
comment on function public.dastak_v1_update_catalogue_sku(uuid,text,bigint,jsonb) is
  'Version-checked, audited Admin mutation for canonical SKU identity, quantity, classification, QA, pricing and lifecycle.';
