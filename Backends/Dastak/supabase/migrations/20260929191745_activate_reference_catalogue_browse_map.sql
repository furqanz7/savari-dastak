-- Record the already-live promotion as a reproducible, fail-closed migration.
-- A fresh environment remains on the draft map if any active SKU is missing,
-- duplicated, or placed under a rail outside its sole destination.
do $$
declare
  v_state text;
  v_invalid_skus bigint;
begin
  select state into v_state
  from dastak_v1.catalogue_browse_versions
  where version = 1;

  if v_state is null then
    raise exception 'Reference catalogue browse map version 1 is missing';
  end if;
  if v_state not in ('DRAFT', 'ACTIVE') then
    raise exception 'Reference catalogue browse map is %', v_state;
  end if;
  if exists (
    select 1 from dastak_v1.catalogue_browse_versions
    where state = 'ACTIVE' and version <> 1
  ) then
    raise exception 'Another catalogue browse map is already active';
  end if;

  -- The reference has a Dairy Alternatives rail. Its exact canonical category
  -- can contain an active soy-milk SKU on a clean replay, so map that path.
  insert into dastak_v1.catalogue_browse_sources
    (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
  values (1, 'dairy-alternatives', 10, 'dairy-bread-eggs', 'dairy-alternatives', null)
  on conflict (version, node_key, source_order) do nothing;
  if not exists (
    select 1 from dastak_v1.catalogue_browse_sources
    where version = 1 and node_key = 'dairy-alternatives' and source_order = 10
      and type_slug = 'dairy-bread-eggs' and category_slug = 'dairy-alternatives'
      and subcategory_slug is null
  ) then
    raise exception 'Dairy Alternatives source path differs from the reference map';
  end if;

  if (select count(*) from dastak_v1.catalogue_browse_nodes
      where version = 1) <> 112
     or (select count(*) from dastak_v1.catalogue_browse_sources
      where version = 1) <> 125 then
    raise exception 'Reference catalogue browse map shape differs from the reviewed release';
  end if;

  with sku_paths as (
    select sku.id, category_type.slug as type_slug,
      category.slug as category_slug,
      subcategory.slug as subcategory_slug,
      subcategory.status = 'ACTIVE'
        and category.status = 'ACTIVE'
        and category_type.status = 'ACTIVE'
        and (brand.id is null or brand.status = 'ACTIVE') as taxonomy_active
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory
      on subcategory.id = sku.subcategory_id
    join dastak_v1.categories category
      on category.id = subcategory.category_id
    join dastak_v1.category_types category_type
      on category_type.id = category.category_type_id
    left join dastak_v1.brands brand on brand.id = sku.brand_id
    where sku.status = 'ACTIVE'
  ), matches as (
    select distinct sku.id, node.kind, node.node_key, node.parent_key
    from sku_paths sku
    join dastak_v1.catalogue_browse_sources source
      on source.version = 1 and source.type_slug = sku.type_slug
      and (source.category_slug is null
        or source.category_slug = sku.category_slug)
      and (source.subcategory_slug is null
        or source.subcategory_slug = sku.subcategory_slug)
      and not (sku.category_slug = any(source.excluded_category_slugs))
      and not (sku.subcategory_slug = any(source.excluded_subcategory_slugs))
    join dastak_v1.catalogue_browse_nodes node
      on node.version = source.version and node.node_key = source.node_key
      and node.kind in ('DESTINATION', 'RAIL')
  ), coverage as (
    select sku.id, sku.taxonomy_active,
      count(distinct matches.node_key) filter (
        where matches.kind = 'DESTINATION') as destination_count,
      max(matches.node_key) filter (
        where matches.kind = 'DESTINATION') as destination_key,
      count(distinct matches.node_key) filter (
        where matches.kind = 'RAIL') as rail_count,
      max(matches.parent_key) filter (
        where matches.kind = 'RAIL') as rail_parent_key
    from sku_paths sku
    left join matches on matches.id = sku.id
    group by sku.id, sku.taxonomy_active
  )
  select count(*) into v_invalid_skus
  from coverage
  where taxonomy_active is not true or destination_count <> 1 or rail_count <> 1
    or destination_key is distinct from rail_parent_key;

  if v_invalid_skus <> 0 then
    raise exception 'Reference catalogue browse map has % invalid active SKU placements',
      v_invalid_skus;
  end if;

  update dastak_v1.catalogue_browse_versions
  set state = 'ACTIVE'
  where version = 1 and state = 'DRAFT';
end;
$$;
