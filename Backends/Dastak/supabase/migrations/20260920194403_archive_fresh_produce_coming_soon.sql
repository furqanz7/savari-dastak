-- Retire the Fresh Produce launch set without deleting order history. The
-- category-type status is what the customer navigation renders as
-- "Coming soon" when it is not ACTIVE.
create temporary table _dastak_fresh_produce_archive_targets (
  sku_id uuid primary key,
  canonical_name text not null,
  previous_status text not null
) on commit drop;

insert into _dastak_fresh_produce_archive_targets (sku_id, canonical_name, previous_status)
select s.id, s.canonical_name, s.status::text
  from dastak_v1.skus s
  join dastak_v1.subcategories sc on sc.id = s.subcategory_id
  join dastak_v1.categories c on c.id = sc.category_id
  join dastak_v1.category_types ct on ct.id = c.category_type_id
 where ct.slug = 'fresh-produce'
   and s.status <> 'INACTIVE';

update dastak_v1.skus s
   set status = 'INACTIVE',
       updated_at = now(),
       version = s.version + 1
  from _dastak_fresh_produce_archive_targets t
 where s.id = t.sku_id;

update dastak_v1.category_types ct
   set status = 'INACTIVE',
       updated_at = now(),
       version = ct.version + 1
 where ct.slug = 'fresh-produce'
   and ct.status <> 'INACTIVE';

insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
select
  '7105206a-6fec-45c9-8c00-3dfd5178fc1b',
  'CATALOGUE_SKU_ARCHIVED',
  'catalogue_sku',
  t.sku_id,
  jsonb_build_object(
    'name', t.canonical_name,
    'previousStatus', t.previous_status,
    'reason', 'Fresh Produce moved to Coming soon'
  )
from _dastak_fresh_produce_archive_targets t;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from _dastak_fresh_produce_archive_targets;
  raise notice 'Archived % Fresh Produce SKU(s) and marked the category Coming soon', v_count;
end
$$;
