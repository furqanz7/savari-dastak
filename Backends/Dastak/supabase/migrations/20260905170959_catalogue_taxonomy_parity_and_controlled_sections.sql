-- Keep the canonical hierarchy consistent across Admin, Merchant and Customer.
-- Draft taxonomy is safe to browse, but only ACTIVE, verified, rights-cleared
-- SKUs remain purchasable/selectable. Pharmacy and Paan are deliberately seeded
-- without products; those products must continue through the controlled flow.

with actor as (
  select grant_row.account_id
  from dastak_v1.platform_permission_grants grant_row
  join dastak_v1.permission_bundles bundle on bundle.id = grant_row.bundle_id
  where bundle.bundle_key = 'platform_super_admin'
    and grant_row.revoked_at is null
  order by grant_row.granted_at, grant_row.account_id
  limit 1
), seed(name, slug, sort_order) as (
  values
    ('Pharmacy', 'pharmacy', 260),
    ('Paan Corner', 'paan-corner', 270)
)
insert into dastak_v1.category_types(name, slug, status, sort_order, created_by)
select seed.name, seed.slug, 'DRAFT', seed.sort_order, actor.account_id
from seed cross join actor
on conflict (slug) do nothing;

with actor as (
  select grant_row.account_id
  from dastak_v1.platform_permission_grants grant_row
  join dastak_v1.permission_bundles bundle on bundle.id = grant_row.bundle_id
  where bundle.bundle_key = 'platform_super_admin'
    and grant_row.revoked_at is null
  order by grant_row.granted_at, grant_row.account_id
  limit 1
), seed(type_slug, name, slug, sort_order) as (
  values
    ('pharmacy', 'Medicines', 'medicines', 10),
    ('pharmacy', 'Vitamins & Supplements', 'vitamins-supplements', 20),
    ('pharmacy', 'First Aid & Medical Supplies', 'first-aid-medical-supplies', 30),
    ('paan-corner', 'Paan & Mouth Fresheners', 'paan-mouth-fresheners', 10)
)
insert into dastak_v1.categories(category_type_id, name, slug, status, sort_order, created_by)
select category_type.id, seed.name, seed.slug, 'DRAFT', seed.sort_order, actor.account_id
from seed
join dastak_v1.category_types category_type on category_type.slug = seed.type_slug
cross join actor
on conflict (slug) do nothing;

with actor as (
  select grant_row.account_id
  from dastak_v1.platform_permission_grants grant_row
  join dastak_v1.permission_bundles bundle on bundle.id = grant_row.bundle_id
  where bundle.bundle_key = 'platform_super_admin'
    and grant_row.revoked_at is null
  order by grant_row.granted_at, grant_row.account_id
  limit 1
), seed(category_slug, name, slug, sort_order) as (
  values
    ('medicines', 'OTC Medicines', 'otc-medicines', 10),
    ('medicines', 'Prescription Medicines', 'prescription-medicines', 20),
    ('medicines', 'Ayurveda & Herbal Medicines', 'ayurveda-herbal-medicines', 30),
    ('medicines', 'Homeopathy', 'homeopathy', 40),
    ('vitamins-supplements', 'Vitamins & Minerals', 'vitamins-minerals', 10),
    ('vitamins-supplements', 'Protein & Nutrition', 'protein-nutrition', 20),
    ('vitamins-supplements', 'Immunity & Wellness', 'immunity-wellness', 30),
    ('first-aid-medical-supplies', 'First Aid', 'pharmacy-first-aid', 10),
    ('first-aid-medical-supplies', 'Medical Devices', 'medical-devices', 20),
    ('first-aid-medical-supplies', 'Health Monitors', 'health-monitors', 30),
    ('paan-mouth-fresheners', 'Paan Ingredients', 'paan-ingredients', 10),
    ('paan-mouth-fresheners', 'Mukhwas & Mouth Fresheners', 'paan-mukhwas-mouth-fresheners', 20),
    ('paan-mouth-fresheners', 'Paan Accessories', 'paan-accessories', 30),
    ('paan-mouth-fresheners', 'Tobacco & Nicotine Products', 'tobacco-nicotine-products', 40)
)
insert into dastak_v1.subcategories(category_id, name, slug, status, sort_order, created_by)
select category.id, seed.name, seed.slug, 'DRAFT', seed.sort_order, actor.account_id
from seed
join dastak_v1.categories category on category.slug = seed.category_slug
cross join actor
on conflict (category_id, slug) do nothing;

create or replace function dastak_v1_api.browse_catalogue_taxonomy(
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);

  return (
    with valid_images as materialized (
      select
        category_type.id as category_type_id,
        category.id as category_id,
        subcategory.id as subcategory_id,
        category.sort_order as category_sort_order,
        subcategory.sort_order as subcategory_sort_order,
        sku.canonical_name as sku_name,
        sku.id as sku_id,
        image.image_key
      from dastak_v1.skus sku
      join dastak_v1.subcategories subcategory
        on subcategory.id = sku.subcategory_id and subcategory.status = 'ACTIVE'
      join dastak_v1.categories category
        on category.id = subcategory.category_id and category.status = 'ACTIVE'
      join dastak_v1.category_types category_type
        on category_type.id = category.category_type_id and category_type.status = 'ACTIVE'
      left join dastak_v1.brands brand on brand.id = sku.brand_id
      join dastak_v1.sku_images image
        on image.sku_id = sku.id
       and image.role = 'PRIMARY'
       and image.status = 'VERIFIED'
       and image.rights_status = 'CLEARED'
      where sku.status = 'ACTIVE'
        and (brand.id is null or brand.status = 'ACTIVE')
    ), ranked_images as materialized (
      select valid_images.*,
        pg_catalog.row_number() over (
          partition by category_type_id
          order by category_sort_order, subcategory_sort_order, pg_catalog.lower(sku_name), sku_id
        ) as category_type_rank,
        pg_catalog.row_number() over (
          partition by category_id
          order by subcategory_sort_order, pg_catalog.lower(sku_name), sku_id
        ) as category_rank,
        pg_catalog.row_number() over (
          partition by subcategory_id
          order by pg_catalog.lower(sku_name), sku_id
        ) as subcategory_rank
      from valid_images
    ), category_type_previews as (
      select category_type_id,
        pg_catalog.jsonb_agg(
          image_key order by category_sort_order, subcategory_sort_order, pg_catalog.lower(sku_name), sku_id
        ) filter (where category_type_rank <= 4) as image_keys
      from ranked_images
      group by category_type_id
    ), category_previews as (
      select category_id,
        pg_catalog.jsonb_agg(
          image_key order by subcategory_sort_order, pg_catalog.lower(sku_name), sku_id
        ) filter (where category_rank <= 4) as image_keys
      from ranked_images
      group by category_id
    ), subcategory_previews as (
      select subcategory_id,
        pg_catalog.jsonb_agg(image_key order by pg_catalog.lower(sku_name), sku_id)
          filter (where subcategory_rank <= 4) as image_keys
      from ranked_images
      group by subcategory_id
    )
    select pg_catalog.jsonb_build_object(
      'categoryTypes', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', category_type.id,
          'categoryTypeId', category_type.id,
          'name', category_type.name,
          'slug', category_type.slug,
          'imageKey', category_type.image_key,
          'previewImageKeys', coalesce(preview.image_keys, '[]'::jsonb),
          'status', category_type.status,
          'requiresControlledFlow', category_type.slug in ('pharmacy', 'paan-corner'),
          'sortOrder', category_type.sort_order
        ) order by category_type.sort_order, category_type.name, category_type.id)
        from dastak_v1.category_types category_type
        left join category_type_previews preview on preview.category_type_id = category_type.id
        where category_type.status <> 'INACTIVE'
      ), '[]'::jsonb),
      'categories', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', category.id,
          'categoryId', category.id,
          'categoryTypeId', category.category_type_id,
          'name', category.name,
          'slug', category.slug,
          'imageKey', category.image_key,
          'previewImageKeys', coalesce(preview.image_keys, '[]'::jsonb),
          'status', category.status,
          'requiresControlledFlow', category_type.slug in ('pharmacy', 'paan-corner'),
          'sortOrder', category.sort_order
        ) order by category_type.sort_order, category.sort_order, category.name, category.id)
        from dastak_v1.categories category
        join dastak_v1.category_types category_type on category_type.id = category.category_type_id
        left join category_previews preview on preview.category_id = category.id
        where category.status <> 'INACTIVE' and category_type.status <> 'INACTIVE'
      ), '[]'::jsonb),
      'subcategories', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', subcategory.id,
          'subcategoryId', subcategory.id,
          'categoryId', subcategory.category_id,
          'name', subcategory.name,
          'slug', subcategory.slug,
          'imageKey', subcategory.image_key,
          'previewImageKeys', coalesce(preview.image_keys, '[]'::jsonb),
          'status', subcategory.status,
          'requiresControlledFlow', category_type.slug in ('pharmacy', 'paan-corner'),
          'sortOrder', subcategory.sort_order
        ) order by category_type.sort_order, category.sort_order,
          subcategory.sort_order, subcategory.name, subcategory.id)
        from dastak_v1.subcategories subcategory
        join dastak_v1.categories category on category.id = subcategory.category_id
        join dastak_v1.category_types category_type on category_type.id = category.category_type_id
        left join subcategory_previews preview on preview.subcategory_id = subcategory.id
        where subcategory.status <> 'INACTIVE'
          and category.status <> 'INACTIVE'
          and category_type.status <> 'INACTIVE'
      ), '[]'::jsonb)
    )
  );
end;
$$;

create or replace function public.dastak_v1_customer_catalogue(
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
    auth.uid(), p_query, p_category_id, p_subcategory_id,
    p_limit, p_after_name, p_after_sku_id
  ) || dastak_v1_api.browse_catalogue_taxonomy(auth.uid());
$$;

create or replace function dastak_v1_api.merchant_canonical_catalogue_snapshot(
  p_actor_id uuid,
  p_branch_id uuid default null,
  p_limit integer default 5000
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
  v_limit integer := least(greatest(coalesce(p_limit, 5000), 1), 5000);
  v_capacity_held integer;
  v_taxonomy jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_branch_id is null then
    select branch.* into v_branch
    from dastak_v1.merchant_branches branch
    where branch.status not in ('CLOSED', 'SUSPENDED')
      and dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id, branch.organization_id, 'merchant.catalogue.selection.manage', branch.id
      )
    order by branch.created_at, branch.id
    limit 1;
  else
    select branch.* into v_branch
    from dastak_v1.merchant_branches branch
    where branch.id = p_branch_id;
  end if;
  if not found then
    raise exception using errcode = 'P0002', message = 'merchant branch not found';
  end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_branch.organization_id, 'merchant.catalogue.selection.manage', v_branch.id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select organization.* into strict v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;
  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception using errcode = '22023', message = 'canonical SKU selection is retail-only';
  end if;

  select state.* into v_state
  from dastak_v1.branch_operational_states state
  where state.branch_id = v_branch.id;
  select pg_catalog.count(*) into v_capacity_held
  from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = v_branch.id and slot.status = 'HELD';
  v_taxonomy := dastak_v1_api.browse_catalogue_taxonomy(p_actor_id);

  return pg_catalog.jsonb_build_object(
    'branch', pg_catalog.jsonb_build_object(
      'branchId', v_branch.id,
      'branchName', v_branch.display_name,
      'branchStatus', v_branch.status,
      'branchVersion', v_branch.version,
      'organizationId', v_organization.id,
      'organizationName', v_organization.display_name,
      'merchantType', v_organization.merchant_type,
      'operationalState', pg_catalog.jsonb_build_object(
        'isOpen', coalesce(v_state.is_open, false),
        'acceptingOrders', coalesce(v_state.accepting_orders, false),
        'version', coalesce(v_state.version, 0),
        'updatedAt', v_state.updated_at
      ),
      'capacity', pg_catalog.jsonb_build_object(
        'limit', v_branch.capacity_limit,
        'held', v_capacity_held,
        'available', greatest(v_branch.capacity_limit - v_capacity_held, 0)
      )
    ),
    'skus', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'skuId', sku.id,
        'categoryTypeId', category.category_type_id,
        'categoryId', subcategory.category_id,
        'subcategoryId', sku.subcategory_id,
        'brandName', brand.name,
        'name', sku.canonical_name,
        'variant', sku.variant_name,
        'packSize', sku.pack_size,
        'description', sku.description,
        'imageKey', primary_image.image_key,
        'galleryImageKeys', coalesce((
          select pg_catalog.jsonb_agg(gallery.image_key order by gallery.sort_order, gallery.id)
          from dastak_v1.sku_images gallery
          where gallery.sku_id = sku.id
            and gallery.role = 'GALLERY'
            and gallery.status = 'VERIFIED'
            and gallery.rights_status = 'CLEARED'
        ), '[]'::jsonb),
        'quantityValue', sku.quantity_value,
        'quantityUnit', sku.quantity_unit,
        'packCount', sku.pack_count,
        'dietType', sku.diet_type,
        'searchTerms', coalesce((
          select pg_catalog.jsonb_agg(alias.alias order by alias.alias)
          from dastak_v1.sku_search_aliases alias
          where alias.sku_id = sku.id
        ), '[]'::jsonb),
        'listPricePaise', sku.list_price_paise,
        'sellingPricePaise', sku.selling_price_paise,
        'currencyCode', sku.currency_code,
        'catalogueStatus', sku.status,
        'selected', coalesce(selection.state = 'SELECTED', false),
        'selectionState', selection.state,
        'selectionVersion', coalesce(selection.version, 0),
        'selectionUpdatedAt', selection.updated_at
      ) order by category_type.sort_order, category.sort_order, subcategory.sort_order,
        pg_catalog.lower(sku.canonical_name), sku.id)
      from (
        select source.*
        from dastak_v1.skus source
        where source.status = 'ACTIVE'
          or exists (
            select 1
            from dastak_v1.merchant_sku_selections existing
            where existing.branch_id = v_branch.id and existing.sku_id = source.id
          )
        order by pg_catalog.lower(source.canonical_name), source.id
        limit v_limit
      ) sku
      join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
      join dastak_v1.categories category on category.id = subcategory.category_id
      left join dastak_v1.category_types category_type on category_type.id = category.category_type_id
      left join dastak_v1.brands brand on brand.id = sku.brand_id
      left join dastak_v1.merchant_sku_selections selection
        on selection.branch_id = v_branch.id and selection.sku_id = sku.id
      left join lateral (
        select image.image_key
        from dastak_v1.sku_images image
        where image.sku_id = sku.id
          and image.role = 'PRIMARY'
          and image.status = 'VERIFIED'
          and image.rights_status = 'CLEARED'
        order by image.sort_order, image.id
        limit 1
      ) primary_image on true
    ), '[]'::jsonb),
    'truncated', (
      select pg_catalog.count(*) > v_limit
      from dastak_v1.skus sku
      where sku.status = 'ACTIVE'
        or exists (
          select 1
          from dastak_v1.merchant_sku_selections existing
          where existing.branch_id = v_branch.id and existing.sku_id = sku.id
        )
    )
  ) || v_taxonomy;
end;
$$;

create or replace function public.dastak_v1_merchant_canonical_catalogue_snapshot(
  p_branch_id uuid default null,
  p_limit integer default 5000
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.merchant_canonical_catalogue_snapshot(
    auth.uid(), p_branch_id, p_limit
  );
$$;

revoke execute on function dastak_v1_api.browse_catalogue_taxonomy(uuid) from public, anon;
revoke execute on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid, uuid, integer) from public, anon;
grant execute on function dastak_v1_api.browse_catalogue_taxonomy(uuid) to authenticated;
grant execute on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid, uuid, integer) to authenticated;

comment on function dastak_v1_api.browse_catalogue_taxonomy(uuid) is
  'Authenticated non-inactive canonical hierarchy shared by Customer and Merchant, with customer-safe preview imagery.';
comment on function public.dastak_v1_customer_catalogue(text, uuid, uuid, integer, text, uuid) is
  'Customer-safe active SKU catalogue plus the complete non-inactive canonical hierarchy.';
comment on function public.dastak_v1_merchant_canonical_catalogue_snapshot(uuid, integer) is
  'Complete non-inactive hierarchy and up to 5,000 canonical retail SKUs for fast staged Merchant selection.';
