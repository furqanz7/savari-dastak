-- Forward correction for the already-active, evolved version-one browse map.
-- Preserve 20260929191745 unchanged for chronological fresh-environment replay.
-- This file does NOT repair history; the scoped release runner records that
-- supersession only after this correction and all release assertions succeed.
do $$
declare
  v_state text;
  v_invalid_skus bigint;
begin
  -- Briefly serialize map configuration changes, not order/inventory tables.
  lock table dastak_v1.catalogue_browse_versions,
    dastak_v1.catalogue_browse_nodes, dastak_v1.catalogue_browse_sources
    in share row exclusive mode;

  select state into v_state from dastak_v1.catalogue_browse_versions where version = 1;
  if v_state is distinct from 'ACTIVE' or exists (
    select 1 from dastak_v1.catalogue_browse_versions where state = 'ACTIVE' and version <> 1
  ) then
    raise exception 'Expected active catalogue browse map version 1; review before reconciliation';
  end if;
  if not exists (select 1 from dastak_v1.catalogue_browse_nodes
      where version = 1 and node_key = 'dairy-alternatives' and kind = 'RAIL'
        and parent_key = 'dairy-bread-eggs' and label = 'Dairy Alternatives')
    or not exists (select 1 from dastak_v1.catalogue_browse_nodes
      where version = 1 and node_key = 'dairy-bread-eggs' and kind = 'DESTINATION')
    or not exists (select 1 from dastak_v1.category_types t
      join dastak_v1.categories c on c.category_type_id = t.id
      where t.slug = 'dairy-bread-eggs' and c.slug = 'dairy-alternatives'
        and t.status = 'ACTIVE' and c.status = 'ACTIVE') then
    raise exception 'Dairy Alternatives browse/taxonomy identity differs; review before reconciliation';
  end if;

  insert into dastak_v1.catalogue_browse_sources
    (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
  values (1, 'dairy-alternatives', 10, 'dairy-bread-eggs', 'dairy-alternatives', null)
  on conflict (version, node_key, source_order) do nothing;
  if (select count(*) from dastak_v1.catalogue_browse_sources
      where version = 1 and node_key = 'dairy-alternatives') <> 1
    or not exists (select 1 from dastak_v1.catalogue_browse_sources
      where version = 1 and node_key = 'dairy-alternatives' and source_order = 10
        and type_slug = 'dairy-bread-eggs' and category_slug = 'dairy-alternatives'
        and subcategory_slug is null and excluded_category_slugs = '{}'::text[]
        and excluded_subcategory_slugs = '{}'::text[]) then
    raise exception 'Dairy Alternatives source conflicts with reviewed mapping';
  end if;

  -- Validate semantics rather than historical fixed node/source counts. Later
  -- approved changes (including prayer essentials) must survive unchanged.
  with sku_paths as (
    select sku.id, t.slug as type_slug, c.slug as category_slug,
      sc.slug as subcategory_slug,
      sc.status = 'ACTIVE' and c.status = 'ACTIVE' and t.status = 'ACTIVE'
        and (b.id is null or b.status = 'ACTIVE') as taxonomy_active
    from dastak_v1.skus sku
    left join dastak_v1.subcategories sc on sc.id = sku.subcategory_id
    left join dastak_v1.categories c on c.id = sc.category_id
    left join dastak_v1.category_types t on t.id = c.category_type_id
    left join dastak_v1.brands b on b.id = sku.brand_id
    where sku.status = 'ACTIVE'
  ), matches as (
    select distinct sku.id, n.kind, n.node_key, n.parent_key
    from sku_paths sku
    join dastak_v1.catalogue_browse_sources s on s.version = 1 and s.type_slug = sku.type_slug
      and (s.category_slug is null or s.category_slug = sku.category_slug)
      and (s.subcategory_slug is null or s.subcategory_slug = sku.subcategory_slug)
      and not (sku.category_slug = any(s.excluded_category_slugs))
      and not (sku.subcategory_slug = any(s.excluded_subcategory_slugs))
    join dastak_v1.catalogue_browse_nodes n on n.version = s.version and n.node_key = s.node_key
      and n.kind in ('DESTINATION', 'RAIL')
  ), coverage as (
    select sku.id, sku.taxonomy_active,
      count(distinct m.node_key) filter (where m.kind = 'DESTINATION') as destinations,
      max(m.node_key) filter (where m.kind = 'DESTINATION') as destination,
      count(distinct m.node_key) filter (where m.kind = 'RAIL') as rails,
      max(m.parent_key) filter (where m.kind = 'RAIL') as rail_parent
    from sku_paths sku left join matches m on m.id = sku.id
    group by sku.id, sku.taxonomy_active
  )
  select count(*) into v_invalid_skus from coverage
  where taxonomy_active is not true or destinations <> 1 or rails <> 1
    or destination is distinct from rail_parent;
  if v_invalid_skus <> 0 then
    raise exception 'Catalogue reconciliation has % invalid active SKU placements', v_invalid_skus;
  end if;
end;
$$;
