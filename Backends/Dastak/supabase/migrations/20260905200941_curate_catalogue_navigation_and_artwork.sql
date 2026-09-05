-- The canonical catalogue is deliberately much deeper than a customer-facing
-- category directory.  Keep every taxonomy node for Admin governance while
-- publishing a small, stable navigation section for the broad department
-- cards used by Customer and Merchant.

create or replace function dastak_v1_api.catalogue_navigation_section(
  p_category_type_slug text
)
returns jsonb
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_category_type_slug in (
      'fresh-produce', 'dairy-bread-eggs', 'staples-pantry', 'masala-cooking'
    ) then pg_catalog.jsonb_build_object(
      'key', 'grocery-kitchen', 'name', 'Grocery & Kitchen', 'sortOrder', 10
    )
    when p_category_type_slug in (
      'breakfast-spreads', 'snacks-munchies', 'biscuits-bakery', 'beverages',
      'tea-coffee-drink-mixes', 'chocolates-sweets',
      'instant-ready-frozen-food', 'paan-corner'
    ) then pg_catalog.jsonb_build_object(
      'key', 'snacks-drinks', 'name', 'Snacks & Drinks', 'sortOrder', 20
    )
    when p_category_type_slug in (
      'personal-care', 'beauty-grooming', 'health-hygiene', 'baby-care',
      'pharmacy'
    ) then pg_catalog.jsonb_build_object(
      'key', 'beauty-wellness', 'name', 'Beauty & Wellness', 'sortOrder', 30
    )
    when p_category_type_slug in (
      'home-cleaning', 'kitchen-dining', 'home-utility',
      'electronics-accessories', 'pet-care'
    ) then pg_catalog.jsonb_build_object(
      'key', 'household-essentials', 'name', 'Household Essentials',
      'sortOrder', 40
    )
    else pg_catalog.jsonb_build_object(
      'key', 'hobbies-interests', 'name', 'Hobbies & Interests', 'sortOrder', 50
    )
  end;
$$;

revoke all on function dastak_v1_api.catalogue_navigation_section(text)
  from public, anon, authenticated;

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
          order by category_sort_order, subcategory_sort_order,
            pg_catalog.lower(sku_name), sku_id
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
          image_key order by category_sort_order, subcategory_sort_order,
            pg_catalog.lower(sku_name), sku_id
        ) filter (where category_type_rank <= 2) as image_keys
      from ranked_images
      group by category_type_id
    ), category_previews as (
      select category_id,
        pg_catalog.jsonb_agg(
          image_key order by subcategory_sort_order, pg_catalog.lower(sku_name), sku_id
        ) filter (where category_rank <= 2) as image_keys
      from ranked_images
      group by category_id
    ), subcategory_previews as (
      select subcategory_id,
        pg_catalog.jsonb_agg(image_key order by pg_catalog.lower(sku_name), sku_id)
          filter (where subcategory_rank <= 1) as image_keys
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
          'navigationSection',
            dastak_v1_api.catalogue_navigation_section(category_type.slug),
          'status', category_type.status,
          'requiresControlledFlow', category_type.slug in ('pharmacy', 'paan-corner'),
          'sortOrder', category_type.sort_order
        ) order by category_type.sort_order, category_type.name, category_type.id)
        from dastak_v1.category_types category_type
        left join category_type_previews preview
          on preview.category_type_id = category_type.id
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
        ) order by category_type.sort_order, category.sort_order,
          category.name, category.id)
        from dastak_v1.categories category
        join dastak_v1.category_types category_type
          on category_type.id = category.category_type_id
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
        join dastak_v1.category_types category_type
          on category_type.id = category.category_type_id
        left join subcategory_previews preview
          on preview.subcategory_id = subcategory.id
        where subcategory.status <> 'INACTIVE'
          and category.status <> 'INACTIVE'
          and category_type.status <> 'INACTIVE'
      ), '[]'::jsonb)
    )
  );
end;
$$;

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

  return (
    with browse as materialized (
      select dastak_v1_api.browse_catalogue_taxonomy(p_actor_id) as value
    ), type_previews as materialized (
      select item ->> 'id' as id,
        item -> 'previewImageKeys' as image_keys,
        item -> 'navigationSection' as navigation_section
      from browse,
        lateral pg_catalog.jsonb_array_elements(value -> 'categoryTypes') item
    ), category_previews as materialized (
      select item ->> 'id' as id, item -> 'previewImageKeys' as image_keys
      from browse,
        lateral pg_catalog.jsonb_array_elements(value -> 'categories') item
    ), subcategory_previews as materialized (
      select item ->> 'id' as id, item -> 'previewImageKeys' as image_keys
      from browse,
        lateral pg_catalog.jsonb_array_elements(value -> 'subcategories') item
    )
    select pg_catalog.jsonb_build_object(
      'categoryTypes', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', category_type.id,
          'name', category_type.name,
          'slug', category_type.slug,
          'imageKey', category_type.image_key,
          'previewImageKeys', coalesce(preview.image_keys, '[]'::jsonb),
          'navigationSection', coalesce(
            preview.navigation_section,
            dastak_v1_api.catalogue_navigation_section(category_type.slug)
          ),
          'status', category_type.status,
          'sortOrder', category_type.sort_order,
          'version', category_type.version,
          'updatedAt', category_type.updated_at
        ) order by category_type.sort_order, category_type.name, category_type.id)
        from dastak_v1.category_types category_type
        left join type_previews preview on preview.id = category_type.id::text
      ), '[]'::jsonb),
      'categories', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', category.id,
          'categoryTypeId', category.category_type_id,
          'name', category.name,
          'slug', category.slug,
          'imageKey', category.image_key,
          'previewImageKeys', coalesce(preview.image_keys, '[]'::jsonb),
          'status', category.status,
          'sortOrder', category.sort_order,
          'version', category.version,
          'updatedAt', category.updated_at
        ) order by category_type.sort_order nulls last, category.sort_order,
          category.name, category.id)
        from dastak_v1.categories category
        left join dastak_v1.category_types category_type
          on category_type.id = category.category_type_id
        left join category_previews preview on preview.id = category.id::text
      ), '[]'::jsonb),
      'subcategories', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', subcategory.id,
          'categoryId', subcategory.category_id,
          'name', subcategory.name,
          'slug', subcategory.slug,
          'imageKey', subcategory.image_key,
          'previewImageKeys', coalesce(preview.image_keys, '[]'::jsonb),
          'status', subcategory.status,
          'sortOrder', subcategory.sort_order,
          'version', subcategory.version,
          'updatedAt', subcategory.updated_at
        ) order by category.sort_order, subcategory.sort_order,
          subcategory.name, subcategory.id)
        from dastak_v1.subcategories subcategory
        join dastak_v1.categories category on category.id = subcategory.category_id
        left join subcategory_previews preview on preview.id = subcategory.id::text
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
    )
  );
end;
$$;

comment on function dastak_v1_api.catalogue_navigation_section(text) is
  'Maps deep canonical departments into the five stable storefront navigation sections.';

comment on function dastak_v1_api.browse_catalogue_taxonomy(uuid) is
  'Publishes complete non-inactive taxonomy with rights-cleared artwork previews and curated navigation sections.';
