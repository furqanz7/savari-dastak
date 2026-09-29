-- Archive the requested brands only within the Dals & Pulses catalogue
-- category. Historical order/inventory rows remain untouched; the existing
-- archive trigger removes any merchant selections for these SKUs.
create temporary table _dastak_archive_targets (
  sku_id uuid primary key,
  canonical_name text not null,
  previous_status text not null
) on commit drop;

insert into _dastak_archive_targets (sku_id, canonical_name, previous_status)
select s.id, s.canonical_name, s.status::text
  from dastak_v1.skus s
  join dastak_v1.brands b on b.id = s.brand_id
  join dastak_v1.subcategories sc on sc.id = s.subcategory_id
  join dastak_v1.categories c on c.id = sc.category_id
 where c.slug = 'dals-pulses'
   and lower(trim(b.name)) in (
     'conscious food',
     'idhayam',
     'organic india',
     'organic tatva',
     'two brothers'
   )
   and s.status <> 'INACTIVE';

update dastak_v1.skus s
   set status = 'INACTIVE',
       updated_at = now(),
       version = s.version + 1
  from _dastak_archive_targets t
 where s.id = t.sku_id;

insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
select
  '7105206a-6fec-45c9-8c00-3dfd5178fc1b',
  'CATALOGUE_SKU_ARCHIVED',
  'catalogue_sku',
  t.sku_id,
  jsonb_build_object(
    'name', t.canonical_name,
    'previousStatus', t.previous_status,
    'reason', 'operator requested selected Dals & Pulses brands be archived'
  )
from _dastak_archive_targets t;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from _dastak_archive_targets;
  raise notice 'Archived % Dals & Pulses SKU(s) for the requested brands', v_count;
end
$$;
