-- Read-only gate for the draft reference browse map. Run only after the
-- catalogue_browse_* migration has been applied in a safe test environment.
-- Every active SKU must land in exactly one first-level destination and one
-- rail beneath it. Two rails within a destination must not claim the same SKU.
with active_skus as (
  select sku.id, sku.slug, sku.canonical_name,
         ct.slug as type_slug, category.slug as category_slug,
         subcategory.slug as subcategory_slug
  from dastak_v1.skus sku
  join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
  join dastak_v1.categories category on category.id = subcategory.category_id
  join dastak_v1.category_types ct on ct.id = category.category_type_id
  where sku.status = 'ACTIVE'
), destination_matches as (
  select distinct sku.id, node.node_key
  from active_skus sku
  join dastak_v1.catalogue_browse_sources source
    on source.version = 1 and source.type_slug = sku.type_slug
   and (source.category_slug is null or source.category_slug = sku.category_slug)
   and (source.subcategory_slug is null or source.subcategory_slug = sku.subcategory_slug)
   and not (sku.category_slug = any(source.excluded_category_slugs))
   and not (sku.subcategory_slug = any(source.excluded_subcategory_slugs))
  join dastak_v1.catalogue_browse_nodes node
    on node.version = source.version and node.node_key = source.node_key
   and node.kind = 'DESTINATION'
), coverage as (
  select sku.id, count(match.node_key) as destination_count
  from active_skus sku left join destination_matches match on match.id = sku.id
  group by sku.id
)
select count(*) as active_skus,
       count(*) filter (where destination_count = 1) as exactly_one_destination,
       count(*) filter (where destination_count = 0) as unmapped_skus,
       count(*) filter (where destination_count > 1) as duplicate_destination_skus
from coverage;

-- Any returned row needs an explicit catalogue decision before activation.
with active_skus as (
  select sku.id, sku.slug, sku.canonical_name,
         ct.slug as type_slug, category.slug as category_slug,
         subcategory.slug as subcategory_slug
  from dastak_v1.skus sku
  join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
  join dastak_v1.categories category on category.id = subcategory.category_id
  join dastak_v1.category_types ct on ct.id = category.category_type_id
  where sku.status = 'ACTIVE'
), matches as (
  select distinct sku.id, node.node_key
  from active_skus sku
  join dastak_v1.catalogue_browse_sources source
    on source.version = 1 and source.type_slug = sku.type_slug
   and (source.category_slug is null or source.category_slug = sku.category_slug)
   and (source.subcategory_slug is null or source.subcategory_slug = sku.subcategory_slug)
   and not (sku.category_slug = any(source.excluded_category_slugs))
   and not (sku.subcategory_slug = any(source.excluded_subcategory_slugs))
  join dastak_v1.catalogue_browse_nodes node
    on node.version = source.version and node.node_key = source.node_key
   and node.kind = 'DESTINATION'
)
select sku.id, sku.slug, sku.canonical_name,
       sku.type_slug, sku.category_slug, sku.subcategory_slug,
       count(match.node_key) as destination_count,
       coalesce(array_agg(match.node_key order by match.node_key)
         filter (where match.node_key is not null), '{}') as destinations
from active_skus sku left join matches match on match.id = sku.id
group by sku.id, sku.slug, sku.canonical_name,
         sku.type_slug, sku.category_slug, sku.subcategory_slug
having count(match.node_key) <> 1
order by sku.type_slug, sku.category_slug, sku.subcategory_slug, sku.slug;

-- The same gate at shelf level. Run this against a test database with the
-- catalogue migration and SKU reparenting migrations applied, not production.
with active_skus as (
  select sku.id, sku.slug, ct.slug as type_slug,
         category.slug as category_slug, subcategory.slug as subcategory_slug
  from dastak_v1.skus sku
  join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
  join dastak_v1.categories category on category.id = subcategory.category_id
  join dastak_v1.category_types ct on ct.id = category.category_type_id
  where sku.status = 'ACTIVE'
), matches as (
  select distinct sku.id, node.node_key
  from active_skus sku
  join dastak_v1.catalogue_browse_sources source
    on source.version = 1 and source.type_slug = sku.type_slug
   and (source.category_slug is null or source.category_slug = sku.category_slug)
   and (source.subcategory_slug is null or source.subcategory_slug = sku.subcategory_slug)
   and not (sku.category_slug = any(source.excluded_category_slugs))
   and not (sku.subcategory_slug = any(source.excluded_subcategory_slugs))
  join dastak_v1.catalogue_browse_nodes node
    on node.version = source.version and node.node_key = source.node_key
   and node.kind = 'RAIL'
), coverage as (
  select sku.id, count(match.node_key) as rail_count
  from active_skus sku left join matches match on match.id = sku.id
  group by sku.id
)
select count(*) as active_skus,
       count(*) filter (where rail_count = 1) as exactly_one_rail,
       count(*) filter (where rail_count = 0) as unmapped_rail_skus,
       count(*) filter (where rail_count > 1) as duplicate_rail_skus
from coverage;

with active_skus as (
  select sku.id, sku.slug, ct.slug as type_slug,
         category.slug as category_slug, subcategory.slug as subcategory_slug
  from dastak_v1.skus sku
  join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
  join dastak_v1.categories category on category.id = subcategory.category_id
  join dastak_v1.category_types ct on ct.id = category.category_type_id
  where sku.status = 'ACTIVE'
), matches as (
  select distinct sku.id, node.node_key
  from active_skus sku
  join dastak_v1.catalogue_browse_sources source
    on source.version = 1 and source.type_slug = sku.type_slug
   and (source.category_slug is null or source.category_slug = sku.category_slug)
   and (source.subcategory_slug is null or source.subcategory_slug = sku.subcategory_slug)
   and not (sku.category_slug = any(source.excluded_category_slugs))
   and not (sku.subcategory_slug = any(source.excluded_subcategory_slugs))
  join dastak_v1.catalogue_browse_nodes node
    on node.version = source.version and node.node_key = source.node_key
   and node.kind = 'RAIL'
)
select sku.slug, sku.type_slug, sku.category_slug, sku.subcategory_slug,
       count(match.node_key) as rail_count,
       coalesce(array_agg(match.node_key order by match.node_key)
         filter (where match.node_key is not null), '{}') as rails
from active_skus sku left join matches match on match.id = sku.id
group by sku.id, sku.slug, sku.type_slug, sku.category_slug, sku.subcategory_slug
having count(match.node_key) <> 1
order by sku.type_slug, sku.category_slug, sku.subcategory_slug, sku.slug;
