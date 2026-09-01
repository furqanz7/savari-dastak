-- Enrich the existing permission-checked Admin catalogue page with the
-- human-readable taxonomy and customer-facing product fields needed by Web
-- and native Admin presentation. No new table or direct-table access is
-- exposed; the existing public wrapper and permission boundary are retained.

create or replace function dastak_v1_api.catalogue_taxonomy_snapshot(
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.catalogue.read'
  );
  return pg_catalog.jsonb_build_object(
    'categoryTypes', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', category_type.id,
        'name', category_type.name,
        'slug', category_type.slug,
        'imageKey', category_type.image_key,
        'status', category_type.status,
        'sortOrder', category_type.sort_order,
        'version', category_type.version,
        'updatedAt', category_type.updated_at
      ) order by category_type.sort_order, category_type.name, category_type.id)
      from dastak_v1.category_types category_type
    ), '[]'::jsonb),
    'categories', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', category.id,
        'categoryTypeId', category.category_type_id,
        'name', category.name,
        'slug', category.slug,
        'imageKey', category.image_key,
        'status', category.status,
        'sortOrder', category.sort_order,
        'version', category.version,
        'updatedAt', category.updated_at
      ) order by category_type.sort_order nulls last,
        category.sort_order, category.name, category.id)
      from dastak_v1.categories category
      left join dastak_v1.category_types category_type
        on category_type.id = category.category_type_id
    ), '[]'::jsonb),
    'subcategories', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', subcategory.id,
        'categoryId', subcategory.category_id,
        'name', subcategory.name,
        'slug', subcategory.slug,
        'imageKey', subcategory.image_key,
        'status', subcategory.status,
        'sortOrder', subcategory.sort_order,
        'version', subcategory.version,
        'updatedAt', subcategory.updated_at
      ) order by category.sort_order, subcategory.sort_order,
        subcategory.name, subcategory.id)
      from dastak_v1.subcategories subcategory
      join dastak_v1.categories category
        on category.id = subcategory.category_id
    ), '[]'::jsonb),
    'brands', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', brand.id,
        'name', brand.name,
        'slug', brand.slug,
        'imageKey', brand.image_key,
        'status', brand.status,
        'version', brand.version,
        'updatedAt', brand.updated_at
      ) order by brand.name, brand.id)
      from dastak_v1.brands brand
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function dastak_v1_api.admin_catalogue_page(
  p_actor_id uuid,
  p_query text default null,
  p_category_type_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_status text default null,
  p_qa_status text default null,
  p_limit integer default 100,
  p_after_name text default null,
  p_after_sku_id uuid default null
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
  v_rows jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.catalogue.read'
  );
  if (p_after_name is null) <> (p_after_sku_id is null) then
    raise exception using errcode = '22023',
      message = 'complete catalogue cursor required';
  end if;
  if p_status is not null
    and pg_catalog.upper(p_status) not in ('DRAFT', 'ACTIVE', 'INACTIVE') then
    raise exception using errcode = '22023',
      message = 'invalid catalogue status';
  end if;
  if p_qa_status is not null
    and pg_catalog.upper(p_qa_status) not in (
      'PENDING', 'NEEDS_REVIEW', 'VERIFIED', 'REJECTED'
    ) then
    raise exception using errcode = '22023', message = 'invalid QA status';
  end if;
  if v_query is not null then
    if pg_catalog.char_length(v_query) > 80 then
      raise exception using errcode = '22023',
        message = 'catalogue search is too long';
    end if;
    v_search := dastak_v1.catalogue_prefix_query(v_query);
  end if;

  with matched as materialized (
    select
      sku.*,
      subcategory.category_id,
      category.category_type_id,
      category_type.name as category_type_name,
      category.name as category_name,
      subcategory.name as subcategory_name,
      brand.name as brand_name,
      readiness.activation_ready,
      coalesce(
        readiness.blockers,
        array['CATEGORY_TYPE_ACTIVE_REQUIRED']::text[]
      ) as activation_blockers,
      coalesce((
        select pg_catalog.count(*)
        from dastak_v1.merchant_sku_selections selection
        where selection.sku_id = sku.id and selection.state = 'SELECTED'
      ), 0) as selection_count
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory
      on subcategory.id = sku.subcategory_id
    join dastak_v1.categories category
      on category.id = subcategory.category_id
    left join dastak_v1.category_types category_type
      on category_type.id = category.category_type_id
    left join dastak_v1.brands brand on brand.id = sku.brand_id
    left join dastak_v1.catalogue_activation_readiness readiness
      on readiness.sku_id = sku.id
    where (p_category_type_id is null
        or category.category_type_id = p_category_type_id)
      and (p_category_id is null or subcategory.category_id = p_category_id)
      and (p_subcategory_id is null or sku.subcategory_id = p_subcategory_id)
      and (p_status is null or sku.status::text = pg_catalog.upper(p_status))
      and (p_qa_status is null or sku.qa_status = pg_catalog.upper(p_qa_status))
      and (
        v_search is null
        or sku.search_document @@ v_search
        or exists (
          select 1 from dastak_v1.sku_search_aliases alias
          where alias.sku_id = sku.id and alias.search_document @@ v_search
        )
        or pg_catalog.to_tsvector(
          'pg_catalog.simple'::regconfig,
          coalesce(brand.name, '') || ' ' || subcategory.name || ' '
            || category.name || ' ' || coalesce(category_type.name, '')
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
    select * from matched
    order by pg_catalog.lower(canonical_name), id
    limit v_limit
  )
  select
    coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', row.id,
        'categoryTypeId', row.category_type_id,
        'categoryTypeName', row.category_type_name,
        'categoryId', row.category_id,
        'categoryName', row.category_name,
        'subcategoryId', row.subcategory_id,
        'subcategoryName', row.subcategory_name,
        'brandId', row.brand_id,
        'brandName', row.brand_name,
        'name', row.canonical_name,
        'slug', row.slug,
        'variant', row.variant_name,
        'packSize', row.pack_size,
        'description', row.description,
        'imageKey', row.image_key,
        'quantityValue', row.quantity_value,
        'quantityUnit', row.quantity_unit,
        'packCount', row.pack_count,
        'manufacturerName', row.manufacturer_name,
        'countryOfOriginCode', row.country_of_origin_code,
        'hsnCode', row.hsn_code,
        'dietType', row.diet_type,
        'shelfLifeDays', row.shelf_life_days,
        'attributes', row.attribute_data,
        'barcode', row.barcode,
        'listPricePaise', row.list_price_paise,
        'sellingPricePaise', row.selling_price_paise,
        'currencyCode', row.currency_code,
        'taxRateBps', row.tax_rate_bps,
        'logisticsAttributes', row.logistics_attributes,
        'status', row.status,
        'qaStatus', row.qa_status,
        'activationReady', coalesce(row.activation_ready, false),
        'activationBlockers', pg_catalog.to_jsonb(row.activation_blockers),
        'selectionCount', row.selection_count,
        'version', row.version,
        'updatedAt', row.updated_at,
        'primaryImage', (
          select pg_catalog.jsonb_build_object(
            'id', image.id,
            'imageKey', image.image_key,
            'status', image.status,
            'rightsStatus', image.rights_status,
            'sourceType', image.source_type
          )
          from dastak_v1.sku_images image
          where image.sku_id = row.id and image.role = 'PRIMARY'
          limit 1
        ),
        'imageCount', (
          select pg_catalog.count(*) from dastak_v1.sku_images image
          where image.sku_id = row.id and image.status <> 'REJECTED'
        ),
        'aliasCount', (
          select pg_catalog.count(*) from dastak_v1.sku_search_aliases alias
          where alias.sku_id = row.id
        ),
        'identifierCount', (
          select pg_catalog.count(*) from dastak_v1.sku_identifiers identifier
          where identifier.sku_id = row.id
        )
      ) order by pg_catalog.lower(row.canonical_name), row.id)
      from selected row
    ), '[]'::jsonb),
    (select pg_catalog.count(*) > v_limit from matched),
    case when (select pg_catalog.count(*) > v_limit from matched) then (
      select pg_catalog.jsonb_build_object(
        'name', row.canonical_name,
        'skuId', row.id
      )
      from selected row
      order by pg_catalog.lower(row.canonical_name) desc, row.id desc
      limit 1
    ) else null end
  into v_rows, v_has_more, v_next_cursor;

  return pg_catalog.jsonb_build_object(
    'skus', v_rows, 'hasMore', v_has_more, 'nextCursor', v_next_cursor
  );
end;
$$;

comment on function dastak_v1_api.admin_catalogue_page(
  uuid,text,uuid,uuid,uuid,text,text,integer,text,uuid
) is
  'Permission-checked Admin catalogue page with presentation-ready taxonomy, product detail and activation truth.';
