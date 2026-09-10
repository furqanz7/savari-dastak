-- Repair Restaurant/Cafe menu updates and make default Store discovery
-- select an applicable retail branch instead of whichever branch was created first.

create or replace function dastak_v1.guard_restaurant_versioned_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new jsonb := pg_catalog.to_jsonb(new);
  v_old jsonb := pg_catalog.to_jsonb(old);
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
    and v_new -> 'category_id' is distinct from v_old -> 'category_id' then
    raise exception 'restaurant menu item category cannot change';
  end if;
  if tg_table_name = 'restaurant_menu_option_groups'
    and v_new -> 'menu_item_id' is distinct from v_old -> 'menu_item_id' then
    raise exception 'restaurant option-group item cannot change';
  end if;
  if tg_table_name = 'restaurant_menu_options'
    and (v_new -> 'menu_item_id' is distinct from v_old -> 'menu_item_id'
      or v_new -> 'option_group_id' is distinct from v_old -> 'option_group_id') then
    raise exception 'restaurant option identity cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
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
    join dastak_v1.merchant_organizations organization
      on organization.id = branch.organization_id
     and organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
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
    raise exception using errcode = 'P0002', message = 'retail merchant branch not found';
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
    raise exception using errcode = 'P0002', message = 'retail merchant branch not found';
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
        'stockQuantity', selection.stock_quantity,
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

comment on function dastak_v1.guard_restaurant_versioned_row() is
  'Protects immutable Restaurant/Cafe menu identity and optimistic versions without referencing fields absent from another menu table.';
