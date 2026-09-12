begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (select pg_catalog.array_agg(bundle.bundle_key order by bundle.bundle_key)
   from dastak_v1.permission_bundle_permissions permission
   join dastak_v1.permission_bundles bundle on bundle.id = permission.bundle_id
   where permission.permission_key = 'platform.catalogue.assets.manage'),
  array['catalogue_admin','executive_admin','platform_super_admin']::text[],
  'catalogue asset governance keeps the intentional C2.1 bundle scope'
);
select is(has_function_privilege('authenticated', 'public.dastak_v1_admin_catalogue_sku_assets(uuid)', 'EXECUTE'), true, 'authenticated callers reach caller-bound projection authorization');
select is(has_function_privilege('authenticated', 'public.dastak_v1_admin_prepare_catalogue_asset(uuid,uuid,bigint,text,bigint,text,text,text,text)', 'EXECUTE'), false, 'browser role cannot execute privileged asset preparation');
select is(has_function_privilege('service_role', 'public.dastak_v1_admin_prepare_catalogue_asset(uuid,uuid,bigint,text,bigint,text,text,text,text)', 'EXECUTE'), true, 'existing Edge service boundary can prepare an asset');
select is(has_table_privilege('authenticated', 'dastak_v1.sku_images', 'INSERT'), false, 'browser cannot create asset metadata directly');
select is(has_table_privilege('authenticated', 'dastak_v1.sku_images', 'UPDATE'), false, 'browser cannot alter SKU association or primary state directly');
select is(has_table_privilege('authenticated', 'dastak_v1.sku_images', 'DELETE'), false, 'browser cannot delete asset metadata directly');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c2500000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c25-super@example.test','',now(),'{}','{}',now(),now()),
  ('c2500000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c25-customer@example.test','',now(),'{}','{}',now(),now()),
  ('c2500000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c25-inactive@example.test','',now(),'{}','{}',now(),now());
insert into public.accounts (id, display_name, phone_number, account_state) values
  ('c2500000-0000-4000-8000-000000000001','C25 Superadmin','+919750000001','ACTIVE'),
  ('c2500000-0000-4000-8000-000000000002','C25 Customer','+919750000002','ACTIVE'),
  ('c2500000-0000-4000-8000-000000000003','C25 Inactive Catalogue Admin','+919750000003','ACTIVE');
insert into private.account_memberships (account_id, role, approved_at, suspended_until) values
  ('c2500000-0000-4000-8000-000000000001','owner',now(),null),
  ('c2500000-0000-4000-8000-000000000002','customer',null,null),
  ('c2500000-0000-4000-8000-000000000003','owner',now(),now() + interval '1 day');
select lives_ok($$select dastak_v1_api.bootstrap_superadmin('c2500000-0000-4000-8000-000000000001')$$, 'rollback fixture establishes Superadmin');
insert into dastak_v1.platform_permission_grants(account_id,bundle_id,granted_by,grant_reason)
select 'c2500000-0000-4000-8000-000000000003', bundle.id,
       'c2500000-0000-4000-8000-000000000001', 'inactive authorization fixture'
from dastak_v1.permission_bundles bundle where bundle.bundle_key='catalogue_admin';

insert into dastak_v1.category_types(id,name,slug,status,created_by) values
  ('c2510000-0000-4000-8000-000000000001','C25 Department','c25-department','DRAFT','c2500000-0000-4000-8000-000000000001');
insert into dastak_v1.categories(id,category_type_id,name,slug,status,created_by) values
  ('c2520000-0000-4000-8000-000000000001','c2510000-0000-4000-8000-000000000001','C25 Category','c25-category','DRAFT','c2500000-0000-4000-8000-000000000001');
insert into dastak_v1.subcategories(id,category_id,name,slug,status,created_by) values
  ('c2530000-0000-4000-8000-000000000001','c2520000-0000-4000-8000-000000000001','C25 Subcategory','c25-subcategory','DRAFT','c2500000-0000-4000-8000-000000000001');
insert into dastak_v1.skus(id,subcategory_id,canonical_name,slug,variant_name,pack_size,list_price_paise,selling_price_paise,status,created_by) values
  ('c2540000-0000-4000-8000-000000000001','c2530000-0000-4000-8000-000000000001','C25 Exact Product','c25-exact-product','Original','500 g',10000,9500,'DRAFT','c2500000-0000-4000-8000-000000000001'),
  ('c2540000-0000-4000-8000-000000000002','c2530000-0000-4000-8000-000000000001','C25 Other Product','c25-other-product','Other','1 kg',20000,19000,'DRAFT','c2500000-0000-4000-8000-000000000001');
insert into dastak_v1.sku_images(
  id,sku_id,image_key,role,sort_order,source_type,source_reference,checksum_sha256,
  width_pixels,height_pixels,mime_type,status,created_by,verified_by,verified_at,
  rights_status,rights_reference,rights_verified_by,rights_verified_at
) values
  ('c2550000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001','canonical/c25/original.png','PRIMARY',0,'MANUFACTURER','Original source',repeat('a',64),600,600,'image/png','VERIFIED','c2500000-0000-4000-8000-000000000001','c2500000-0000-4000-8000-000000000001',now(),'CLEARED','Original rights','c2500000-0000-4000-8000-000000000001',now());
create temporary table c25_sku_before as
select canonical_name,variant_name,pack_size,list_price_paise,selling_price_paise,subcategory_id,brand_id
from dastak_v1.skus where id='c2540000-0000-4000-8000-000000000001';

select set_config('request.jwt.claim.sub','c2500000-0000-4000-8000-000000000001',true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_catalogue_sku_assets('c2540000-0000-4000-8000-000000000001')$$, 'authorized Admin reads exact-SKU assets');
select is(public.dastak_v1_admin_catalogue_sku_assets('c2540000-0000-4000-8000-000000000001') #>> '{assets,0,skuId}', 'c2540000-0000-4000-8000-000000000001', 'projection preserves exact SKU association');
reset role;

select set_config('request.jwt.claim.sub','c2500000-0000-4000-8000-000000000002',true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_catalogue_sku_assets('c2540000-0000-4000-8000-000000000001')$$,'42501','platform permission required','ordinary authenticated Customer is denied');
reset role;
select set_config('request.jwt.claim.sub','c2500000-0000-4000-8000-000000000003',true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_catalogue_sku_assets('c2540000-0000-4000-8000-000000000001')$$,'42501','platform permission required','suspended owner assignment removes catalogue asset access');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_catalogue_sku_assets('c2540000-0000-4000-8000-000000000001')$$,'42501','authentication required','authenticated role without subject is denied');
reset role;

set local role service_role;
create temporary table c25_prepare as select public.dastak_v1_admin_prepare_catalogue_asset(
  'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',1,
  'image/png',1024,'MANUFACTURER','Reviewed manufacturer product page','Correct exact-SKU image','c25-prepare'
) body;
select is((select body #>> '{assetVersion}' from c25_prepare),'2','asset preparation advances asset-only version');
select is((select body from c25_prepare), public.dastak_v1_admin_prepare_catalogue_asset(
  'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',1,
  'image/png',1024,'MANUFACTURER','Reviewed manufacturer product page','Correct exact-SKU image','c25-prepare'
),'identical preparation replay is idempotent');
select matches((select body #>> '{imageKey}' from c25_prepare),'^canonical/admin/c2540000-0000-4000-8000-000000000001/.+\.png$','database generates the exact-SKU storage path');

-- Preparing an upload reserves its exact asset row. Another governed asset
-- operation may advance the SKU version while Storage writes; finalization of
-- that already-authorized upload must still be able to complete.
reset role;
update dastak_v1.skus
set asset_version = asset_version + 1
where id = 'c2540000-0000-4000-8000-000000000001';
set local role service_role;
create temporary table c25_finalize as select public.dastak_v1_admin_finalize_catalogue_asset(
  'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',
  ((select body #>> '{assetId}' from c25_prepare)::uuid),2,repeat('b',64),'image/png',1024,800,800,
  'Correct exact-SKU image','c25-finalize'
) body;
select is((select body #>> '{assetVersion}' from c25_finalize),'4','prepared upload finalizes after an intervening asset-version advance');
select throws_ok(
  $$select public.dastak_v1_admin_finalize_catalogue_asset(
    'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000002',
    (select body #>> '{asset,id}' from c25_finalize)::uuid,1,repeat('b',64),'image/png',1024,800,800,
    'Wrong association attempt','c25-cross-sku')$$,
  'P0002','catalogue asset not found for SKU','an asset cannot be finalized against another SKU'
);
create temporary table c25_promote as select public.dastak_v1_admin_promote_catalogue_primary_asset(
  'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',
  ((select body #>> '{asset,id}' from c25_finalize)::uuid),'c2550000-0000-4000-8000-000000000001',4,
  'Replace inaccurate primary image','c25-promote'
) body;
select is((select body #>> '{assetVersion}' from c25_promote),'5','atomic primary replacement advances version');
reset role;
select is((select pg_catalog.count(*) from dastak_v1.sku_images where sku_id='c2540000-0000-4000-8000-000000000001' and role='PRIMARY' and status='VERIFIED' and rights_status='CLEARED'),1::bigint,'exactly one valid primary remains');
set local role service_role;
select throws_ok(
  $$select public.dastak_v1_admin_remove_catalogue_asset(
    'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',
    (select body #>> '{asset,id}' from c25_finalize)::uuid,5,'Do not remove primary','c25-remove-primary')$$,
  '55000','CATALOGUE_PRIMARY_ASSET_REQUIRES_REPLACEMENT','current primary cannot be removed'
);
create temporary table c25_remove as select public.dastak_v1_admin_remove_catalogue_asset(
  'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',
  'c2550000-0000-4000-8000-000000000001',5,'Remove superseded unused image','c25-remove-old'
) body;
select is((select body #>> '{assetVersion}' from c25_remove),'6','unused former primary can be removed');
select is((select body from c25_remove), public.dastak_v1_admin_remove_catalogue_asset(
  'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',
  'c2550000-0000-4000-8000-000000000001',5,'Remove superseded unused image','c25-remove-old'
),'identical removal replay remains safe for storage reconciliation');
select throws_ok(
  $$select public.dastak_v1_admin_prepare_catalogue_asset(
    'c2500000-0000-4000-8000-000000000001','c2540000-0000-4000-8000-000000000001',5,
    'image/png',100,'BRAND','Reviewed source','Stale attempt','c25-stale')$$,
  '40001','stale catalogue asset version','stale asset versions fail safely'
);
reset role;

select is(
  (select row(canonical_name,variant_name,pack_size,list_price_paise,selling_price_paise,subcategory_id,brand_id)::text from dastak_v1.skus where id='c2540000-0000-4000-8000-000000000001'),
  (select row(canonical_name,variant_name,pack_size,list_price_paise,selling_price_paise,subcategory_id,brand_id)::text from c25_sku_before),
  'asset operations preserve SKU identity, variant, pack, pricing and taxonomy facts'
);
select is((select pg_catalog.count(*) from dastak_v1.audit_events where resource_id='c2540000-0000-4000-8000-000000000001' and action in ('CATALOGUE_ASSET_UPLOAD_PREPARED','CATALOGUE_ASSET_ADDED','CATALOGUE_PRIMARY_IMAGE_REPLACED','CATALOGUE_ASSET_REMOVED')),4::bigint,'one safe audit event is recorded per logical mutation');
select is((select pg_catalog.count(*) from dastak_v1.audit_events where resource_id='c2540000-0000-4000-8000-000000000001' and metadata::text ~ 'canonical/admin|source_reference|checksum'),0::bigint,'audit metadata contains no storage path, source reference or checksum');
select set_config('request.jwt.claim.sub','c2500000-0000-4000-8000-000000000001',true);
set local role authenticated;
select is(public.dastak_v1_admin_audit_history_page(null,null,null,'CATALOGUE_ASSET_REMOVED','catalogue_sku','c2540000-0000-4000-8000-000000000001',null,null,null,null,10,null,null) #>> '{events,0,action}','CATALOGUE_ASSET_REMOVED','asset audit appears immediately in governed Audit History');
reset role;

select * from finish();
rollback;
