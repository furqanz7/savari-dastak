-- Read-only production preflight. No products, map rows or history are changed.
begin read only;
set local statement_timeout = '15s';
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
  join dastak_v1.catalogue_browse_sources s on s.version = 1
    and s.type_slug = sku.type_slug
    and (s.category_slug is null or s.category_slug = sku.category_slug)
    and (s.subcategory_slug is null or s.subcategory_slug = sku.subcategory_slug)
    and not (sku.category_slug = any(s.excluded_category_slugs))
    and not (sku.subcategory_slug = any(s.excluded_subcategory_slugs))
  join dastak_v1.catalogue_browse_nodes n
    on n.version = s.version and n.node_key = s.node_key
    and n.kind in ('DESTINATION', 'RAIL')
), coverage as (
  select sku.id, sku.taxonomy_active, sku.type_slug, sku.category_slug,
    sku.subcategory_slug,
    count(distinct m.node_key) filter (where m.kind = 'DESTINATION') as destinations,
    max(m.node_key) filter (where m.kind = 'DESTINATION') as destination,
    count(distinct m.node_key) filter (where m.kind = 'RAIL') as rails,
    max(m.parent_key) filter (where m.kind = 'RAIL') as rail_parent
  from sku_paths sku left join matches m on m.id = sku.id
  group by sku.id, sku.taxonomy_active, sku.type_slug, sku.category_slug, sku.subcategory_slug
), invalid as (
  select * from coverage where taxonomy_active is not true or destinations <> 1
    or rails <> 1 or destination is distinct from rail_parent
)
select jsonb_build_object(
  'migrationRecorded', exists(select 1 from supabase_migrations.schema_migrations where version = '20260929191745'),
  'versions', (select jsonb_agg(to_jsonb(v) order by version) from dastak_v1.catalogue_browse_versions v),
  'nodes', (select count(*) from dastak_v1.catalogue_browse_nodes where version = 1),
  'sources', (select count(*) from dastak_v1.catalogue_browse_sources where version = 1),
  'nodesFingerprint', (select md5(coalesce(jsonb_agg(to_jsonb(n) order by node_key)::text, '[]'))
    from dastak_v1.catalogue_browse_nodes n where version = 1),
  'sourcesFingerprint', (select md5(coalesce(jsonb_agg(to_jsonb(s) order by node_key, source_order)::text, '[]'))
    from dastak_v1.catalogue_browse_sources s where version = 1),
  'activeSkus', (select count(*) from sku_paths),
  'invalidActiveSkus', (select count(*) from invalid),
  'invalidPaths', (select jsonb_agg(p) from (select distinct type_slug, category_slug, subcategory_slug,
      taxonomy_active, destinations, rails, destination, rail_parent from invalid limit 20) p),
  'dairyAlternativeSources', (select jsonb_agg(to_jsonb(s) order by source_order)
    from dastak_v1.catalogue_browse_sources s where version = 1 and node_key = 'dairy-alternatives'),
  'activeDairyAlternativeSkus', (select count(*) from sku_paths
    where type_slug = 'dairy-bread-eggs' and category_slug = 'dairy-alternatives')
) as reconciliation;
rollback;
