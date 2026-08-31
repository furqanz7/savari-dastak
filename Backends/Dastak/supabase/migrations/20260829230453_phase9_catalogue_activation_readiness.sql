create or replace view dastak_v1.catalogue_activation_readiness
with (security_invoker = true)
as
select
  s.id as sku_id,
  s.canonical_name,
  s.status as sku_status,
  s.qa_status,
  s.list_price_paise,
  s.selling_price_paise,
  sc.status as subcategory_status,
  c.status as category_status,
  ct.status as category_type_status,
  b.status as brand_status,
  exists (
    select 1 from dastak_v1.catalogue_import_items i
    where i.canonical_sku_id=s.id
  ) as has_source_provenance,
  exists (
    select 1 from dastak_v1.sku_images im
    where im.sku_id=s.id and im.role='PRIMARY'
  ) as has_primary_image,
  exists (
    select 1 from dastak_v1.sku_images im
    where im.sku_id=s.id and im.role='PRIMARY' and im.status='VERIFIED'
  ) as has_verified_primary_image,
  exists (
    select 1 from dastak_v1.sku_images im
    where im.sku_id=s.id and im.role='PRIMARY' and im.rights_status='CLEARED'
  ) as has_rights_cleared_primary_image,
  exists (
    select 1 from dastak_v1.sku_images im
    where im.sku_id=s.id and im.role='PRIMARY' and im.status='VERIFIED' and im.rights_status='CLEARED'
  ) as has_activation_ready_primary_image,
  array_remove(array[
    case when s.qa_status <> 'VERIFIED' then 'QA_VERIFIED_REQUIRED' end,
    case when s.list_price_paise is null or s.selling_price_paise is null then 'DASTAK_PRICING_REQUIRED' end,
    case when ct.status <> 'ACTIVE' then 'CATEGORY_TYPE_ACTIVE_REQUIRED' end,
    case when c.status <> 'ACTIVE' then 'CATEGORY_ACTIVE_REQUIRED' end,
    case when sc.status <> 'ACTIVE' then 'SUBCATEGORY_ACTIVE_REQUIRED' end,
    case when s.brand_id is not null and b.status <> 'ACTIVE' then 'BRAND_ACTIVE_REQUIRED' end,
    case when not exists (select 1 from dastak_v1.catalogue_import_items i where i.canonical_sku_id=s.id) then 'SOURCE_PROVENANCE_REQUIRED' end,
    case when not exists (select 1 from dastak_v1.sku_images im where im.sku_id=s.id and im.role='PRIMARY') then 'PRIMARY_IMAGE_REQUIRED' end,
    case when exists (select 1 from dastak_v1.sku_images im where im.sku_id=s.id and im.role='PRIMARY')
           and not exists (select 1 from dastak_v1.sku_images im where im.sku_id=s.id and im.role='PRIMARY' and im.status='VERIFIED') then 'PRIMARY_IMAGE_VERIFICATION_REQUIRED' end,
    case when exists (select 1 from dastak_v1.sku_images im where im.sku_id=s.id and im.role='PRIMARY')
           and not exists (select 1 from dastak_v1.sku_images im where im.sku_id=s.id and im.role='PRIMARY' and im.rights_status='CLEARED') then 'IMAGE_RIGHTS_CLEARANCE_REQUIRED' end
  ]::text[],null) as blockers,
  (
    s.qa_status='VERIFIED'
    and s.list_price_paise is not null
    and s.selling_price_paise is not null
    and ct.status='ACTIVE'
    and c.status='ACTIVE'
    and sc.status='ACTIVE'
    and (s.brand_id is null or b.status='ACTIVE')
    and exists (select 1 from dastak_v1.catalogue_import_items i where i.canonical_sku_id=s.id)
    and exists (select 1 from dastak_v1.sku_images im where im.sku_id=s.id and im.role='PRIMARY' and im.status='VERIFIED' and im.rights_status='CLEARED')
  ) as activation_ready
from dastak_v1.skus s
join dastak_v1.subcategories sc on sc.id=s.subcategory_id
join dastak_v1.categories c on c.id=sc.category_id
join dastak_v1.category_types ct on ct.id=c.category_type_id
left join dastak_v1.brands b on b.id=s.brand_id;;
