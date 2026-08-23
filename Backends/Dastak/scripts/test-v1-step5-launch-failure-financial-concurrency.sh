#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-step5.XXXXXX")"
run_token="$(date +%s)$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
owner_id='99600000-0000-4000-8000-000000000001'
customer_id='99600000-0000-4000-8000-000000000002'
outsider_id='99600000-0000-4000-8000-000000000003'
source_merchant='99600000-0000-4000-8000-000000000004'
merchant_b='99600000-0000-4000-8000-000000000005'
merchant_c='99600000-0000-4000-8000-000000000006'
rider_id='99600000-0000-4000-8000-000000000007'
recovery_rider_id='99600000-0000-4000-8000-000000000008'
source_org='99600000-0000-4000-8000-000000000020'
org_b='99600000-0000-4000-8000-000000000030'
org_c='99600000-0000-4000-8000-000000000040'
source_branch='99600000-0000-4000-8000-000000000021'
branch_b='99600000-0000-4000-8000-000000000031'
branch_c='99600000-0000-4000-8000-000000000041'
sku_id='99600000-0000-4000-8000-000000000052'
recovery_order='99600000-0000-4000-8000-000000000100'
delivered_order='99600000-0000-4000-8000-000000000101'
delivery_recovery_order='99600000-0000-4000-8000-000000000102'
recovery_line='99600000-0000-4000-8000-000000000110'
delivered_line='99600000-0000-4000-8000-000000000111'
delivery_recovery_line='99600000-0000-4000-8000-000000000112'
source_fulfilment='99600000-0000-4000-8000-000000000140'
delivered_fulfilment='99600000-0000-4000-8000-000000000141'
delivery_recovery_fulfilment='99600000-0000-4000-8000-000000000142'
delivery_recovery_mission='99600000-0000-4000-8000-000000000202'

"${psql_base[@]}" <<'SQL'
begin;
insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at
) values
('99600000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step5-owner@example.test','',now(),now(),now()),
('99600000-0000-4000-8000-000000000002','00000000-0000-0000-8000-000000000000','authenticated','authenticated','step5-customer@example.test','',now(),now(),now()),
('99600000-0000-4000-8000-000000000003','00000000-0000-0000-8000-000000000000','authenticated','authenticated','step5-outsider@example.test','',now(),now(),now()),
('99600000-0000-4000-8000-000000000004','00000000-0000-0000-8000-000000000000','authenticated','authenticated','step5-source@example.test','',now(),now(),now()),
('99600000-0000-4000-8000-000000000005','00000000-0000-0000-8000-000000000000','authenticated','authenticated','step5-b@example.test','',now(),now(),now()),
('99600000-0000-4000-8000-000000000006','00000000-0000-0000-8000-000000000000','authenticated','authenticated','step5-c@example.test','',now(),now(),now()),
('99600000-0000-4000-8000-000000000007','00000000-0000-0000-8000-000000000000','authenticated','authenticated','step5-rider@example.test','',now(),now(),now()),
('99600000-0000-4000-8000-000000000008','00000000-0000-0000-8000-000000000000','authenticated','authenticated','step5-recovery-rider@example.test','',now(),now(),now())
on conflict (id) do nothing;

insert into public.accounts (id,display_name,phone_number) values
('99600000-0000-4000-8000-000000000001','Step 5 Operations','+919960000001'),
('99600000-0000-4000-8000-000000000002','Step 5 Customer','+919960000002'),
('99600000-0000-4000-8000-000000000003','Step 5 Outsider','+919960000003'),
('99600000-0000-4000-8000-000000000004','Step 5 Source Merchant','+919960000004'),
('99600000-0000-4000-8000-000000000005','Step 5 Merchant B','+919960000005'),
('99600000-0000-4000-8000-000000000006','Step 5 Merchant C','+919960000006'),
('99600000-0000-4000-8000-000000000007','Step 5 Return Rider','+919960000007'),
('99600000-0000-4000-8000-000000000008','Step 5 Recovery Rider','+919960000008')
on conflict (id) do nothing;

insert into private.account_memberships (account_id,role,approved_at) values
('99600000-0000-4000-8000-000000000001','owner',now()),
('99600000-0000-4000-8000-000000000002','customer',null),
('99600000-0000-4000-8000-000000000003','customer',null),
('99600000-0000-4000-8000-000000000004','merchant',now()),
('99600000-0000-4000-8000-000000000005','merchant',now()),
('99600000-0000-4000-8000-000000000006','merchant',now()),
('99600000-0000-4000-8000-000000000007','dastak_partner',now()),
('99600000-0000-4000-8000-000000000008','dastak_partner',now())
on conflict (account_id,role) do update set approved_at=excluded.approved_at;

insert into dastak_v1.platform_permission_grants (
  account_id,bundle_id,granted_by,grant_reason
)
select '99600000-0000-4000-8000-000000000001', bundle.id,
  '99600000-0000-4000-8000-000000000001',
  'Step 5 explicit recovery and finance Operations fixture.'
from dastak_v1.permission_bundles bundle
where bundle.id in (
  '10000000-0000-4000-8000-000000000008',
  '10000000-0000-4000-8000-000000000009'
)
and not exists (
  select 1 from dastak_v1.platform_permission_grants grant_row
  where grant_row.account_id='99600000-0000-4000-8000-000000000001'
    and grant_row.bundle_id=bundle.id and grant_row.revoked_at is null
);

insert into private.delivery_partner_applications (
  id,account_id,delivery_method,identity_evidence_object_path,verification_version,
  vehicle_registration_number,vehicle_make_model,vehicle_evidence_object_path,
  status,submitted_at,reviewed_at,reviewed_by
) values (
  '99600000-0000-4000-8000-000000000070','99600000-0000-4000-8000-000000000007',
  'motorbike','dastak-partner/99600000-0000-4000-8000-000000000007/identity.pdf',2,
  'TN 01 S5 0001','Step 5 Motorbike',
  'dastak-partner/99600000-0000-4000-8000-000000000007/vehicle.pdf',
  'approved',now(),now(),'99600000-0000-4000-8000-000000000001'
),(
  '99600000-0000-4000-8000-000000000071','99600000-0000-4000-8000-000000000008',
  'motorbike','dastak-partner/99600000-0000-4000-8000-000000000008/identity.pdf',2,
  'TN 01 S5 0002','Step 5 Recovery Motorbike',
  'dastak-partner/99600000-0000-4000-8000-000000000008/vehicle.pdf',
  'approved',now(),now(),'99600000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;
insert into private.delivery_partner_profiles (account_id,approved_application_id,delivery_method)
values
('99600000-0000-4000-8000-000000000007','99600000-0000-4000-8000-000000000070','motorbike'),
('99600000-0000-4000-8000-000000000008','99600000-0000-4000-8000-000000000071','motorbike')
on conflict (account_id) do update set delivery_method=excluded.delivery_method;
insert into public.service_zones (id,name,boundary,active) values (
  '99600000-0000-4000-8000-000000000010','Step 5 Zone',
  extensions.st_geomfromtext('POLYGON((80 15,81 15,81 16,80 16,80 15))',4326),true
) on conflict (id) do nothing;
insert into private.delivery_partner_availability (
  account_id,status,location,service_zone_id,last_seen_at,available_until
) values (
  '99600000-0000-4000-8000-000000000007','online',
  extensions.st_setsrid(extensions.st_makepoint(80.62,15.68),4326),
  '99600000-0000-4000-8000-000000000010',now(),now()+interval '2 hours'
) on conflict (account_id) do update set
  status='online',location=excluded.location,service_zone_id=excluded.service_zone_id,
  last_seen_at=now(),available_until=now()+interval '2 hours';
insert into dastak_v1.categories (id,name,slug,status,created_by) values
('99600000-0000-4000-8000-000000000050','Step 5 Category','step-5-category','ACTIVE','99600000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.subcategories (id,category_id,name,slug,status,created_by) values
('99600000-0000-4000-8000-000000000051','99600000-0000-4000-8000-000000000050','Step 5 Subcategory','step-5-subcategory','ACTIVE','99600000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.skus (
  id,subcategory_id,canonical_name,slug,pack_size,list_price_paise,
  selling_price_paise,logistics_attributes,status,created_by
) values (
  '99600000-0000-4000-8000-000000000052','99600000-0000-4000-8000-000000000051',
  'Step 5 Exact Product','step-5-exact-product','1 unit',1000,900,
  '{"weightGrams":500,"lengthMillimetres":200,"widthMillimetres":100,"heightMillimetres":100,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}',
  'ACTIVE','99600000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;

insert into dastak_v1.merchant_organizations (id,legal_name,display_name,merchant_type,status,created_by) values
('99600000-0000-4000-8000-000000000020','Step 5 Source Private Limited','Secret Source Merchant','RETAIL','ACTIVE','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8000-000000000030','Step 5 B Private Limited','Secret Recovery B','RETAIL','ACTIVE','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8000-000000000040','Step 5 C Private Limited','Secret Recovery C','DASTAK_CONVENIENCE_STORE','ACTIVE','99600000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.merchant_branches (
  id,organization_id,display_name,service_zone_id,address_snapshot,location,capacity_limit,status,created_by
) values
('99600000-0000-4000-8000-000000000021','99600000-0000-4000-8000-000000000020','Secret Source Branch','99600000-0000-4000-8000-000000000010','{}',extensions.st_setsrid(extensions.st_makepoint(80.60,15.68),4326),2,'ACTIVE','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8000-000000000031','99600000-0000-4000-8000-000000000030','Secret Recovery Branch B','99600000-0000-4000-8000-000000000010','{}',extensions.st_setsrid(extensions.st_makepoint(80.61,15.68),4326),2,'ACTIVE','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8000-000000000041','99600000-0000-4000-8000-000000000040','Secret Recovery Branch C','99600000-0000-4000-8000-000000000010','{}',extensions.st_setsrid(extensions.st_makepoint(80.62,15.68),4326),2,'ACTIVE','99600000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.merchant_users (id,organization_id,account_id,status,created_by) values
('99600000-0000-4000-8000-000000000022','99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000004','ACTIVE','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8000-000000000032','99600000-0000-4000-8000-000000000030','99600000-0000-4000-8000-000000000005','ACTIVE','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8000-000000000042','99600000-0000-4000-8000-000000000040','99600000-0000-4000-8000-000000000006','ACTIVE','99600000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.merchant_permission_grants (
  id,merchant_user_id,organization_id,bundle_id,branch_id,granted_by,grant_reason
) values
('99600000-0000-4000-8000-000000000023','99600000-0000-4000-8000-000000000022','99600000-0000-4000-8000-000000000020','10000000-0000-4000-8000-000000000002','99600000-0000-4000-8000-000000000021','99600000-0000-4000-8000-000000000001','Step 5 source.'),
('99600000-0000-4000-8000-000000000033','99600000-0000-4000-8000-000000000032','99600000-0000-4000-8000-000000000030','10000000-0000-4000-8000-000000000002','99600000-0000-4000-8000-000000000031','99600000-0000-4000-8000-000000000001','Step 5 B.'),
('99600000-0000-4000-8000-000000000043','99600000-0000-4000-8000-000000000042','99600000-0000-4000-8000-000000000040','10000000-0000-4000-8000-000000000002','99600000-0000-4000-8000-000000000041','99600000-0000-4000-8000-000000000001','Step 5 C.')
on conflict (id) do nothing;
insert into dastak_v1.branch_operational_states (branch_id,is_open,accepting_orders,updated_by) values
('99600000-0000-4000-8000-000000000021',true,true,'99600000-0000-4000-8000-000000000004'),
('99600000-0000-4000-8000-000000000031',true,true,'99600000-0000-4000-8000-000000000005'),
('99600000-0000-4000-8000-000000000041',true,true,'99600000-0000-4000-8000-000000000006')
on conflict (branch_id) do update set is_open=true,accepting_orders=true,updated_by=excluded.updated_by,version=dastak_v1.branch_operational_states.version+1;
insert into dastak_v1.merchant_sku_selections (branch_id,sku_id,state,selected_by) values
('99600000-0000-4000-8000-000000000021','99600000-0000-4000-8000-000000000052','SELECTED','99600000-0000-4000-8000-000000000004'),
('99600000-0000-4000-8000-000000000031','99600000-0000-4000-8000-000000000052','SELECTED','99600000-0000-4000-8000-000000000005'),
('99600000-0000-4000-8000-000000000041','99600000-0000-4000-8000-000000000052','SELECTED','99600000-0000-4000-8000-000000000006')
on conflict (branch_id,sku_id) do nothing;

insert into dastak_v1.platform_settings (id,setting_key,scope_type,setting_value,updated_by,update_reason)
select setting.id,setting.key,'GLOBAL',setting.value,'99600000-0000-4000-8000-000000000001','Step 5 runtime configuration.'
from (values
('99600000-0000-4000-8000-000000000300'::uuid,'matching.wave2_timeout_seconds','120'::jsonb),
('99600000-0000-4000-8000-000000000301'::uuid,'matching.wave2_hold_seconds','180'::jsonb),
('99600000-0000-4000-8000-000000000302'::uuid,'matching.wave2_max_pickup_route_meters','50000'::jsonb),
('99600000-0000-4000-8000-000000000303'::uuid,'payment.reservation_seconds','300'::jsonb),
('99600000-0000-4000-8000-000000000304'::uuid,'delivery.default_sku_logistics','{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}'::jsonb),
('99600000-0000-4000-8000-000000000305'::uuid,'delivery.transport_load_profiles','[{"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},{"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500},{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]'::jsonb),
('99600000-0000-4000-8000-000000000306'::uuid,'recovery.radius_meters','50000'::jsonb),
('99600000-0000-4000-8000-000000000307'::uuid,'recovery.offer_timeout_seconds','120'::jsonb),
('99600000-0000-4000-8000-000000000308'::uuid,'retail.prep_time_options_minutes','[10,15,20]'::jsonb),
('99600000-0000-4000-8000-000000000309'::uuid,'returns.reporting_window_seconds','86400'::jsonb),
('99600000-0000-4000-8000-000000000310'::uuid,'refunds.approval_limit_paise','100000'::jsonb),
('99600000-0000-4000-8000-000000000311'::uuid,'settlement.merchant_commission_bps','0'::jsonb),
('99600000-0000-4000-8000-000000000312'::uuid,'settlement.rider_distance_payout','{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb),
('99600000-0000-4000-8000-000000000313'::uuid,'delivery.verification_invalid_attempt_limit','3'::jsonb)
) setting(id,key,value)
where not exists (select 1 from dastak_v1.platform_settings existing where existing.setting_key=setting.key and existing.scope_type='GLOBAL' and existing.scope_id is null);

insert into dastak_v1.orders (
  id,display_order_number,customer_id,order_type,status,submitted_at,paid_at,delivered_at,version
) values
('99600000-0000-4000-8000-000000000100','DV1-STEP5-RECOVERY','99600000-0000-4000-8000-000000000002','RETAIL_ONLY','PREPARING',now()-interval '30 minutes',now()-interval '20 minutes',null,4),
('99600000-0000-4000-8000-000000000101','DV1-STEP5-RETURN','99600000-0000-4000-8000-000000000002','RETAIL_ONLY','DELIVERED',now()-interval '2 hours',now()-interval '110 minutes',now()-interval '10 minutes',12),
('99600000-0000-4000-8000-000000000102','DV1-STEP5-DELIVERY-RECOVERY','99600000-0000-4000-8000-000000000002','RETAIL_ONLY','OUT_FOR_DELIVERY',now()-interval '2 hours',now()-interval '110 minutes',null,10)
on conflict (id) do nothing;
insert into dastak_v1.order_context_snapshots (order_id,delivery_address,recipient,snapshot_hash) values
('99600000-0000-4000-8000-000000000100','{"line1":"1 Recovery Road","latitude":15.68,"longitude":80.62}','{"name":"Step 5 Customer","phoneNumber":"+919960000002"}',extensions.digest('step5-recovery','sha256')),
('99600000-0000-4000-8000-000000000101','{"line1":"2 Return Road","latitude":15.68,"longitude":80.62}','{"name":"Shared Recipient","phoneNumber":"+919969999999"}',extensions.digest('step5-return','sha256')),
('99600000-0000-4000-8000-000000000102','{"line1":"3 Recovery Road","latitude":15.68,"longitude":80.62}','{"name":"Step 5 Customer","phoneNumber":"+919960000002"}',extensions.digest('step5-delivery-recovery','sha256'))
on conflict (order_id) do nothing;
insert into dastak_v1.order_price_snapshots (order_id,snapshot_kind,subtotal_paise,total_paise) values
('99600000-0000-4000-8000-000000000100','FINAL',900,900),
('99600000-0000-4000-8000-000000000101','FINAL',900,900),
('99600000-0000-4000-8000-000000000102','FINAL',900,900)
on conflict (order_id,snapshot_kind) do nothing;
insert into dastak_v1.order_lines (
  id,order_id,line_type,sku_id,product_name_snapshot,pack_size_snapshot,quantity,unit_price_paise,status
) values
('99600000-0000-4000-8000-000000000110','99600000-0000-4000-8000-000000000100','RETAIL_SKU','99600000-0000-4000-8000-000000000052','Step 5 Exact Product','1 unit',1,900,'FULFILLING'),
('99600000-0000-4000-8000-000000000111','99600000-0000-4000-8000-000000000101','RETAIL_SKU','99600000-0000-4000-8000-000000000052','Step 5 Exact Product','1 unit',1,900,'FULFILLING'),
('99600000-0000-4000-8000-000000000112','99600000-0000-4000-8000-000000000102','RETAIL_SKU','99600000-0000-4000-8000-000000000052','Step 5 Exact Product','1 unit',1,900,'FULFILLING')
on conflict (id) do nothing;
insert into dastak_v1.payments (
  id,order_id,customer_id,status,amount_paise,currency_code,reserved_at,expires_at,succeeded_at,provider_payment_reference
) values
('99600000-0000-4000-8000-000000000120','99600000-0000-4000-8000-000000000100','99600000-0000-4000-8000-000000000002','SUCCEEDED',900,'INR',now()-interval '25 minutes',now()-interval '20 minutes',now()-interval '20 minutes','pay_step5recovery'),
('99600000-0000-4000-8000-000000000121','99600000-0000-4000-8000-000000000101','99600000-0000-4000-8000-000000000002','SUCCEEDED',900,'INR',now()-interval '115 minutes',now()-interval '110 minutes',now()-interval '110 minutes','pay_step5return'),
('99600000-0000-4000-8000-000000000122','99600000-0000-4000-8000-000000000102','99600000-0000-4000-8000-000000000002','SUCCEEDED',900,'INR',now()-interval '115 minutes',now()-interval '110 minutes',now()-interval '110 minutes','pay_step5deliveryrecovery')
on conflict (id) do nothing;
insert into dastak_v1.matching_attempts (id,order_id,wave,status,started_at,expires_at,closed_at) values
('99600000-0000-4000-8000-000000000130','99600000-0000-4000-8000-000000000100','WAVE_1','EXPIRED',now()-interval '30 minutes',now()-interval '27 minutes',now()-interval '27 minutes'),
('99600000-0000-4000-8000-000000000131','99600000-0000-4000-8000-000000000101','WAVE_1','EXPIRED',now()-interval '2 hours',now()-interval '117 minutes',now()-interval '117 minutes'),
('99600000-0000-4000-8000-000000000132','99600000-0000-4000-8000-000000000102','WAVE_1','EXPIRED',now()-interval '2 hours',now()-interval '117 minutes',now()-interval '117 minutes')
on conflict (id) do nothing;
insert into dastak_v1.merchant_opportunities (
  id,matching_attempt_id,order_id,organization_id,branch_id,wave,status,started_at,expires_at
) values
('99600000-0000-4000-8000-000000000135','99600000-0000-4000-8000-000000000130','99600000-0000-4000-8000-000000000100','99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000021','WAVE_1','LOST',now()-interval '30 minutes',now()-interval '27 minutes'),
('99600000-0000-4000-8000-000000000136','99600000-0000-4000-8000-000000000131','99600000-0000-4000-8000-000000000101','99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000021','WAVE_1','LOST',now()-interval '2 hours',now()-interval '117 minutes'),
('99600000-0000-4000-8000-000000000137','99600000-0000-4000-8000-000000000132','99600000-0000-4000-8000-000000000102','99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000021','WAVE_1','LOST',now()-interval '2 hours',now()-interval '117 minutes')
on conflict (id) do nothing;
insert into dastak_v1.fulfilments (
  id,order_id,organization_id,branch_id,source_opportunity_id,fulfilment_type,status,
  promised_prep_minutes,committed_at,prep_started_at,estimated_ready_at,ready_at,actual_ready_at,package_count
) values
('99600000-0000-4000-8000-000000000140','99600000-0000-4000-8000-000000000100','99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000021','99600000-0000-4000-8000-000000000135','RETAIL','PREPARING',10,now()-interval '25 minutes',now()-interval '20 minutes',now()-interval '10 minutes',null,null,null),
('99600000-0000-4000-8000-000000000141','99600000-0000-4000-8000-000000000101','99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000021','99600000-0000-4000-8000-000000000136','RETAIL','COMPLETED',10,now()-interval '115 minutes',now()-interval '110 minutes',now()-interval '100 minutes',now()-interval '102 minutes',now()-interval '102 minutes',1),
('99600000-0000-4000-8000-000000000142','99600000-0000-4000-8000-000000000102','99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000021','99600000-0000-4000-8000-000000000137','RETAIL','PICKED_UP',10,now()-interval '115 minutes',now()-interval '110 minutes',now()-interval '100 minutes',now()-interval '102 minutes',now()-interval '102 minutes',1)
on conflict (id) do nothing;
insert into dastak_v1.fulfilment_lines (fulfilment_id,order_line_id,confirmed_quantity) values
('99600000-0000-4000-8000-000000000140','99600000-0000-4000-8000-000000000110',1),
('99600000-0000-4000-8000-000000000141','99600000-0000-4000-8000-000000000111',1),
('99600000-0000-4000-8000-000000000142','99600000-0000-4000-8000-000000000112',1)
on conflict do nothing;
insert into dastak_v1.inventory_holds (id,fulfilment_id,order_line_id,branch_id,held_quantity,status,held_at) values
('99600000-0000-4000-8000-000000000150','99600000-0000-4000-8000-000000000140','99600000-0000-4000-8000-000000000110','99600000-0000-4000-8000-000000000021',1,'HELD',now()-interval '25 minutes')
on conflict (id) do nothing;
insert into dastak_v1.retail_capacity_slots (id,branch_id,fulfilment_id,status,held_at) values
('99600000-0000-4000-8000-000000000151','99600000-0000-4000-8000-000000000021','99600000-0000-4000-8000-000000000140','HELD',now()-interval '25 minutes')
on conflict (id) do nothing;
insert into dastak_v1.packages (
  id,order_id,fulfilment_id,package_number,status,current_custody_owner_type,current_custody_owner_id,
  declared_by,declared_at,ready_at,picked_up_at,delivered_at
) values
('99600000-0000-4000-8000-000000000160','99600000-0000-4000-8000-000000000101','99600000-0000-4000-8000-000000000141',1,'DELIVERED','CUSTOMER','99600000-0000-4000-8000-000000000002','99600000-0000-4000-8000-000000000004',now()-interval '105 minutes',now()-interval '102 minutes',now()-interval '30 minutes',now()-interval '10 minutes'),
('99600000-0000-4000-8000-000000000161','99600000-0000-4000-8000-000000000102','99600000-0000-4000-8000-000000000142',1,'IN_TRANSIT','RIDER','99600000-0000-4000-8000-000000000008','99600000-0000-4000-8000-000000000004',now()-interval '105 minutes',now()-interval '102 minutes',now()-interval '30 minutes',null)
on conflict (id) do nothing;
insert into dastak_v1.delivery_missions (
  id,order_id,status,assigned_rider_id,assigned_transport_type,transport_snapshot,pickup_count,
  search_started_at,assigned_at,first_package_picked_up_at,all_packages_picked_up_at,out_for_delivery_at,version
) values (
  '99600000-0000-4000-8000-000000000202','99600000-0000-4000-8000-000000000102','DELIVERY_RECOVERY',
  '99600000-0000-4000-8000-000000000008','MOTORBIKE','{"feasible":true,"eligibleTransportTypes":["MOTORBIKE"]}',1,
  now()-interval '40 minutes',now()-interval '35 minutes',now()-interval '30 minutes',now()-interval '29 minutes',now()-interval '20 minutes',7
) on conflict (id) do nothing;
insert into dastak_v1.recovery_cases (
  id,case_type,order_id,delivery_mission_id,status,fault_source,reason,opened_by,opened_at
) values (
  '99600000-0000-4000-8000-000000000203','DELIVERY','99600000-0000-4000-8000-000000000102',
  '99600000-0000-4000-8000-000000000202','ACTION_REQUIRED','UNKNOWN','Address access issue requires Operations.',
  '99600000-0000-4000-8000-000000000008',now()-interval '5 minutes'
) on conflict (id) do nothing;
insert into dastak_v1.settlement_entries (
  id,entry_key,subject_type,subject_id,order_id,fulfilment_id,order_line_id,entry_type,
  status,calculation_status,gross_amount_paise,amount_paise,calculation_snapshot
) values (
  '99600000-0000-4000-8000-000000000170','996-step5-delivered-earning','MERCHANT_ORGANIZATION',
  '99600000-0000-4000-8000-000000000020','99600000-0000-4000-8000-000000000101',
  '99600000-0000-4000-8000-000000000141','99600000-0000-4000-8000-000000000111','EARNING',
  'PENDING','CALCULATED',900,900,'{"formula":"STEP5_RUNTIME_FIXTURE"}'
) on conflict (id) do nothing;
insert into dastak_v1.settlement_entries (
  id,entry_key,subject_type,subject_id,order_id,delivery_mission_id,entry_type,
  status,calculation_status,gross_amount_paise,amount_paise,calculation_snapshot
) values (
  '99600000-0000-4000-8000-000000000171','996-step5-rider-config','RIDER',
  '99600000-0000-4000-8000-000000000008','99600000-0000-4000-8000-000000000102',
  '99600000-0000-4000-8000-000000000202','EARNING','PENDING',
  'SYSTEM_CONFIGURATION_REQUIRED',null,null,'{"configurationRequired":true}'
) on conflict (id) do nothing;
commit;
SQL

# Exact-SKU recovery is full-line, price preserving and has one atomic winner.
recovery_json="$("${psql_base[@]}" -Atc "select dastak_v1_api.report_exact_sku_failure('$source_merchant'::uuid,'$source_fulfilment'::uuid,'$recovery_line'::uuid,'Exact item became unavailable after payment.',1,'report-$run_token') from (select set_config('request.jwt.claim.sub','$source_merchant',false)) actor")"
recovery_case="$(printf '%s' "$recovery_json" | sed -n 's/.*"recoveryCaseId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[[ -n "$recovery_case" ]] || { printf 'exact-SKU recovery did not start: %s\n' "$recovery_json" >&2; exit 1; }
offer_b_json="$("${psql_base[@]}" -Atc "select dastak_v1_api.create_exact_sku_recovery_offer('$owner_id'::uuid,'$recovery_case'::uuid,'$branch_b'::uuid,1,'offer-b-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
offer_c_json="$("${psql_base[@]}" -Atc "select dastak_v1_api.create_exact_sku_recovery_offer('$owner_id'::uuid,'$recovery_case'::uuid,'$branch_c'::uuid,1,'offer-c-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
offer_b="$(printf '%s' "$offer_b_json" | sed -n 's/.*"recoveryOpportunityId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
offer_c="$(printf '%s' "$offer_c_json" | sed -n 's/.*"recoveryOpportunityId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[[ -n "$offer_b" && -n "$offer_c" ]] || { printf 'recovery offers missing\n' >&2; exit 1; }

set +e
"${psql_base[@]}" -Atc "select dastak_v1_api.respond_exact_sku_recovery_offer('$merchant_b'::uuid,'$offer_b'::uuid,'ACCEPT',10,1,'accept-b-$run_token') from (select set_config('request.jwt.claim.sub','$merchant_b',false)) actor" >"$work_dir/recovery-b.out" 2>"$work_dir/recovery-b.err" &
pid_b=$!
"${psql_base[@]}" -Atc "select dastak_v1_api.respond_exact_sku_recovery_offer('$merchant_c'::uuid,'$offer_c'::uuid,'ACCEPT',10,1,'accept-c-$run_token') from (select set_config('request.jwt.claim.sub','$merchant_c',false)) actor" >"$work_dir/recovery-c.out" 2>"$work_dir/recovery-c.err" &
pid_c=$!
wait "$pid_b"; rc_b=$?
wait "$pid_c"; rc_c=$?
set -e
[[ $(( (rc_b == 0 ? 1 : 0) + (rc_c == 0 ? 1 : 0) )) -eq 1 ]] || {
  printf 'exact-SKU accept race did not have one winner: b=%s c=%s\n' "$rc_b" "$rc_c" >&2; exit 1;
}
recovery_truth="$("${psql_base[@]}" -At -F '|' -c "
select
  (select status from dastak_v1.recovery_cases where id='$recovery_case'::uuid),
  (select count(*) from dastak_v1.fulfilments where source_recovery_opportunity_id in ('$offer_b'::uuid,'$offer_c'::uuid)),
  (select count(*) from dastak_v1.fulfilment_lines fl join dastak_v1.fulfilments f on f.id=fl.fulfilment_id where f.source_recovery_opportunity_id in ('$offer_b'::uuid,'$offer_c'::uuid) and fl.confirmed_quantity=1),
  (select count(*) from dastak_v1.recovery_opportunities where recovery_case_id='$recovery_case'::uuid and status='SELECTED'),
  (select count(*) from dastak_v1.recovery_opportunities where recovery_case_id='$recovery_case'::uuid and status='CLOSED'),
  (select count(*) from dastak_v1.payments where order_id='$recovery_order'::uuid and amount_paise=900),
  (select status from dastak_v1.retail_capacity_slots where fulfilment_id='$source_fulfilment'::uuid)")"
[[ "$recovery_truth" == "RECOVERED|1|1|1|1|1|RELEASED" ]] || { printf 'exact-SKU recovery invariants failed: %s\n' "$recovery_truth" >&2; exit 1; }

# A replacement that also fails closes offered work, refunds once, and replays safely.
replacement_fulfilment="$("${psql_base[@]}" -Atc "select id from dastak_v1.fulfilments where source_recovery_opportunity_id in ('$offer_b'::uuid,'$offer_c'::uuid)")"
replacement_merchant="$("${psql_base[@]}" -Atc "select merchant.account_id from dastak_v1.fulfilments fulfilment join dastak_v1.merchant_users merchant on merchant.organization_id=fulfilment.organization_id and merchant.status='ACTIVE' where fulfilment.id='$replacement_fulfilment'::uuid order by merchant.created_at limit 1")"
second_recovery_json="$("${psql_base[@]}" -Atc "select dastak_v1_api.report_exact_sku_failure('$replacement_merchant'::uuid,'$replacement_fulfilment'::uuid,'$recovery_line'::uuid,'The exact replacement also became unavailable.',1,'second-report-$run_token') from (select set_config('request.jwt.claim.sub','$replacement_merchant',false)) actor")"
second_recovery_case="$(printf '%s' "$second_recovery_json" | sed -n 's/.*"recoveryCaseId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[[ -n "$second_recovery_case" ]] || { printf 'second exact-SKU recovery did not start: %s\n' "$second_recovery_json" >&2; exit 1; }
"${psql_base[@]}" -Atc "select dastak_v1_api.create_exact_sku_recovery_offer('$owner_id'::uuid,'$second_recovery_case'::uuid,'$source_branch'::uuid,1,'second-offer-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >/dev/null
failed_recovery="$("${psql_base[@]}" -Atc "select dastak_v1_api.fail_exact_sku_recovery('$owner_id'::uuid,'$second_recovery_case'::uuid,'No eligible branch could preserve the exact paid line.',1,'fail-recovery-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
failed_recovery_replay="$("${psql_base[@]}" -Atc "select dastak_v1_api.fail_exact_sku_recovery('$owner_id'::uuid,'$second_recovery_case'::uuid,'No eligible branch could preserve the exact paid line.',1,'fail-recovery-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
[[ "$failed_recovery" == "$failed_recovery_replay" ]] || { printf 'failed recovery idempotent replay changed response\n' >&2; exit 1; }
failed_recovery_truth="$("${psql_base[@]}" -At -F '|' -c "
select
  (select status from dastak_v1.recovery_cases where id='$second_recovery_case'::uuid),
  (select status from dastak_v1.orders where id='$recovery_order'::uuid),
  (select status from dastak_v1.order_lines where id='$recovery_line'::uuid),
  (select count(*) from dastak_v1.recovery_opportunities where recovery_case_id='$second_recovery_case'::uuid and status='CLOSED'),
  (select count(*) from dastak_v1.refunds where recovery_case_id='$second_recovery_case'::uuid and status='APPROVED' and amount_paise=900 and destination='ORIGINAL_PAYMENT_METHOD')")"
[[ "$failed_recovery_truth" == "RECOVERY_FAILED|DASTAK_FULFILMENT_FAILURE|REFUNDED|1|1" ]] || { printf 'failed exact-SKU recovery/refund invariants failed: %s\n' "$failed_recovery_truth" >&2; exit 1; }

# Delivery Recovery remains an Operations-only, audited state distinct from normal delivery.
delivery_resume="$("${psql_base[@]}" -Atc "select dastak_v1_api.manage_delivery_recovery(
  '$owner_id'::uuid,'99600000-0000-4000-8000-000000000203'::uuid,'RESUME_DELIVERY','CUSTOMER',null,
  '{\"line1\":\"3A Corrected Recovery Road\",\"latitude\":15.68,\"longitude\":80.62}'::jsonb,
  'Customer confirmed a minor address correction.',1,'resume-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
[[ "$delivery_resume" == *'"recoveryStatus": "RESOLVED"'* && "$delivery_resume" == *'"missionStatus": "OUT_FOR_DELIVERY"'* ]] || {
  printf 'delivery recovery did not resume safely: %s\n' "$delivery_resume" >&2; exit 1;
}
[[ "$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.delivery_address_exceptions where recovery_case_id='99600000-0000-4000-8000-000000000203'::uuid")" == "1" ]] || {
  printf 'delivery recovery address exception was not audited\n' >&2; exit 1;
}

# The mission quote is immutable and later payout-policy changes cannot rewrite it.
set +e
"${psql_base[@]}" -c "update dastak_v1.delivery_missions set rider_payout_quote_paise=rider_payout_quote_paise+1,version=version+1 where id='99600000-0000-4000-8000-000000000202'::uuid" >"$work_dir/rewrite-payout.out" 2>&1
rewrite_payout_rc=$?
set -e
[[ $rewrite_payout_rc -ne 0 ]] || { printf 'mission payout snapshot was mutable\n' >&2; exit 1; }
grep -q 'delivery mission payout quote cannot change' "$work_dir/rewrite-payout.out"

"${psql_base[@]}" -c "
update dastak_v1.platform_settings
set setting_value='{\"base_distance_meters\":1000,\"base_payout_paise\":9900,\"increment_distance_meters\":1000,\"increment_payout_paise\":100,\"rounding\":\"STARTED_DISTANCE_BAND\"}'::jsonb,
  updated_by='$owner_id'::uuid, update_reason='Prove mission quote survives later payout configuration.',
  version=version+1
where setting_key='settlement.rider_distance_payout'
  and scope_type='GLOBAL' and scope_id is null" >/dev/null

calculation_result="$("${psql_base[@]}" -Atc "select dastak_v1_api.finalize_settlement_calculation('$owner_id'::uuid,'99600000-0000-4000-8000-000000000171'::uuid,1,'calculate-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
calculation_replay="$("${psql_base[@]}" -Atc "select dastak_v1_api.finalize_settlement_calculation('$owner_id'::uuid,'99600000-0000-4000-8000-000000000171'::uuid,1,'calculate-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
[[ "$calculation_result" == "$calculation_replay" ]] || { printf 'settlement calculation retry was not idempotent\n' >&2; exit 1; }
calculation_truth="$("${psql_base[@]}" -At -F '|' -c "
select entry.status,entry.calculation_status,
  entry.amount_paise=mission.rider_payout_quote_paise,
  entry.amount_paise<>dastak_v1_api.calculate_rider_distance_payout(
    mission.delivery_distance_meters,
    dastak_v1_api.effective_setting_json('settlement.rider_distance_payout')
  ),entry.version,
  entry.calculation_snapshot->>'rounding',
  (entry.calculation_snapshot->>'deliveryDistanceMeters')::bigint=mission.delivery_distance_meters
from dastak_v1.settlement_entries entry
join dastak_v1.delivery_missions mission on mission.id=entry.delivery_mission_id
where entry.id='99600000-0000-4000-8000-000000000171'::uuid")"
[[ "$calculation_truth" == "PENDING|CALCULATED|t|t|2|STARTED_DISTANCE_BAND|t" ]] || { printf 'snapshotted distance settlement calculation failed: %s\n' "$calculation_truth" >&2; exit 1; }

# Customer issue -> physical return -> reverse custody -> original-method refund.
issue_json="$("${psql_base[@]}" -Atc "select dastak_v1_api.report_customer_issue(
  '$customer_id'::uuid,'$delivered_order'::uuid,'$delivered_line'::uuid,'DELIVERY_PROBLEM',
  'The delivered package needs a physical return.',null,null,'issue-$run_token') from (select set_config('request.jwt.claim.sub','$customer_id',false)) actor")"
issue_id="$(printf '%s' "$issue_json" | sed -n 's/.*"issueId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[[ -n "$issue_id" ]] || { printf 'customer issue was not created: %s\n' "$issue_json" >&2; exit 1; }
set +e
"${psql_base[@]}" -Atc "select dastak_v1_api.report_customer_issue('$outsider_id'::uuid,'$delivered_order'::uuid,'$delivered_line'::uuid,'OTHER','Not my order.',null,null,'outsider-$run_token') from (select set_config('request.jwt.claim.sub','$outsider_id',false)) actor" >"$work_dir/outsider.out" 2>"$work_dir/outsider.err"
outsider_rc=$?
set -e
[[ $outsider_rc -ne 0 ]] || { printf 'customer issue ownership isolation failed\n' >&2; exit 1; }

decision_json="$("${psql_base[@]}" -Atc "select dastak_v1_api.decide_customer_issue(
  '$owner_id'::uuid,'$issue_id'::uuid,'PHYSICAL_RETURN',900,'MERCHANT',1,
  'Operations approved a complete physical return.',1,'decision-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
return_id="$(printf '%s' "$decision_json" | sed -n 's/.*"returnId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
return_mission="$(printf '%s' "$decision_json" | sed -n 's/.*"returnMissionId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[[ -n "$return_id" && -n "$return_mission" ]] || { printf 'physical return was not created: %s\n' "$decision_json" >&2; exit 1; }

"${psql_base[@]}" -Atc "select dastak_v1_api.assign_return_rider('$owner_id'::uuid,'$return_mission'::uuid,'$rider_id'::uuid,1,'assign-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor" >/dev/null
pickup_code="$("${psql_base[@]}" -Atc "select private.dastak_v1_handoff_code(id,handoff_type,code_version) from dastak_v1.return_verifications where return_mission_id='$return_mission'::uuid and handoff_type='CUSTOMER_TO_RETURN_RIDER'")"
return_stop="$("${psql_base[@]}" -Atc "select id from dastak_v1.return_stops where return_mission_id='$return_mission'::uuid")"
receipt_code="$("${psql_base[@]}" -Atc "select private.dastak_v1_handoff_code(id,handoff_type,code_version) from dastak_v1.return_verifications where return_stop_id='$return_stop'::uuid")"
"${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'ARRIVE_CUSTOMER',null,null,null,'arrive-$run_token')" >/dev/null
set +e
"${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'VERIFY_RETURN_PICKUP',null,null,'$pickup_code','missing-evidence-$run_token')" >"$work_dir/missing-evidence.out" 2>"$work_dir/missing-evidence.err"
missing_evidence_rc=$?
set -e
[[ $missing_evidence_rc -ne 0 ]] || { printf 'return pickup succeeded without evidence\n' >&2; exit 1; }
return_path="return-pickup/$rider_id/step5-$run_token.jpg"
"${psql_base[@]}" -c "insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('dastak-evidence','$return_path','$rider_id'::uuid,'$rider_id','{\"mimetype\":\"image/jpeg\",\"size\":2048}')" >/dev/null
"${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'ADD_RETURN_EVIDENCE',null,'$return_path',null,'evidence-$run_token')" >/dev/null
wrong_pickup="$("${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'VERIFY_RETURN_PICKUP',null,null,'000000','wrong-pickup-$run_token')->'error'->>'code'")"
[[ "$wrong_pickup" == "return_pickup_code_invalid" ]] || { printf 'wrong return code was not recorded: %s\n' "$wrong_pickup" >&2; exit 1; }
"${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'VERIFY_RETURN_PICKUP',null,null,'$pickup_code','pickup-$run_token')" >/dev/null
duplicate_pickup="$("${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'VERIFY_RETURN_PICKUP',null,null,'$pickup_code','pickup-$run_token')->>'missionStatus'")"
[[ "$duplicate_pickup" == "RETURNING_TO_MERCHANTS" ]] || { printf 'idempotent return pickup retry changed truth\n' >&2; exit 1; }
set +e
"${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'VERIFY_RETURN_PICKUP',null,null,'$pickup_code','replay-$run_token')" >"$work_dir/pickup-replay.out" 2>"$work_dir/pickup-replay.err"
pickup_replay_rc=$?
set -e
[[ $pickup_replay_rc -ne 0 ]] || { printf 'consumed return pickup code replay succeeded\n' >&2; exit 1; }
"${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'ARRIVE_RETURN_STOP','$return_stop'::uuid,null,null,'stop-$run_token')" >/dev/null
"${psql_base[@]}" -Atc "select dastak_v1_api.advance_return_mission('$rider_id'::uuid,'$return_mission'::uuid,'VERIFY_RETURN_RECEIPT','$return_stop'::uuid,null,'$receipt_code','receipt-$run_token')" >/dev/null

reverse_truth="$("${psql_base[@]}" -At -F '|' -c "
select
  (select status from dastak_v1.returns where id='$return_id'::uuid),
  (select status from dastak_v1.return_missions where id='$return_mission'::uuid),
  (select count(*) from dastak_v1.return_packages where return_id='$return_id'::uuid and status='MERCHANT_RETURN_CUSTODY' and current_custody_owner_type='MERCHANT_RETURN'),
  (select count(*) from dastak_v1.return_custody_events where return_id='$return_id'::uuid),
  (select count(*) from dastak_v1.refunds where return_id='$return_id'::uuid and destination='ORIGINAL_PAYMENT_METHOD' and status='APPROVED')")"
[[ "$reverse_truth" == "COMPLETED|COMPLETED|1|2|1" ]] || { printf 'reverse custody/refund invariants failed: %s\n' "$reverse_truth" >&2; exit 1; }
refund_id="$("${psql_base[@]}" -Atc "select id from dastak_v1.refunds where return_id='$return_id'::uuid")"

set +e
"${psql_base[@]}" -Atc "select dastak_v1_api.settle_entry('$customer_id'::uuid,'99600000-0000-4000-8000-000000000170'::uuid,'unauthorized',1,'bad-settle-$run_token') from (select set_config('request.jwt.claim.sub','$customer_id',false)) actor" >"$work_dir/bad-settle.out" 2>"$work_dir/bad-settle.err"
bad_settle_rc=$?
set -e
[[ $bad_settle_rc -ne 0 ]] || { printf 'unauthorized settlement action succeeded\n' >&2; exit 1; }

"${psql_base[@]}" -Atc "select dastak_v1_api.prepare_razorpay_refund('$owner_id'::uuid,'$refund_id'::uuid,'prepare-$run_token')" >/dev/null
"${psql_base[@]}" -Atc "select dastak_v1_api.attach_razorpay_refund('$owner_id'::uuid,'$refund_id'::uuid,'rfnd_step5return',900)" >/dev/null
refund_event="evt_step5_$run_token"
"${psql_base[@]}" -Atc "select response_status from public.dastak_v1_record_razorpay_event('$refund_event','refund_succeeded',null,'pay_step5return','rfnd_step5return',900,now(),'5555555555555555555555555555555555555555555555555555555555555555')" >"$work_dir/refund-a.out" &
refund_pid_a=$!
"${psql_base[@]}" -Atc "select response_status from public.dastak_v1_record_razorpay_event('$refund_event','refund_succeeded',null,'pay_step5return','rfnd_step5return',900,now(),'5555555555555555555555555555555555555555555555555555555555555555')" >"$work_dir/refund-b.out" &
refund_pid_b=$!
wait "$refund_pid_a"
wait "$refund_pid_b"
[[ "$(tr -d '[:space:]' <"$work_dir/refund-a.out")" == "200" && "$(tr -d '[:space:]' <"$work_dir/refund-b.out")" == "200" ]] || {
  printf 'duplicate refund webhook did not return idempotent success\n' >&2; exit 1;
}
refund_truth="$("${psql_base[@]}" -At -F '|' -c "
select
  (select status from dastak_v1.refunds where id='$refund_id'::uuid),
  (select count(*) from dastak_v1.refund_provider_events where provider_event_id='$refund_event'),
  (select count(*) from dastak_v1.domain_events_outbox where event_key like '$refund_id:REFUND_COMPLETED:%'),
  (select count(*) from dastak_v1.settlement_entries where refund_id='$refund_id'::uuid and entry_type='REFUND_ADJUSTMENT' and status='ELIGIBLE')")"
[[ "$refund_truth" == "COMPLETED|1|1|1" ]] || { printf 'refund idempotency/settlement eligibility failed: %s\n' "$refund_truth" >&2; exit 1; }

adjustment_id="$("${psql_base[@]}" -Atc "select id from dastak_v1.settlement_entries where refund_id='$refund_id'::uuid")"
adjustment_version="$("${psql_base[@]}" -Atc "select version from dastak_v1.settlement_entries where id='$adjustment_id'::uuid")"
settlement_result="$("${psql_base[@]}" -Atc "select dastak_v1_api.settle_entry('$owner_id'::uuid,'$adjustment_id'::uuid,'bank-step5-$run_token',$adjustment_version,'settle-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
settlement_replay="$("${psql_base[@]}" -Atc "select dastak_v1_api.settle_entry('$owner_id'::uuid,'$adjustment_id'::uuid,'bank-step5-$run_token',$adjustment_version,'settle-$run_token') from (select set_config('request.jwt.claim.sub','$owner_id',false)) actor")"
[[ "$settlement_result" == "$settlement_replay" ]] || { printf 'settlement retry was not idempotent\n' >&2; exit 1; }
settlement_truth="$("${psql_base[@]}" -At -F '|' -c "select status,(select count(*) from dastak_v1.settlement_entry_history h where h.settlement_entry_id=e.id) from dastak_v1.settlement_entries e where e.id='$adjustment_id'::uuid")"
[[ "$settlement_truth" == "SETTLED|3" ]] || { printf 'append-only settlement history failed: %s\n' "$settlement_truth" >&2; exit 1; }

customer_projection="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_json('$delivered_order'::uuid,'$customer_id'::uuid)::text")"
[[ "$customer_projection" == *'"support"'* && "$customer_projection" == *'"refunds"'* ]] || { printf 'customer support/refund projection missing\n' >&2; exit 1; }
[[ "$customer_projection" != *'Secret Source'* && "$customer_projection" != *"$source_branch"* && "$customer_projection" != *"$source_org"* ]] || {
  printf 'customer support projection leaked retail merchant identity\n' >&2; exit 1;
}

printf 'Step 5 exact-SKU recovery, delivery recovery, reverse custody, refund race, settlement and privacy gates passed.\n'
