#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-step4a.XXXXXX")"
run_token="$(date +%s)$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
owner_id='99400000-0000-4000-8000-000000000001'
customer_id='99400000-0000-4000-8000-000000000002'
merchant_id='99400000-0000-4000-8000-000000000003'
rider_a='99400000-0000-4000-8000-000000000004'
rider_b='99400000-0000-4000-8000-000000000005'
rider_c='99400000-0000-4000-8000-000000000006'
zone_id='99400000-0000-4000-8000-000000000010'
branch_a='99400000-0000-4000-8000-000000000020'
branch_b='99400000-0000-4000-8000-000000000021'
order_a='99400000-0000-4000-8000-000000000100'
order_b='99400000-0000-4000-8000-000000000101'
fulfilment_a1='99400000-0000-4000-8000-000000000110'
fulfilment_a2='99400000-0000-4000-8000-000000000111'
fulfilment_b='99400000-0000-4000-8000-000000000112'

"${psql_base[@]}" <<'SQL'
begin;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
('99400000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'step4-owner@example.test', '', now(), now(), now()),
('99400000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'step4-customer@example.test', '', now(), now(), now()),
('99400000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'step4-merchant@example.test', '', now(), now(), now()),
('99400000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'step4-rider-a@example.test', '', now(), now(), now()),
('99400000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'step4-rider-b@example.test', '', now(), now(), now()),
('99400000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'step4-rider-c@example.test', '', now(), now(), now())
on conflict (id) do nothing;

insert into public.accounts (id, display_name, phone_number) values
('99400000-0000-4000-8000-000000000001', 'Step Four Owner', '+919940000001'),
('99400000-0000-4000-8000-000000000002', 'Step Four Customer', '+919940000002'),
('99400000-0000-4000-8000-000000000003', 'Step Four Merchant', '+919940000003'),
('99400000-0000-4000-8000-000000000004', 'Step Four Rider A', '+919940000004'),
('99400000-0000-4000-8000-000000000005', 'Step Four Rider B', '+919940000005'),
('99400000-0000-4000-8000-000000000006', 'Step Four Rider C', '+919940000006')
on conflict (id) do nothing;

insert into private.account_memberships (account_id, role, approved_at) values
('99400000-0000-4000-8000-000000000001', 'owner', now()),
('99400000-0000-4000-8000-000000000002', 'customer', null),
('99400000-0000-4000-8000-000000000003', 'merchant', now()),
('99400000-0000-4000-8000-000000000004', 'dastak_partner', now()),
('99400000-0000-4000-8000-000000000005', 'dastak_partner', now()),
('99400000-0000-4000-8000-000000000006', 'dastak_partner', now())
on conflict (account_id, role) do update set approved_at = excluded.approved_at;

insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
)
select
  '99400000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-00000000000c',
  '99400000-0000-4000-8000-000000000001',
  'Step 4 operational safety runtime fixture'
where not exists (
  select 1 from dastak_v1.platform_permission_grants permission_grant
  where permission_grant.account_id = '99400000-0000-4000-8000-000000000001'
    and permission_grant.bundle_id = '10000000-0000-4000-8000-00000000000c'
    and permission_grant.revoked_at is null
);

insert into public.service_zones (id, name, boundary, active) values (
  '99400000-0000-4000-8000-000000000010', 'Step Four Zone',
  extensions.st_geomfromtext('POLYGON((80 15,81 15,81 16,80 16,80 15))', 4326), true
) on conflict (id) do nothing;

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  verification_version, vehicle_registration_number, vehicle_make_model,
  vehicle_evidence_object_path, status, submitted_at, reviewed_at, reviewed_by
) values
('99400000-0000-4000-8000-000000000030', '99400000-0000-4000-8000-000000000004', 'motorbike', 'dastak-partner/99400000-0000-4000-8000-000000000004/identity-a.pdf', 2, 'TN 01 AA 1001', 'Test Motorbike A', 'dastak-partner/99400000-0000-4000-8000-000000000004/vehicle-a.pdf', 'approved', now(), now(), '99400000-0000-4000-8000-000000000001'),
('99400000-0000-4000-8000-000000000031', '99400000-0000-4000-8000-000000000005', 'motorbike', 'dastak-partner/99400000-0000-4000-8000-000000000005/identity-b.pdf', 2, 'TN 01 AA 1002', 'Test Motorbike B', 'dastak-partner/99400000-0000-4000-8000-000000000005/vehicle-b.pdf', 'approved', now(), now(), '99400000-0000-4000-8000-000000000001'),
('99400000-0000-4000-8000-000000000032', '99400000-0000-4000-8000-000000000006', 'motorbike', 'dastak-partner/99400000-0000-4000-8000-000000000006/identity-c.pdf', 2, 'TN 01 AA 1003', 'Test Motorbike C', 'dastak-partner/99400000-0000-4000-8000-000000000006/vehicle-c.pdf', 'approved', now(), now(), '99400000-0000-4000-8000-000000000001')
on conflict (id) do nothing;

insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values
('99400000-0000-4000-8000-000000000004', '99400000-0000-4000-8000-000000000030', 'motorbike'),
('99400000-0000-4000-8000-000000000005', '99400000-0000-4000-8000-000000000031', 'motorbike'),
('99400000-0000-4000-8000-000000000006', '99400000-0000-4000-8000-000000000032', 'motorbike')
on conflict (account_id) do update set delivery_method = excluded.delivery_method;

insert into private.delivery_partner_availability (
  account_id, status, location, service_zone_id, last_seen_at, available_until
) values
('99400000-0000-4000-8000-000000000004', 'online', extensions.st_setsrid(extensions.st_makepoint(80.6001,15.6800),4326), '99400000-0000-4000-8000-000000000010', now(), now()+interval '2 hours'),
('99400000-0000-4000-8000-000000000005', 'online', extensions.st_setsrid(extensions.st_makepoint(80.6002,15.6800),4326), '99400000-0000-4000-8000-000000000010', now(), now()+interval '2 hours'),
('99400000-0000-4000-8000-000000000006', 'online', extensions.st_setsrid(extensions.st_makepoint(80.6400,15.6800),4326), '99400000-0000-4000-8000-000000000010', now(), now()+interval '2 hours')
on conflict (account_id) do update set status='online', location=excluded.location,
  service_zone_id=excluded.service_zone_id, last_seen_at=excluded.last_seen_at,
  available_until=excluded.available_until,
  state_version=private.delivery_partner_availability.state_version+1;

insert into dastak_v1.category_types (id,name,slug,status,created_by) values
('99400000-0000-4000-8000-000000000039','Step Four Type','step-four-type','ACTIVE','99400000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.categories (id,category_type_id,name,slug,status,created_by) values
('99400000-0000-4000-8000-000000000040','99400000-0000-4000-8000-000000000039','Step Four Category','step-four-category','ACTIVE','99400000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.subcategories (id,category_id,name,slug,status,created_by) values
('99400000-0000-4000-8000-000000000041','99400000-0000-4000-8000-000000000040','Step Four Subcategory','step-four-subcategory','ACTIVE','99400000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.skus (
  id,subcategory_id,canonical_name,slug,pack_size,list_price_paise,
  selling_price_paise,logistics_attributes,status,
  qa_status,qa_verified_at,qa_verified_by,created_by
) values
('99400000-0000-4000-8000-000000000042','99400000-0000-4000-8000-000000000041','Step Four Product A','step-four-product-a','1 unit',1000,900,'{"weightGrams":1000,"lengthMillimetres":200,"widthMillimetres":100,"heightMillimetres":100,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}','DRAFT','VERIFIED',now(),'99400000-0000-4000-8000-000000000001','99400000-0000-4000-8000-000000000001'),
('99400000-0000-4000-8000-000000000043','99400000-0000-4000-8000-000000000041','Step Four Product B','step-four-product-b','1 unit',1000,900,'{"weightGrams":1000,"lengthMillimetres":200,"widthMillimetres":100,"heightMillimetres":100,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}','DRAFT','VERIFIED',now(),'99400000-0000-4000-8000-000000000001','99400000-0000-4000-8000-000000000001')
on conflict (id) do nothing;

insert into dastak_v1.sku_images (
  id,sku_id,image_key,role,source_type,source_reference,status,
  created_by,verified_by,verified_at,rights_status,rights_reference,
  rights_verified_by,rights_verified_at
) values
('99400000-0000-4000-8000-000000000044','99400000-0000-4000-8000-000000000042','test-fixtures/step-four-product-a.webp','PRIMARY','OWNER_CAPTURE','V1 race fixture','VERIFIED','99400000-0000-4000-8000-000000000001','99400000-0000-4000-8000-000000000001',now(),'CLEARED','Test fixture rights clearance','99400000-0000-4000-8000-000000000001',now()),
('99400000-0000-4000-8000-000000000045','99400000-0000-4000-8000-000000000043','test-fixtures/step-four-product-b.webp','PRIMARY','OWNER_CAPTURE','V1 race fixture','VERIFIED','99400000-0000-4000-8000-000000000001','99400000-0000-4000-8000-000000000001',now(),'CLEARED','Test fixture rights clearance','99400000-0000-4000-8000-000000000001',now())
on conflict (id) do nothing;
update dastak_v1.skus set status='ACTIVE',updated_at=now(),version=version+1
where id in ('99400000-0000-4000-8000-000000000042','99400000-0000-4000-8000-000000000043')
  and status <> 'ACTIVE';

insert into dastak_v1.merchant_organizations (
  id,legal_name,display_name,merchant_type,status,created_by
) values ('99400000-0000-4000-8000-000000000050','Step Four Retail Private Limited','Step Four Retail','RETAIL','ACTIVE','99400000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.merchant_branches (
  id,organization_id,display_name,service_zone_id,address_snapshot,
  location,capacity_limit,status,created_by
) values
('99400000-0000-4000-8000-000000000020','99400000-0000-4000-8000-000000000050','Hidden Branch Alpha','99400000-0000-4000-8000-000000000010','{"line1":"1 Pickup Road"}',extensions.st_setsrid(extensions.st_makepoint(80.6000,15.6800),4326),5,'ACTIVE','99400000-0000-4000-8000-000000000001'),
('99400000-0000-4000-8000-000000000021','99400000-0000-4000-8000-000000000050','Hidden Branch Beta','99400000-0000-4000-8000-000000000010','{"line1":"2 Pickup Road"}',extensions.st_setsrid(extensions.st_makepoint(80.6010,15.6800),4326),5,'ACTIVE','99400000-0000-4000-8000-000000000001')
on conflict (id) do nothing;

insert into dastak_v1.platform_settings (
  id,setting_key,scope_type,setting_value,updated_by,update_reason
)
select
  '99400000-0000-4000-8000-000000000213','merchant.reachability_stale_seconds',
  'GLOBAL','300'::jsonb,'99400000-0000-4000-8000-000000000001',
  'Step 4A merchant reachability fixture.'
where not exists (
  select 1 from dastak_v1.platform_settings
  where setting_key='merchant.reachability_stale_seconds'
    and scope_type='GLOBAL' and scope_id is null
);
insert into dastak_v1.branch_operational_states (
  branch_id,is_open,accepting_orders,updated_by
) values
('99400000-0000-4000-8000-000000000020',true,true,'99400000-0000-4000-8000-000000000003'),
('99400000-0000-4000-8000-000000000021',true,true,'99400000-0000-4000-8000-000000000003')
on conflict (branch_id) do update
set is_open=true,accepting_orders=true,updated_by=excluded.updated_by,
    version=dastak_v1.branch_operational_states.version+1;

insert into dastak_v1.orders (
  id,display_order_number,customer_id,order_type,status,submitted_at,paid_at,version
) values
('99400000-0000-4000-8000-000000000100','DV1-STEP4-A','99400000-0000-4000-8000-000000000002','RETAIL_ONLY','PREPARING',now()-interval '20 minutes',now()-interval '10 minutes',1),
('99400000-0000-4000-8000-000000000101','DV1-STEP4-B','99400000-0000-4000-8000-000000000002','RETAIL_ONLY','PREPARING',now()-interval '20 minutes',now()-interval '10 minutes',1)
on conflict (id) do nothing;
insert into dastak_v1.order_context_snapshots (order_id,delivery_address,recipient,snapshot_hash) values
('99400000-0000-4000-8000-000000000100','{"line1":"10 Customer Road","countryCode":"IN","latitude":15.69,"longitude":80.61}','{"name":"Step Customer","phoneNumber":"+919940000002"}',decode(repeat('01',32),'hex')),
('99400000-0000-4000-8000-000000000101','{"line1":"10 Customer Road","countryCode":"IN","latitude":15.69,"longitude":80.61}','{"name":"Step Customer","phoneNumber":"+919940000002"}',decode(repeat('02',32),'hex'))
on conflict (order_id) do nothing;
insert into dastak_v1.order_lines (
  id,order_id,line_type,sku_id,product_name_snapshot,pack_size_snapshot,
  quantity,unit_price_paise,status
) values
('99400000-0000-4000-8000-000000000120','99400000-0000-4000-8000-000000000100','RETAIL_SKU','99400000-0000-4000-8000-000000000042','Step Four Product A','1 unit',1,900,'FULFILLING'),
('99400000-0000-4000-8000-000000000121','99400000-0000-4000-8000-000000000100','RETAIL_SKU','99400000-0000-4000-8000-000000000043','Step Four Product B','1 unit',1,900,'FULFILLING'),
('99400000-0000-4000-8000-000000000122','99400000-0000-4000-8000-000000000101','RETAIL_SKU','99400000-0000-4000-8000-000000000042','Step Four Product A','1 unit',1,900,'FULFILLING')
on conflict (id) do nothing;

insert into dastak_v1.matching_attempts (
  id,order_id,wave,status,started_at,expires_at,closed_at
) values
('99400000-0000-4000-8000-000000000130','99400000-0000-4000-8000-000000000100','WAVE_1','EXPIRED',now()-interval '20 minutes',now()-interval '17 minutes',now()-interval '17 minutes'),
('99400000-0000-4000-8000-000000000132','99400000-0000-4000-8000-000000000100','WAVE_2','EXPIRED',now()-interval '17 minutes',now()-interval '14 minutes',now()-interval '14 minutes'),
('99400000-0000-4000-8000-000000000131','99400000-0000-4000-8000-000000000101','WAVE_1','EXPIRED',now()-interval '20 minutes',now()-interval '17 minutes',now()-interval '17 minutes')
on conflict (id) do nothing;
insert into dastak_v1.merchant_opportunities (
  id,matching_attempt_id,order_id,organization_id,branch_id,wave,status,started_at,expires_at
) values
('99400000-0000-4000-8000-000000000140','99400000-0000-4000-8000-000000000130','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000020','WAVE_1','LOST',now()-interval '20 minutes',now()-interval '17 minutes'),
('99400000-0000-4000-8000-000000000141','99400000-0000-4000-8000-000000000132','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000021','WAVE_2','LOST',now()-interval '17 minutes',now()-interval '14 minutes'),
('99400000-0000-4000-8000-000000000142','99400000-0000-4000-8000-000000000131','99400000-0000-4000-8000-000000000101','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000020','WAVE_1','LOST',now()-interval '20 minutes',now()-interval '17 minutes')
on conflict (id) do nothing;

insert into dastak_v1.fulfilments (
  id,order_id,organization_id,branch_id,source_opportunity_id,
  fulfilment_type,status,promised_prep_minutes,committed_at,prep_started_at,
  estimated_ready_at,ready_at,actual_ready_at,package_count
) values
('99400000-0000-4000-8000-000000000110','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000020','99400000-0000-4000-8000-000000000140','RETAIL','READY',10,now()-interval '15 minutes',now()-interval '10 minutes',now(),now()-interval '1 minute',now()-interval '1 minute',2),
('99400000-0000-4000-8000-000000000111','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000021','99400000-0000-4000-8000-000000000141','RETAIL','READY',10,now()-interval '15 minutes',now()-interval '10 minutes',now(),now()-interval '1 minute',now()-interval '1 minute',1),
('99400000-0000-4000-8000-000000000112','99400000-0000-4000-8000-000000000101','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000020','99400000-0000-4000-8000-000000000142','RETAIL','PREPARING',10,now()-interval '15 minutes',now()-interval '10 minutes',now(),null,null,1)
on conflict (id) do nothing;
insert into dastak_v1.fulfilment_lines (fulfilment_id,order_line_id,confirmed_quantity) values
('99400000-0000-4000-8000-000000000110','99400000-0000-4000-8000-000000000120',1),
('99400000-0000-4000-8000-000000000111','99400000-0000-4000-8000-000000000121',1),
('99400000-0000-4000-8000-000000000112','99400000-0000-4000-8000-000000000122',1)
on conflict do nothing;
insert into dastak_v1.settlement_entries (
  entry_key,subject_type,subject_id,order_id,fulfilment_id,order_line_id,
  entry_type,status,calculation_status,gross_amount_paise,amount_paise,
  calculation_snapshot
) values
('STEP4A:MERCHANT:A1','MERCHANT_ORGANIZATION','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000110','99400000-0000-4000-8000-000000000120','EARNING','PENDING','CALCULATED',900,900,'{"commissionBps":0,"configurationRequired":false}'),
('STEP4A:MERCHANT:A2','MERCHANT_ORGANIZATION','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000111','99400000-0000-4000-8000-000000000121','EARNING','PENDING','CALCULATED',900,900,'{"commissionBps":0,"configurationRequired":false}'),
('STEP4A:MERCHANT:B','MERCHANT_ORGANIZATION','99400000-0000-4000-8000-000000000050','99400000-0000-4000-8000-000000000101','99400000-0000-4000-8000-000000000112','99400000-0000-4000-8000-000000000122','EARNING','PENDING','CALCULATED',900,900,'{"commissionBps":0,"configurationRequired":false}')
on conflict(entry_key) do nothing;
insert into dastak_v1.packages (
  id,order_id,fulfilment_id,package_number,status,
  current_custody_owner_type,current_custody_owner_id,declared_by,
  declared_at,ready_at
) values
('99400000-0000-4000-8000-000000000150','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000110',1,'READY','MERCHANT_BRANCH','99400000-0000-4000-8000-000000000020','99400000-0000-4000-8000-000000000003',now()-interval '2 minutes',now()-interval '1 minute'),
('99400000-0000-4000-8000-000000000151','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000110',2,'READY','MERCHANT_BRANCH','99400000-0000-4000-8000-000000000020','99400000-0000-4000-8000-000000000003',now()-interval '2 minutes',now()-interval '1 minute'),
('99400000-0000-4000-8000-000000000152','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000111',1,'READY','MERCHANT_BRANCH','99400000-0000-4000-8000-000000000021','99400000-0000-4000-8000-000000000003',now()-interval '2 minutes',now()-interval '1 minute'),
('99400000-0000-4000-8000-000000000153','99400000-0000-4000-8000-000000000101','99400000-0000-4000-8000-000000000112',1,'DECLARED','MERCHANT_BRANCH','99400000-0000-4000-8000-000000000020','99400000-0000-4000-8000-000000000003',now()-interval '2 minutes',null)
on conflict (id) do nothing;
insert into dastak_v1.fulfilment_evidence (
  id,order_id,fulfilment_id,evidence_type,object_path,content_type,
  content_length_bytes,captured_by,captured_at
) values
('99400000-0000-4000-8000-000000000154','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000110','MERCHANT_READY_PHOTO','test/step4a/ready-a1.jpg','image/jpeg',1024,'99400000-0000-4000-8000-000000000003',now()-interval '1 minute'),
('99400000-0000-4000-8000-000000000155','99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000111','MERCHANT_READY_PHOTO','test/step4a/ready-a2.jpg','image/jpeg',1024,'99400000-0000-4000-8000-000000000003',now()-interval '1 minute')
on conflict (id) do nothing;
commit;
SQL

configure_setting() {
  local key="$1" value="$2" id="$3"
  "${psql_base[@]}" -v key="$key" -v value="$value" -v id="$id" -v owner="$owner_id" <<'SQL' >/dev/null
update dastak_v1.platform_settings
set setting_value = :'value'::jsonb, updated_by = :'owner'::uuid,
    update_reason = 'Step 4A runtime configuration.', version = version + 1
where setting_key = :'key' and scope_type = 'GLOBAL' and scope_id is null;
insert into dastak_v1.platform_settings (
  id,setting_key,scope_type,setting_value,updated_by,update_reason
)
select :'id'::uuid, :'key', 'GLOBAL', :'value'::jsonb, :'owner'::uuid,
  'Step 4A runtime configuration.'
where not exists (
  select 1 from dastak_v1.platform_settings
  where setting_key = :'key' and scope_type = 'GLOBAL' and scope_id is null
);
SQL
}

configure_setting 'matching.wave2_timeout_seconds' '120' '99400000-0000-4000-8000-000000000200'
configure_setting 'matching.wave2_hold_seconds' '180' '99400000-0000-4000-8000-000000000201'
configure_setting 'payment.reservation_seconds' '300' '99400000-0000-4000-8000-000000000202'
configure_setting 'matching.wave2_max_pickup_route_meters' '50000' '99400000-0000-4000-8000-000000000203'
configure_setting 'delivery.default_sku_logistics' '{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}' '99400000-0000-4000-8000-000000000204'
configure_setting 'delivery.transport_load_profiles' '[{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]' '99400000-0000-4000-8000-000000000205'
configure_setting 'delivery.rider_initial_pool_size' '2' '99400000-0000-4000-8000-000000000206'
configure_setting 'delivery.rider_offer_timeout_seconds' '30' '99400000-0000-4000-8000-000000000207'
configure_setting 'delivery.rider_pool_expansion' '{"initialRadiusMeters":1000,"radiusStepMeters":5000,"additionalRidersPerRound":2,"maximumRounds":4}' '99400000-0000-4000-8000-000000000208'
configure_setting 'delivery.verification_invalid_attempt_limit' '3' '99400000-0000-4000-8000-000000000209'
configure_setting 'settlement.rider_distance_payout' '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}' '99400000-0000-4000-8000-000000000210'
configure_setting 'delivery.rider_stall_threshold_seconds' '60' '99400000-0000-4000-8000-000000000211'
configure_setting 'delivery.rider_unresponsive_threshold_seconds' '120' '99400000-0000-4000-8000-000000000212'

mission_a="$("${psql_base[@]}" -Atc "select dastak_v1_api.ensure_delivery_mission('$order_a'::uuid)" | tail -n 1)"
mission_b="$("${psql_base[@]}" -Atc "select dastak_v1_api.ensure_delivery_mission('$order_b'::uuid)" | tail -n 1)"
[[ -n "$mission_a" && -n "$mission_b" ]] || { printf 'missions were not created\n' >&2; exit 1; }

offer_a_a="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_a'::uuid and rider_id='$rider_a'::uuid")"
offer_a_b="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_a'::uuid and rider_id='$rider_b'::uuid")"
offer_b_a="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_b'::uuid and rider_id='$rider_a'::uuid")"
[[ -n "$offer_a_a" && -n "$offer_a_b" && -n "$offer_b_a" ]] || { printf 'initial nearby pools were not created\n' >&2; exit 1; }

# Current transport is revalidated at acceptance, not trusted from the offer.
"${psql_base[@]}" -c "update private.delivery_partner_profiles set delivery_method='scooter' where account_id='$rider_a'::uuid" >/dev/null
incapable="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->'error'->>'code' from public.dastak_v1_accept_delivery_offer('$rider_a'::uuid,'$offer_a_a'::uuid,'incapable-$run_token','incapable')")"
[[ "$incapable" == "409|transport_incapable" ]] || { printf 'incapable transport was not rejected: %s\n' "$incapable" >&2; exit 1; }
"${psql_base[@]}" -c "update private.delivery_partner_profiles set delivery_method='motorbike' where account_id='$rider_a'::uuid" >/dev/null

"${psql_base[@]}" -At -c "select response_status from public.dastak_v1_accept_delivery_offer('$rider_a'::uuid,'$offer_a_a'::uuid,'race-a-$run_token','race-a')" >"$work_dir/accept-a.out" &
pid_a=$!
"${psql_base[@]}" -At -c "select response_status from public.dastak_v1_accept_delivery_offer('$rider_b'::uuid,'$offer_a_b'::uuid,'race-b-$run_token','race-b')" >"$work_dir/accept-b.out" &
pid_b=$!
wait "$pid_a"; wait "$pid_b"

winner="$("${psql_base[@]}" -Atc "select assigned_rider_id from dastak_v1.delivery_missions where id='$mission_a'::uuid")"
accepted_count="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.delivery_offers where mission_id='$mission_a'::uuid and status='ACCEPTED'")"
[[ "$accepted_count" == "1" && ( "$winner" == "$rider_a" || "$winner" == "$rider_b" ) ]] || { printf 'simultaneous accepts did not produce one winner\n' >&2; exit 1; }

if "${psql_base[@]}" -c "insert into dastak_v1.delivery_missions(order_id,status,transport_snapshot,pickup_count) select order_id,'SEARCHING_RIDER',transport_snapshot,pickup_count from dastak_v1.delivery_missions where id='$mission_a'::uuid" >"$work_dir/duplicate-mission.out" 2>&1; then
  printf 'same order accepted two active missions\n' >&2; exit 1
fi
grep -Eiq 'delivery_missions_one_active_order_uidx|duplicate key' "$work_dir/duplicate-mission.out"

cancelled="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->>'reassignmentStarted' from public.dastak_v1_advance_delivery_mission('$winner'::uuid,'$mission_a'::uuid,'CANCEL_BEFORE_PICKUP',null,null,null,'Rider unavailable before pickup','cancel-$run_token','cancel')")"
[[ "$cancelled" == "200|true" ]] || { printf 'pre-pickup reassignment failed: %s\n' "$cancelled" >&2; exit 1; }
offer_a_c="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_a'::uuid and rider_id='$rider_c'::uuid and status='OFFERED'")"
[[ -n "$offer_a_c" ]] || { printf 'configured expanded rider pool was not created\n' >&2; exit 1; }
"${psql_base[@]}" -c "select * from public.dastak_v1_accept_delivery_offer('$rider_c'::uuid,'$offer_a_c'::uuid,'accept-c-$run_token','accept-c')" >/dev/null

# A rider already holding one active customer mission cannot accept another.
"${psql_base[@]}" -c "insert into dastak_v1.delivery_offers(mission_id,order_id,rider_id,transport_type,pool_round,status,distance_meters,offered_at,respond_by) values('$mission_b'::uuid,'$order_b'::uuid,'$rider_c'::uuid,'MOTORBIKE',1,'OFFERED',100,now(),now()+interval '2 minutes')" >/dev/null
offer_b_c="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_b'::uuid and rider_id='$rider_c'::uuid")"
second_mission="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->'error'->>'code' from public.dastak_v1_accept_delivery_offer('$rider_c'::uuid,'$offer_b_c'::uuid,'second-$run_token','second')")"
[[ "$second_mission" == "409|rider_has_active_mission" ]] || { printf 'one-order-per-rider failed: %s\n' "$second_mission" >&2; exit 1; }

# The second order is late but remains assignable; assignment never auto-releases it.
"${psql_base[@]}" -c "select * from public.dastak_v1_accept_delivery_offer('$rider_a'::uuid,'$offer_b_a'::uuid,'late-accept-$run_token','late-accept')" >/dev/null
late_truth="$("${psql_base[@]}" -At -F ' ' -c "select (assigned_rider_id='$rider_a'::uuid)::int,(status='ASSIGNED')::int from dastak_v1.delivery_missions where id='$mission_b'::uuid")"
[[ "$late_truth" == "1 1" ]] || { printf 'late fulfilment removed assigned rider\n' >&2; exit 1; }
"${psql_base[@]}" -c "select * from public.dastak_v1_advance_delivery_mission('$rider_a'::uuid,'$mission_b'::uuid,'START_PICKUPS',null,null,null,null,'late-start-$run_token','late-start')" >/dev/null
stop_b="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_stops where mission_id='$mission_b'::uuid")"
not_ready="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->'error'->>'code' from public.dastak_v1_advance_delivery_mission('$rider_a'::uuid,'$mission_b'::uuid,'VERIFY_PICKUP','$stop_b'::uuid,1,'000000',null,'not-ready-$run_token','not-ready')")"
[[ "$not_ready" == "409|fulfilment_not_ready" ]] || { printf 'pickup before Ready was not rejected: %s\n' "$not_ready" >&2; exit 1; }

# Missing transport configuration is a system/configuration error.
if "${psql_base[@]}" >"$work_dir/config-error.out" 2>&1 <<SQL
begin;
alter table dastak_v1.platform_settings disable trigger platform_settings_guard;
delete from dastak_v1.platform_settings where setting_key='delivery.transport_load_profiles';
select dastak_v1_api.rider_matching_configuration();
rollback;
SQL
then
  printf 'missing transport configuration did not fail\n' >&2; exit 1
fi
grep -q 'SYSTEM_CONFIGURATION_ERROR' "$work_dir/config-error.out"

# Legacy order-level settlement eligibility cannot bypass verified pickup.
premature_royalty="$("${psql_base[@]}" -At -F '|' -c "
select dastak_v1_api.mark_order_settlements_eligible(
    '$order_a'::uuid,null,'Premature eligibility probe.',true
  ),
  dastak_v1_api.royalty_earning_milestone_proven(entry.id),
  entry.status,
  (select count(*) from dastak_v1.financial_journal_transactions transaction
    where transaction.settlement_entry_id=entry.id)
from dastak_v1.settlement_entries entry
where entry.fulfilment_id='$fulfilment_a1'::uuid and entry.entry_type='EARNING'")"
[[ "$premature_royalty" == "0|f|PENDING|0" ]] || {
  printf 'merchant Royalty became eligible before verified pickup: %s\n' "$premature_royalty" >&2; exit 1;
}

"${psql_base[@]}" -c "select * from public.dastak_v1_advance_delivery_mission('$rider_c'::uuid,'$mission_a'::uuid,'START_PICKUPS',null,null,null,null,'start-a-$run_token','start-a')" >/dev/null
stop_a="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_stops where mission_id='$mission_a'::uuid and fulfilment_id='$fulfilment_a1'::uuid")"
code_a="$("${psql_base[@]}" -Atc "select private.dastak_v1_handoff_code(id,handoff_type,code_version) from dastak_v1.verification_handoffs where mission_id='$mission_a'::uuid and fulfilment_id='$fulfilment_a1'::uuid")"
[[ "$code_a" =~ ^[0-9]{6}$ ]] || { printf 'pickup code was unavailable after Ready\n' >&2; exit 1; }

wrong_rider="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->'error'->>'code' from public.dastak_v1_advance_delivery_mission('$rider_b'::uuid,'$mission_a'::uuid,'VERIFY_PICKUP','$stop_a'::uuid,2,'$code_a',null,'wrong-rider-$run_token','wrong-rider')")"
[[ "$wrong_rider" == "404|mission_not_found" ]] || { printf 'wrong rider with valid code was not rejected: %s\n' "$wrong_rider" >&2; exit 1; }

mismatch="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->'error'->>'code' from public.dastak_v1_advance_delivery_mission('$rider_c'::uuid,'$mission_a'::uuid,'VERIFY_PICKUP','$stop_a'::uuid,1,'$code_a',null,'mismatch-$run_token','mismatch')")"
[[ "$mismatch" == "409|package_count_mismatch" ]] || { printf 'package mismatch was not rejected: %s\n' "$mismatch" >&2; exit 1; }

if "${psql_base[@]}" -c "update dastak_v1.packages set status='PICKED_UP',picked_up_at=now(),current_custody_owner_type='RIDER',current_custody_owner_id='$rider_c'::uuid,version=version+1 where id='99400000-0000-4000-8000-000000000150'::uuid" >"$work_dir/partial.out" 2>&1; then
  printf 'partial direct pickup unexpectedly succeeded\n' >&2; exit 1
fi
grep -q 'consumed verification' "$work_dir/partial.out"

pickup_sql="select response_status from public.dastak_v1_advance_delivery_mission('$rider_c'::uuid,'$mission_a'::uuid,'VERIFY_PICKUP','$stop_a'::uuid,2,'$code_a',null,'pickup-once-$run_token','pickup-once')"
"${psql_base[@]}" -At -c "$pickup_sql" >"$work_dir/pickup-a.out" & pickup_a_pid=$!
"${psql_base[@]}" -At -c "$pickup_sql" >"$work_dir/pickup-b.out" & pickup_b_pid=$!
wait "$pickup_a_pid"; wait "$pickup_b_pid"
pickup_truth="$("${psql_base[@]}" -At -F ' ' -c "select (select count(*) from dastak_v1.packages where fulfilment_id='$fulfilment_a1'::uuid and status='PICKED_UP' and current_custody_owner_type='RIDER' and current_custody_owner_id='$rider_c'::uuid),(select count(*) from dastak_v1.package_custody_events where fulfilment_id='$fulfilment_a1'::uuid),(select count(*) from dastak_v1.verification_handoffs where fulfilment_id='$fulfilment_a1'::uuid and status='CONSUMED'),(select count(*) from dastak_v1.fulfilments where id='$fulfilment_a1'::uuid and status='PICKED_UP'),(select count(*) from dastak_v1.delivery_stops where id='$stop_a'::uuid and status='COMPLETED'),(select count(*) from dastak_v1.settlement_entries where fulfilment_id='$fulfilment_a1'::uuid and status='ELIGIBLE'),(select count(*) from dastak_v1.financial_journal_transactions where fulfilment_id='$fulfilment_a1'::uuid and transaction_type='MERCHANT_ROYALTY_EARNING')")"
[[ "$pickup_truth" == "2 2 1 1 1 1 1" ]] || { printf 'atomic pickup/Royalty truth failed: %s\n' "$pickup_truth" >&2; exit 1; }

replay="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->'error'->>'code' from public.dastak_v1_advance_delivery_mission('$rider_c'::uuid,'$mission_a'::uuid,'VERIFY_PICKUP','$stop_a'::uuid,2,'$code_a',null,'replay-$run_token','replay')")"
[[ "$replay" == "409|invalid_pickup_state" || "$replay" == "409|pickup_code_consumed" ]] || { printf 'consumed pickup replay was unsafe: %s\n' "$replay" >&2; exit 1; }
post_replay="$("${psql_base[@]}" -At -F ' ' -c "select count(*),(select count(*) from dastak_v1.package_custody_events where fulfilment_id='$fulfilment_a1'::uuid),(select count(*) from dastak_v1.financial_journal_transactions where fulfilment_id='$fulfilment_a1'::uuid and transaction_type='MERCHANT_ROYALTY_EARNING') from dastak_v1.packages where fulfilment_id='$fulfilment_a1'::uuid and status='PICKED_UP'")"
[[ "$post_replay" == "2 2 1" ]] || { printf 'replay transferred custody or credited Merchant Royalty twice\n' >&2; exit 1; }

after_custody_cancel="$("${psql_base[@]}" -At -F '|' -c "select response_status,response_body->'error'->>'code' from public.dastak_v1_advance_delivery_mission('$rider_c'::uuid,'$mission_a'::uuid,'CANCEL_BEFORE_PICKUP',null,null,null,'Cannot continue after pickup','after-custody-$run_token','after-custody')")"
[[ "$after_custody_cancel" == "409|delivery_recovery_required" ]] || { printf 'post-custody cancellation was not rejected: %s\n' "$after_custody_cancel" >&2; exit 1; }

customer_projection="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_json('$order_a'::uuid,'$customer_id'::uuid)::text")"
[[ "$customer_projection" != *'Hidden Branch'* && "$customer_projection" != *"$branch_a"* && "$customer_projection" != *"$branch_b"* ]] || { printf 'customer projection leaked retail merchant identity\n' >&2; exit 1; }
[[ "$customer_projection" == *'PICKING_UP'* ]] || { printf 'customer pickup state was not projected\n' >&2; exit 1; }

# Final package declaration is a second authoritative transport gate. Race a
# Motorbike acceptance against a five-package final declaration: regardless of
# lock order, an incapable assignment may not survive and no custody may move.
order_c='99400000-0000-4000-8000-000000000102'
fulfilment_c='99400000-0000-4000-8000-000000000113'
"${psql_base[@]}" <<'SQL'
begin;
insert into dastak_v1.orders (
  id,display_order_number,customer_id,order_type,status,submitted_at,paid_at,version
) values (
  '99400000-0000-4000-8000-000000000102','DV1-STEP4-C',
  '99400000-0000-4000-8000-000000000002','RETAIL_ONLY','PREPARING',
  now()-interval '20 minutes',now()-interval '10 minutes',1
);
insert into dastak_v1.order_context_snapshots (
  order_id,delivery_address,recipient,snapshot_hash
) values (
  '99400000-0000-4000-8000-000000000102',
  '{"line1":"10 Customer Road","countryCode":"IN","latitude":15.69,"longitude":80.61}',
  '{"name":"Step Customer","phoneNumber":"+919940000002"}',
  decode(repeat('03',32),'hex')
);
insert into dastak_v1.order_lines (
  id,order_id,line_type,sku_id,product_name_snapshot,pack_size_snapshot,
  quantity,unit_price_paise,status
) values (
  '99400000-0000-4000-8000-000000000123',
  '99400000-0000-4000-8000-000000000102','RETAIL_SKU',
  '99400000-0000-4000-8000-000000000042','Step Four Product A','1 unit',
  1,900,'FULFILLING'
);
insert into dastak_v1.matching_attempts (
  id,order_id,wave,status,started_at,expires_at,closed_at
) values (
  '99400000-0000-4000-8000-000000000133',
  '99400000-0000-4000-8000-000000000102','WAVE_1','EXPIRED',
  now()-interval '20 minutes',now()-interval '17 minutes',now()-interval '17 minutes'
);
insert into dastak_v1.merchant_opportunities (
  id,matching_attempt_id,order_id,organization_id,branch_id,wave,status,
  started_at,expires_at
) values (
  '99400000-0000-4000-8000-000000000143',
  '99400000-0000-4000-8000-000000000133',
  '99400000-0000-4000-8000-000000000102',
  '99400000-0000-4000-8000-000000000050',
  '99400000-0000-4000-8000-000000000020','WAVE_1','LOST',
  now()-interval '20 minutes',now()-interval '17 minutes'
);
insert into dastak_v1.fulfilments (
  id,order_id,organization_id,branch_id,source_opportunity_id,
  fulfilment_type,status,promised_prep_minutes,committed_at,prep_started_at,
  estimated_ready_at,package_count
) values (
  '99400000-0000-4000-8000-000000000113',
  '99400000-0000-4000-8000-000000000102',
  '99400000-0000-4000-8000-000000000050',
  '99400000-0000-4000-8000-000000000020',
  '99400000-0000-4000-8000-000000000143','RETAIL','PREPARING',10,
  now()-interval '15 minutes',now()-interval '10 minutes',now(),null
);
insert into dastak_v1.fulfilment_lines (
  fulfilment_id,order_line_id,confirmed_quantity
) values (
  '99400000-0000-4000-8000-000000000113',
  '99400000-0000-4000-8000-000000000123',1
);
commit;
SQL

mission_c="$("${psql_base[@]}" -Atc "select dastak_v1_api.ensure_delivery_mission('$order_c'::uuid)" | tail -n 1)"
offer_c_b="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_c'::uuid and rider_id='$rider_b'::uuid and status='OFFERED'")"
[[ -n "$mission_c" && -n "$offer_c_b" ]] || { printf 'pre-offer transport classification did not create the expected mission/offer\n' >&2; exit 1; }
preoffer_final="$("${psql_base[@]}" -Atc "select transport_snapshot->>'packageCountFinal' from dastak_v1.delivery_missions where id='$mission_c'::uuid")"
[[ "$preoffer_final" == "false" ]] || { printf 'pre-offer package count was incorrectly final\n' >&2; exit 1; }

("${psql_base[@]}" -At -c "select response_status from public.dastak_v1_accept_delivery_offer('$rider_b'::uuid,'$offer_c_b'::uuid,'final-load-accept-$run_token','final-load-accept')" >"$work_dir/final-load-accept.out" 2>&1 || true) &
final_accept_pid=$!
("${psql_base[@]}" >"$work_dir/final-load-declare.out" 2>&1 <<SQL
begin;
insert into dastak_v1.packages (
  id,order_id,fulfilment_id,package_number,status,
  current_custody_owner_type,current_custody_owner_id,declared_by,declared_at
)
select
  ('99400000-0000-4000-8000-' || pg_catalog.lpad((160 + number)::text,12,'0'))::uuid,
  '$order_c'::uuid,'$fulfilment_c'::uuid,number,'DECLARED',
  'MERCHANT_BRANCH','$branch_a'::uuid,'$merchant_id'::uuid,now()
from pg_catalog.generate_series(1,5) number;
update dastak_v1.fulfilments
set package_count=5,version=version+1 where id='$fulfilment_c'::uuid;
commit;
SQL
) &
final_declare_pid=$!
wait "$final_accept_pid"; wait "$final_declare_pid"
final_load_truth="$("${psql_base[@]}" -At -F ' ' -c "select (transport_snapshot->>'packageCountFinal')::boolean,(transport_snapshot->>'packageCount')::int,assigned_rider_id is null,status in ('SEARCHING_RIDER','REASSIGNING'),not dastak_v1_api.mission_has_package_custody(id) from dastak_v1.delivery_missions where id='$mission_c'::uuid")"
[[ "$final_load_truth" == "t 5 t t t" ]] || { printf 'final package transport race left an unsafe mission: %s\n' "$final_load_truth" >&2; exit 1; }

# Scoped emergency controls block only new commitments. Existing paid work and
# custody truth stay unchanged.
pause_retail="$("${psql_base[@]}" -Atc "select dastak_v1_api.set_operational_pause('$owner_id'::uuid,'ZONE_RETAIL','$zone_id'::uuid,true,'Runtime retail emergency pause',0,'pause-retail-$run_token')->>'version' from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
[[ "$pause_retail" == "1" ]] || { printf 'retail zone pause was not created\n' >&2; exit 1; }
if "${psql_base[@]}" >"$work_dir/paused-order.out" 2>&1 <<SQL
begin;
insert into dastak_v1.orders (
  id,display_order_number,customer_id,order_type,status
) values (
  '99400000-0000-4000-8000-000000000180','DV1-PAUSED-RETAIL',
  '$customer_id'::uuid,'RETAIL_ONLY','CREATED'
);
insert into dastak_v1.order_context_snapshots (
  order_id,delivery_address,recipient,snapshot_hash
) values (
  '99400000-0000-4000-8000-000000000180',
  '{"latitude":15.69,"longitude":80.61}', '{}',decode(repeat('18',32),'hex')
);
commit;
SQL
then
  printf 'paused retail zone accepted a new order\n' >&2; exit 1
fi
grep -q 'ORDERING_PAUSED' "$work_dir/paused-order.out"
"${psql_base[@]}" -c "select dastak_v1_api.set_operational_pause('$owner_id'::uuid,'ZONE_RETAIL','$zone_id'::uuid,false,'Retail ordering restored',1,'resume-retail-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >/dev/null

"${psql_base[@]}" -c "select dastak_v1_api.set_operational_pause('$owner_id'::uuid,'MERCHANT_BRANCH','$branch_a'::uuid,true,'Branch intake paused safely',0,'pause-branch-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >/dev/null
"${psql_base[@]}" <<SQL >/dev/null
insert into dastak_v1.matching_attempts (
  id,order_id,wave,status,started_at,expires_at
) values (
  '99400000-0000-4000-8000-000000000134','$order_c'::uuid,
  'WAVE_2','OPEN',now(),now()+interval '3 minutes'
);
insert into dastak_v1.merchant_opportunities (
  id,matching_attempt_id,order_id,organization_id,branch_id,wave,status,
  started_at,expires_at
) values (
  '99400000-0000-4000-8000-000000000144',
  '99400000-0000-4000-8000-000000000134','$order_c'::uuid,
  '99400000-0000-4000-8000-000000000050','$branch_a'::uuid,
  'WAVE_2','OFFERED',now(),now()+interval '3 minutes'
);
SQL
paused_branch_count="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.merchant_opportunities where id='99400000-0000-4000-8000-000000000144'::uuid")"
[[ "$paused_branch_count" == "0" ]] || { printf 'paused branch received a new opportunity\n' >&2; exit 1; }
"${psql_base[@]}" -c "select dastak_v1_api.set_operational_pause('$owner_id'::uuid,'MERCHANT_BRANCH','$branch_a'::uuid,false,'Branch intake restored',1,'resume-branch-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >/dev/null

# Stall can clear on authenticated heartbeat; unresponsive pre-custody work can
# be released exactly once by Operations, with paused riders excluded from the
# rematch pool.
"${psql_base[@]}" -c "update dastak_v1.delivery_missions set rider_last_progress_at=now()-interval '61 seconds',rider_last_contact_at=now(),version=version+1 where id='$mission_b'::uuid" >/dev/null
"${psql_base[@]}" -c "select dastak_v1_api.process_rider_escalations(100,now())" >/dev/null
stalled="$("${psql_base[@]}" -Atc "select escalation_state from dastak_v1.delivery_missions where id='$mission_b'::uuid")"
[[ "$stalled" == "STALLED" ]] || { printf 'rider stall was not detected: %s\n' "$stalled" >&2; exit 1; }
mission_b_version="$("${psql_base[@]}" -Atc "select version from dastak_v1.delivery_missions where id='$mission_b'::uuid")"
heartbeat_state="$("${psql_base[@]}" -Atc "select dastak_v1_api.rider_heartbeat('$rider_a'::uuid,'$mission_b'::uuid,$mission_b_version)->>'escalationState' from (select set_config('request.jwt.claim.sub','$rider_a',false)) actor")"
[[ "$heartbeat_state" == "NONE" ]] || { printf 'rider heartbeat did not clear a stall\n' >&2; exit 1; }
"${psql_base[@]}" -c "update dastak_v1.delivery_missions set rider_last_progress_at=now()-interval '121 seconds',rider_last_contact_at=now()-interval '121 seconds',version=version+1 where id='$mission_b'::uuid" >/dev/null
"${psql_base[@]}" -c "select dastak_v1_api.process_rider_escalations(100,now())" >/dev/null
unresponsive="$("${psql_base[@]}" -Atc "select escalation_state from dastak_v1.delivery_missions where id='$mission_b'::uuid")"
[[ "$unresponsive" == "UNRESPONSIVE" ]] || { printf 'rider unresponsive state was not detected: %s\n' "$unresponsive" >&2; exit 1; }

"${psql_base[@]}" -c "select dastak_v1_api.set_operational_pause('$owner_id'::uuid,'RIDER_ASSIGNMENTS','$rider_b'::uuid,true,'Rider assignments paused safely',0,'pause-rider-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >/dev/null
mission_b_version="$("${psql_base[@]}" -Atc "select version from dastak_v1.delivery_missions where id='$mission_b'::uuid")"
release_sql="select dastak_v1_api.manage_rider_escalation('$owner_id'::uuid,'$mission_b'::uuid,'RELEASE_REMATCH','Authorized pre-custody unresponsive release',$mission_b_version"
("${psql_base[@]}" -At -c "$release_sql,'release-a-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >"$work_dir/release-a.out" 2>&1 || true) & release_a_pid=$!
("${psql_base[@]}" -At -c "$release_sql,'release-b-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >"$work_dir/release-b.out" 2>&1 || true) & release_b_pid=$!
wait "$release_a_pid"; wait "$release_b_pid"
release_truth="$("${psql_base[@]}" -At -F ' ' -c "select status='SEARCHING_RIDER',assigned_rider_id is null,escalation_state='RELEASED_PRE_CUSTODY',(select count(*)=0 from dastak_v1.delivery_offers where mission_id='$mission_b'::uuid and rider_id='$rider_b'::uuid and status='OFFERED') from dastak_v1.delivery_missions where id='$mission_b'::uuid")"
[[ "$release_truth" == "t t t t" ]] || { printf 'pre-custody release/rematch was unsafe: %s\n' "$release_truth" >&2; exit 1; }
release_a_success="$(grep -c 'missionId' "$work_dir/release-a.out" || true)"
release_b_success="$(grep -c 'missionId' "$work_dir/release-b.out" || true)"
[[ $((release_a_success + release_b_success)) -eq 1 ]] || { printf 'concurrent Operations release did not commit exactly once\n' >&2; exit 1; }
"${psql_base[@]}" -c "select dastak_v1_api.set_operational_pause('$owner_id'::uuid,'RIDER_ASSIGNMENTS','$rider_b'::uuid,false,'Rider assignments restored',1,'resume-rider-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >/dev/null

# An unresponsive rider after custody enters Delivery Recovery and is never
# automatically reassigned.
"${psql_base[@]}" -c "update dastak_v1.delivery_missions set rider_last_progress_at=now()-interval '121 seconds',rider_last_contact_at=now()-interval '121 seconds',version=version+1 where id='$mission_a'::uuid" >/dev/null
"${psql_base[@]}" -c "select dastak_v1_api.process_rider_escalations(100,now())" >/dev/null
recovery_truth="$("${psql_base[@]}" -At -F ' ' -c "select status='DELIVERY_RECOVERY',escalation_state='DELIVERY_RECOVERY',assigned_rider_id='$rider_c'::uuid,dastak_v1_api.mission_has_package_custody(id) from dastak_v1.delivery_missions where id='$mission_a'::uuid")"
[[ "$recovery_truth" == "t t t t" ]] || { printf 'post-custody unresponsive handling reassigned or lost recovery truth: %s\n' "$recovery_truth" >&2; exit 1; }

paid_commitments="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.orders where id in ('$order_a'::uuid,'$order_b'::uuid) and paid_at is not null")"
[[ "$paid_commitments" == "2" ]] || { printf 'emergency controls altered paid commitments\n' >&2; exit 1; }

printf 'Dastak V1 rider assignment, transport revalidation and operational safety races passed.\n'
