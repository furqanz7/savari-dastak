-- Remove every Millets & Grains SKU where integrity permits. Referenced SKUs
-- are archived instead of deleted so historical orders remain valid.
create temporary table _dastak_millets_grains_targets (
  sku_id uuid primary key,
  canonical_name text not null,
  refs bigint not null
) on commit drop;

insert into _dastak_millets_grains_targets (sku_id, canonical_name, refs)
select s.id, s.canonical_name, count(refs.sku_id)
  from dastak_v1.skus s
  join dastak_v1.subcategories sc on sc.id = s.subcategory_id
  join dastak_v1.categories c on c.id = sc.category_id
  left join (
    select sku_id from dastak_v1.order_lines
    union all select sku_id from dastak_v1.merchant_stock_reservations
    union all select sku_id from dastak_v1.merchant_sku_selections
    union all select sku_id from dastak_v1.merchant_opportunity_lines
    union all select sku_id from dastak_v1.recovery_opportunities
  ) refs on refs.sku_id = s.id
 where c.slug = 'millets-grains'
 group by s.id, s.canonical_name;

insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
select
  '7105206a-6fec-45c9-8c00-3dfd5178fc1b',
  'CATALOGUE_SKU_DELETED',
  'catalogue_sku',
  t.sku_id,
  jsonb_build_object('name', t.canonical_name, 'reason', 'operator requested Millets & Grains removal')
from _dastak_millets_grains_targets t
where t.refs = 0;

delete from dastak_v1.skus s
using _dastak_millets_grains_targets t
where s.id = t.sku_id
  and t.refs = 0;

update dastak_v1.skus s
   set status = 'INACTIVE', updated_at = now(), version = version + 1
  from _dastak_millets_grains_targets t
 where s.id = t.sku_id and t.refs > 0 and s.status <> 'INACTIVE';

delete from dastak_v1.merchant_sku_selections selection
using _dastak_millets_grains_targets t
where selection.sku_id = t.sku_id and t.refs > 0;

insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
select
  '7105206a-6fec-45c9-8c00-3dfd5178fc1b',
  'CATALOGUE_SKU_ARCHIVED',
  'catalogue_sku',
  t.sku_id,
  jsonb_build_object('name', t.canonical_name, 'references', t.refs, 'reason', 'operator requested Millets & Grains removal')
from _dastak_millets_grains_targets t
where t.refs > 0;

do $$
declare
  v_deleted integer;
  v_retained integer;
begin
  select count(*) into v_deleted from _dastak_millets_grains_targets where refs = 0;
  select count(*) into v_retained from _dastak_millets_grains_targets where refs > 0;
  raise notice 'Permanently deleted % Millets & Grains SKU(s); retained % referenced SKU(s) as archived', v_deleted, v_retained;
end
$$;
