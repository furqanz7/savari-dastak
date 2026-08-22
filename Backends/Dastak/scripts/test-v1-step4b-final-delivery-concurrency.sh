#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-step4b.XXXXXX")"
run_token="$(date +%s)$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
owner_id='99500000-0000-4000-8000-000000000001'
customer_id='99500000-0000-4000-8000-000000000002'
rider_id='99500000-0000-4000-8000-000000000003'
wrong_rider_id='99500000-0000-4000-8000-000000000004'
unauthorized_id='99500000-0000-4000-8000-000000000005'
merchant_id='99500000-0000-4000-8000-000000000006'
override_rider_id='99500000-0000-4000-8000-000000000007'
organization_id='99500000-0000-4000-8000-000000000010'
branch_id='99500000-0000-4000-8000-000000000011'
category_id='99500000-0000-4000-8000-000000000012'
subcategory_id='99500000-0000-4000-8000-000000000013'
sku_id='99500000-0000-4000-8000-000000000014'
order_normal='99500000-0000-4000-8000-000000000100'
order_missing='99500000-0000-4000-8000-000000000101'
order_override='99500000-0000-4000-8000-000000000102'
mission_normal='99500000-0000-4000-8000-000000000200'
mission_missing='99500000-0000-4000-8000-000000000201'
mission_override='99500000-0000-4000-8000-000000000202'

"${psql_base[@]}" <<'SQL'
begin;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
('99500000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step4b-owner@example.test','',now(),now(),now()),
('99500000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step4b-customer@example.test','',now(),now(),now()),
('99500000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step4b-rider@example.test','',now(),now(),now()),
('99500000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step4b-wrong-rider@example.test','',now(),now(),now()),
('99500000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step4b-unauthorized@example.test','',now(),now(),now()),
('99500000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step4b-merchant@example.test','',now(),now(),now()),
('99500000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','step4b-override-rider@example.test','',now(),now(),now())
on conflict (id) do nothing;

insert into public.accounts (id, display_name, phone_number) values
('99500000-0000-4000-8000-000000000001','Step 4B Operations','+919950000001'),
('99500000-0000-4000-8000-000000000002','Step 4B Buyer','+919950000002'),
('99500000-0000-4000-8000-000000000003','Step 4B Rider','+919950000003'),
('99500000-0000-4000-8000-000000000004','Step 4B Wrong Rider','+919950000004'),
('99500000-0000-4000-8000-000000000005','Step 4B Unauthorized','+919950000005'),
('99500000-0000-4000-8000-000000000006','Step 4B Merchant','+919950000006'),
('99500000-0000-4000-8000-000000000007','Step 4B Override Rider','+919950000007')
on conflict (id) do nothing;

insert into private.account_memberships (account_id, role, approved_at) values
('99500000-0000-4000-8000-000000000001','owner',now()),
('99500000-0000-4000-8000-000000000002','customer',null),
('99500000-0000-4000-8000-000000000003','dastak_partner',now()),
('99500000-0000-4000-8000-000000000004','dastak_partner',now()),
('99500000-0000-4000-8000-000000000005','customer',null),
('99500000-0000-4000-8000-000000000006','merchant',now()),
('99500000-0000-4000-8000-000000000007','dastak_partner',now())
on conflict (account_id, role) do update set approved_at=excluded.approved_at;

insert into dastak_v1.platform_permission_grants (
  account_id,bundle_id,granted_by,grant_reason
)
select '99500000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000007',
  '99500000-0000-4000-8000-000000000001',
  'Step 4B explicit Delivery Operations fixture.'
where not exists (
  select 1 from dastak_v1.platform_permission_grants grant_row
  where grant_row.account_id='99500000-0000-4000-8000-000000000001'
    and grant_row.bundle_id='10000000-0000-4000-8000-000000000007'
    and grant_row.revoked_at is null
  );

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  verification_version, vehicle_registration_number, vehicle_make_model,
  vehicle_evidence_object_path, status, submitted_at, reviewed_at, reviewed_by
) values
('99500000-0000-4000-8000-000000000020','99500000-0000-4000-8000-000000000003','motorbike','dastak-partner/99500000-0000-4000-8000-000000000003/identity.pdf',2,'TN 01 BB 4001','Test Motorbike','dastak-partner/99500000-0000-4000-8000-000000000003/vehicle.pdf','approved',now(),now(),'99500000-0000-4000-8000-000000000001'),
('99500000-0000-4000-8000-000000000021','99500000-0000-4000-8000-000000000004','motorbike','dastak-partner/99500000-0000-4000-8000-000000000004/identity.pdf',2,'TN 01 BB 4002','Test Motorbike','dastak-partner/99500000-0000-4000-8000-000000000004/vehicle.pdf','approved',now(),now(),'99500000-0000-4000-8000-000000000001'),
('99500000-0000-4000-8000-000000000022','99500000-0000-4000-8000-000000000007','motorbike','dastak-partner/99500000-0000-4000-8000-000000000007/identity.pdf',2,'TN 01 BB 4003','Test Motorbike','dastak-partner/99500000-0000-4000-8000-000000000007/vehicle.pdf','approved',now(),now(),'99500000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values
('99500000-0000-4000-8000-000000000003','99500000-0000-4000-8000-000000000020','motorbike'),
('99500000-0000-4000-8000-000000000004','99500000-0000-4000-8000-000000000021','motorbike'),
('99500000-0000-4000-8000-000000000007','99500000-0000-4000-8000-000000000022','motorbike')
on conflict (account_id) do update set delivery_method=excluded.delivery_method;

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values (
  '99500000-0000-4000-8000-000000000010','Hidden Step 4B Retail Private Limited',
  'Hidden Step 4B Retail','RETAIL','ACTIVE','99500000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;
insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, address_snapshot, location,
  capacity_limit, status, created_by
) values (
  '99500000-0000-4000-8000-000000000011','99500000-0000-4000-8000-000000000010',
  'Hidden Final Delivery Branch','{"line1":"Secret Pickup Street"}',
  extensions.st_setsrid(extensions.st_makepoint(80.60,15.70),4326),5,'ACTIVE',
  '99500000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;
insert into dastak_v1.categories (id,name,slug,status,created_by) values
('99500000-0000-4000-8000-000000000012','Step 4B Category','step-4b-category','ACTIVE','99500000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.subcategories (id,category_id,name,slug,status,created_by) values
('99500000-0000-4000-8000-000000000013','99500000-0000-4000-8000-000000000012','Step 4B Subcategory','step-4b-subcategory','ACTIVE','99500000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, logistics_attributes, status, created_by
) values (
  '99500000-0000-4000-8000-000000000014','99500000-0000-4000-8000-000000000013',
  'Step 4B Product','step-4b-product','1 unit',1000,900,
  '{"weightGrams":500,"lengthMillimetres":200,"widthMillimetres":100,"heightMillimetres":100,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}',
  'ACTIVE','99500000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, paid_at, version
) values
('99500000-0000-4000-8000-000000000100','DV1-STEP4B-NORMAL','99500000-0000-4000-8000-000000000002','RETAIL_ONLY','PICKUP_IN_PROGRESS',now()-interval '30 minutes',now()-interval '20 minutes',8),
('99500000-0000-4000-8000-000000000101','DV1-STEP4B-MISSING','99500000-0000-4000-8000-000000000002','RETAIL_ONLY','PICKUP_IN_PROGRESS',now()-interval '30 minutes',now()-interval '20 minutes',8),
('99500000-0000-4000-8000-000000000102','DV1-STEP4B-OVERRIDE','99500000-0000-4000-8000-000000000002','RETAIL_ONLY','PICKUP_IN_PROGRESS',now()-interval '30 minutes',now()-interval '20 minutes',8)
on conflict (id) do nothing;
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values
('99500000-0000-4000-8000-000000000100','{"line1":"10 Customer Road","latitude":15.7,"longitude":80.7}','{"name":"Shared-code Recipient","phoneNumber":"+919959999999"}',extensions.digest('normal','sha256')),
('99500000-0000-4000-8000-000000000101','{"line1":"11 Customer Road","latitude":15.71,"longitude":80.71}','{"name":"Buyer","phoneNumber":"+919950000002"}',extensions.digest('missing','sha256')),
('99500000-0000-4000-8000-000000000102','{"line1":"12 Customer Road","latitude":15.72,"longitude":80.72}','{"name":"Buyer","phoneNumber":"+919950000002"}',extensions.digest('override','sha256'))
on conflict (order_id) do nothing;
insert into dastak_v1.order_price_snapshots (
  order_id, snapshot_kind, subtotal_paise, total_paise
) values
('99500000-0000-4000-8000-000000000100','FINAL',900,900),
('99500000-0000-4000-8000-000000000101','FINAL',900,900),
('99500000-0000-4000-8000-000000000102','FINAL',900,900)
on conflict (order_id,snapshot_kind) do nothing;
insert into dastak_v1.order_lines (
  id, order_id, line_type, sku_id, product_name_snapshot,
  pack_size_snapshot, quantity, unit_price_paise, status
) values
('99500000-0000-4000-8000-000000000110','99500000-0000-4000-8000-000000000100','RETAIL_SKU','99500000-0000-4000-8000-000000000014','Step 4B Product','1 unit',1,900,'FULFILLING'),
('99500000-0000-4000-8000-000000000111','99500000-0000-4000-8000-000000000101','RETAIL_SKU','99500000-0000-4000-8000-000000000014','Step 4B Product','1 unit',1,900,'FULFILLING'),
('99500000-0000-4000-8000-000000000112','99500000-0000-4000-8000-000000000102','RETAIL_SKU','99500000-0000-4000-8000-000000000014','Step 4B Product','1 unit',1,900,'FULFILLING')
on conflict (id) do nothing;

insert into dastak_v1.matching_attempts (
  id, order_id, wave, status, started_at, expires_at, closed_at
) values
('99500000-0000-4000-8000-000000000120','99500000-0000-4000-8000-000000000100','WAVE_1','EXPIRED',now()-interval '30 minutes',now()-interval '27 minutes',now()-interval '27 minutes'),
('99500000-0000-4000-8000-000000000121','99500000-0000-4000-8000-000000000101','WAVE_1','EXPIRED',now()-interval '30 minutes',now()-interval '27 minutes',now()-interval '27 minutes'),
('99500000-0000-4000-8000-000000000122','99500000-0000-4000-8000-000000000102','WAVE_1','EXPIRED',now()-interval '30 minutes',now()-interval '27 minutes',now()-interval '27 minutes')
on conflict (id) do nothing;
insert into dastak_v1.merchant_opportunities (
  id, matching_attempt_id, order_id, organization_id, branch_id,
  wave, status, started_at, expires_at
) values
('99500000-0000-4000-8000-000000000130','99500000-0000-4000-8000-000000000120','99500000-0000-4000-8000-000000000100','99500000-0000-4000-8000-000000000010','99500000-0000-4000-8000-000000000011','WAVE_1','LOST',now()-interval '30 minutes',now()-interval '27 minutes'),
('99500000-0000-4000-8000-000000000131','99500000-0000-4000-8000-000000000121','99500000-0000-4000-8000-000000000101','99500000-0000-4000-8000-000000000010','99500000-0000-4000-8000-000000000011','WAVE_1','LOST',now()-interval '30 minutes',now()-interval '27 minutes'),
('99500000-0000-4000-8000-000000000132','99500000-0000-4000-8000-000000000122','99500000-0000-4000-8000-000000000102','99500000-0000-4000-8000-000000000010','99500000-0000-4000-8000-000000000011','WAVE_1','LOST',now()-interval '30 minutes',now()-interval '27 minutes')
on conflict (id) do nothing;
insert into dastak_v1.fulfilments (
  id, order_id, organization_id, branch_id, source_opportunity_id,
  fulfilment_type, status, promised_prep_minutes, committed_at,
  prep_started_at, estimated_ready_at, ready_at, actual_ready_at, package_count
) values
('99500000-0000-4000-8000-000000000140','99500000-0000-4000-8000-000000000100','99500000-0000-4000-8000-000000000010','99500000-0000-4000-8000-000000000011','99500000-0000-4000-8000-000000000130','RETAIL','PICKED_UP',10,now()-interval '25 minutes',now()-interval '20 minutes',now()-interval '10 minutes',now()-interval '12 minutes',now()-interval '12 minutes',2),
('99500000-0000-4000-8000-000000000141','99500000-0000-4000-8000-000000000101','99500000-0000-4000-8000-000000000010','99500000-0000-4000-8000-000000000011','99500000-0000-4000-8000-000000000131','RETAIL','PICKED_UP',10,now()-interval '25 minutes',now()-interval '20 minutes',now()-interval '10 minutes',now()-interval '12 minutes',now()-interval '12 minutes',1),
('99500000-0000-4000-8000-000000000142','99500000-0000-4000-8000-000000000102','99500000-0000-4000-8000-000000000010','99500000-0000-4000-8000-000000000011','99500000-0000-4000-8000-000000000132','RETAIL','PICKED_UP',10,now()-interval '25 minutes',now()-interval '20 minutes',now()-interval '10 minutes',now()-interval '12 minutes',now()-interval '12 minutes',2)
on conflict (id) do nothing;
insert into dastak_v1.fulfilment_lines (fulfilment_id,order_line_id,confirmed_quantity) values
('99500000-0000-4000-8000-000000000140','99500000-0000-4000-8000-000000000110',1),
('99500000-0000-4000-8000-000000000141','99500000-0000-4000-8000-000000000111',1),
('99500000-0000-4000-8000-000000000142','99500000-0000-4000-8000-000000000112',1)
on conflict do nothing;

insert into dastak_v1.packages (
  id, order_id, fulfilment_id, package_number, status,
  current_custody_owner_type, current_custody_owner_id, declared_by,
  declared_at, ready_at, picked_up_at
) values
('99500000-0000-4000-8000-000000000150','99500000-0000-4000-8000-000000000100','99500000-0000-4000-8000-000000000140',1,'PICKED_UP','RIDER','99500000-0000-4000-8000-000000000003','99500000-0000-4000-8000-000000000006',now()-interval '15 minutes',now()-interval '12 minutes',now()-interval '5 minutes'),
('99500000-0000-4000-8000-000000000151','99500000-0000-4000-8000-000000000100','99500000-0000-4000-8000-000000000140',2,'PICKED_UP','RIDER','99500000-0000-4000-8000-000000000003','99500000-0000-4000-8000-000000000006',now()-interval '15 minutes',now()-interval '12 minutes',now()-interval '5 minutes'),
('99500000-0000-4000-8000-000000000152','99500000-0000-4000-8000-000000000101','99500000-0000-4000-8000-000000000141',1,'READY','MERCHANT_BRANCH','99500000-0000-4000-8000-000000000011','99500000-0000-4000-8000-000000000006',now()-interval '15 minutes',now()-interval '12 minutes',null),
('99500000-0000-4000-8000-000000000153','99500000-0000-4000-8000-000000000102','99500000-0000-4000-8000-000000000142',1,'PICKED_UP','RIDER','99500000-0000-4000-8000-000000000007','99500000-0000-4000-8000-000000000006',now()-interval '15 minutes',now()-interval '12 minutes',now()-interval '5 minutes'),
('99500000-0000-4000-8000-000000000154','99500000-0000-4000-8000-000000000102','99500000-0000-4000-8000-000000000142',2,'PICKED_UP','RIDER','99500000-0000-4000-8000-000000000007','99500000-0000-4000-8000-000000000006',now()-interval '15 minutes',now()-interval '12 minutes',now()-interval '5 minutes')
on conflict (id) do nothing;

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values (
  '99500000-0000-4000-8000-000000000301',
  'settlement.rider_distance_payout','GLOBAL',
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}',
  '99500000-0000-4000-8000-000000000001','Step 4B rider payout fixture.'
) on conflict do nothing;

insert into dastak_v1.delivery_missions (
  id, order_id, status, assigned_rider_id, assigned_transport_type,
  transport_snapshot, pickup_count, search_started_at, assigned_at,
  first_package_picked_up_at, all_packages_picked_up_at, version
) values
('99500000-0000-4000-8000-000000000200','99500000-0000-4000-8000-000000000100','ALL_PACKAGES_PICKED_UP','99500000-0000-4000-8000-000000000003','MOTORBIKE','{"feasible":true,"eligibleTransportTypes":["MOTORBIKE"]}',1,now()-interval '15 minutes',now()-interval '10 minutes',now()-interval '5 minutes',now()-interval '4 minutes',5),
('99500000-0000-4000-8000-000000000201','99500000-0000-4000-8000-000000000101','ALL_PACKAGES_PICKED_UP','99500000-0000-4000-8000-000000000004','MOTORBIKE','{"feasible":true,"eligibleTransportTypes":["MOTORBIKE"]}',1,now()-interval '15 minutes',now()-interval '10 minutes',now()-interval '5 minutes',now()-interval '4 minutes',5),
('99500000-0000-4000-8000-000000000202','99500000-0000-4000-8000-000000000102','ALL_PACKAGES_PICKED_UP','99500000-0000-4000-8000-000000000007','MOTORBIKE','{"feasible":true,"eligibleTransportTypes":["MOTORBIKE"]}',1,now()-interval '15 minutes',now()-interval '10 minutes',now()-interval '5 minutes',now()-interval '4 minutes',5)
on conflict (id) do nothing;
insert into dastak_v1.delivery_stops (
  id, mission_id, order_id, fulfilment_id, branch_id, stop_sequence,
  status, declared_package_count, arrived_at, completed_at, waiting_seconds
) values
('99500000-0000-4000-8000-000000000210','99500000-0000-4000-8000-000000000200','99500000-0000-4000-8000-000000000100','99500000-0000-4000-8000-000000000140','99500000-0000-4000-8000-000000000011',1,'COMPLETED',2,now()-interval '6 minutes',now()-interval '5 minutes',60),
('99500000-0000-4000-8000-000000000211','99500000-0000-4000-8000-000000000201','99500000-0000-4000-8000-000000000101','99500000-0000-4000-8000-000000000141','99500000-0000-4000-8000-000000000011',1,'COMPLETED',1,now()-interval '6 minutes',now()-interval '5 minutes',60),
('99500000-0000-4000-8000-000000000212','99500000-0000-4000-8000-000000000202','99500000-0000-4000-8000-000000000102','99500000-0000-4000-8000-000000000142','99500000-0000-4000-8000-000000000011',1,'COMPLETED',2,now()-interval '6 minutes',now()-interval '5 minutes',60)
on conflict (id) do nothing;

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values (
  '99500000-0000-4000-8000-000000000300',
  'delivery.verification_invalid_attempt_limit','GLOBAL','3',
  '99500000-0000-4000-8000-000000000001','Step 4B runtime verification threshold.'
) on conflict do nothing;
commit;
SQL

call_final() {
  local rider="$1" mission="$2" action="$3" object_path="$4" code="$5" key="$6" digest="$7"
  local object_sql='null' code_sql='null'
  if [[ -n "$object_path" ]]; then object_sql="'$object_path'::text"; fi
  if [[ -n "$code" ]]; then code_sql="'$code'::text"; fi
  "${psql_base[@]}" -At -F '|' -c "
    select response_status,coalesce(response_body->'error'->>'code','OK')
    from public.dastak_v1_advance_final_delivery(
      '$rider'::uuid,'$mission'::uuid,'$action',
      $object_sql,
      $code_sql,
      '$key','$digest'
    )"
}

actor_override() {
  local actor="$1" mission="$2" evidence="$3" reason="$4" version="$5" key="$6"
  "${psql_base[@]}" -At -c "
    begin;
    select pg_catalog.set_config('request.jwt.claim.sub','$actor',true);
    select public.dastak_v1_authorize_exceptional_delivery_handoff(
      '$mission'::uuid,'$evidence'::uuid,'$reason',$version,'$key'
    );
    commit;"
}

pre_projection="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_json('$order_normal'::uuid,'$customer_id'::uuid)::text")"
[[ "$pre_projection" != *'deliveryCode'* ]] || { printf 'final code leaked before final-delivery stage\n' >&2; exit 1; }
pre_handoff="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.verification_handoffs where order_id='$order_normal'::uuid and handoff_type='RIDER_TO_CUSTOMER'")"
[[ "$pre_handoff" == "0" ]] || { printf 'final handoff activated before final delivery\n' >&2; exit 1; }

missing_result="$(call_final "$wrong_rider_id" "$mission_missing" START_FINAL_DELIVERY '' '' "missing-$run_token" missing)"
[[ "$missing_result" == "409|final_delivery_incomplete_custody" ]] || { printf 'missing package did not block final delivery: %s\n' "$missing_result" >&2; exit 1; }

start_result="$(call_final "$rider_id" "$mission_normal" START_FINAL_DELIVERY '' '' "start-normal-$run_token" start-normal)"
[[ "$start_result" == "200|OK" ]] || { printf 'normal final delivery did not start: %s\n' "$start_result" >&2; exit 1; }
normal_code="$("${psql_base[@]}" -Atc "select private.dastak_v1_handoff_code(id,handoff_type,code_version) from dastak_v1.verification_handoffs where order_id='$order_normal'::uuid and handoff_type='RIDER_TO_CUSTOMER'")"
[[ "$normal_code" =~ ^[0-9]{6}$ ]] || { printf 'active final code was unavailable\n' >&2; exit 1; }
active_projection="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_json('$order_normal'::uuid,'$customer_id'::uuid)::text")"
[[ "$active_projection" == *'ON_THE_WAY'* && "$active_projection" == *"$normal_code"* ]] || { printf 'customer did not receive active in-app delivery code\n' >&2; exit 1; }
[[ "$active_projection" != *'Hidden Final Delivery Branch'* && "$active_projection" != *"$branch_id"* ]] || { printf 'customer projection leaked retail merchant identity\n' >&2; exit 1; }

wrong_rider="$(call_final "$wrong_rider_id" "$mission_normal" ARRIVE_CUSTOMER '' '' "wrong-rider-$run_token" wrong-rider)"
[[ "$wrong_rider" == "404|mission_not_found" ]] || { printf 'wrong rider was not rejected: %s\n' "$wrong_rider" >&2; exit 1; }
arrive_result="$(call_final "$rider_id" "$mission_normal" ARRIVE_CUSTOMER '' '' "arrive-normal-$run_token" arrive-normal)"
[[ "$arrive_result" == "200|OK" ]] || { printf 'customer arrival failed: %s\n' "$arrive_result" >&2; exit 1; }
missing_photo="$(call_final "$rider_id" "$mission_normal" VERIFY_DELIVERY '' "$normal_code" "photo-required-$run_token" photo-required)"
[[ "$missing_photo" == "409|delivery_evidence_required" ]] || { printf 'delivery succeeded without rider photo: %s\n' "$missing_photo" >&2; exit 1; }

normal_path="rider-delivery/$rider_id/99500000-0000-4000-8000-000000000401.jpg"
"${psql_base[@]}" -c "insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('dastak-evidence','$normal_path','$rider_id'::uuid,'$rider_id','{\"mimetype\":\"image/jpeg\",\"size\":2048}')" >/dev/null
photo_result="$(call_final "$rider_id" "$mission_normal" ADD_DELIVERY_EVIDENCE "$normal_path" '' "photo-normal-$run_token" photo-normal)"
[[ "$photo_result" == "200|OK" ]] || { printf 'rider evidence capture failed: %s\n' "$photo_result" >&2; exit 1; }
wrong_code="$(call_final "$rider_id" "$mission_normal" VERIFY_DELIVERY '' 000000 "wrong-normal-$run_token" wrong-normal)"
[[ "$wrong_code" == "409|delivery_code_invalid" ]] || { printf 'wrong delivery code was not rejected: %s\n' "$wrong_code" >&2; exit 1; }

verify_sql_a="select response_status from public.dastak_v1_advance_final_delivery('$rider_id'::uuid,'$mission_normal'::uuid,'VERIFY_DELIVERY',null,'$normal_code','verify-normal-a-$run_token','verify-normal-a')"
verify_sql_b="select response_status from public.dastak_v1_advance_final_delivery('$rider_id'::uuid,'$mission_normal'::uuid,'VERIFY_DELIVERY',null,'$normal_code','verify-normal-b-$run_token','verify-normal-b')"
"${psql_base[@]}" -At -c "$verify_sql_a" >"$work_dir/verify-a.out" & verify_a_pid=$!
"${psql_base[@]}" -At -c "$verify_sql_b" >"$work_dir/verify-b.out" & verify_b_pid=$!
wait "$verify_a_pid"; wait "$verify_b_pid"
verify_statuses="$(sort "$work_dir/verify-a.out" "$work_dir/verify-b.out" | tr '\n' ' ' | sed 's/ $//')"
[[ "$verify_statuses" == "200 409" ]] || { printf 'competing final-delivery attempts were not serialized: %s\n' "$verify_statuses" >&2; exit 1; }
normal_truth="$("${psql_base[@]}" -At -F ' ' -c "
select
  (select count(*) from dastak_v1.orders where id='$order_normal'::uuid and status='DELIVERED' and delivered_at is not null),
  (select count(*) from dastak_v1.delivery_missions where id='$mission_normal'::uuid and status='DELIVERED' and delivered_at is not null),
  (select count(*) from dastak_v1.verification_handoffs where order_id='$order_normal'::uuid and handoff_type='RIDER_TO_CUSTOMER' and status='CONSUMED'),
  (select count(*) from dastak_v1.packages where order_id='$order_normal'::uuid and status='DELIVERED' and current_custody_owner_type='CUSTOMER' and current_custody_owner_id='$customer_id'::uuid),
  (select count(*) from dastak_v1.package_custody_events where order_id='$order_normal'::uuid and to_owner_type='CUSTOMER'),
  (select count(*) from dastak_v1.fulfilments where order_id='$order_normal'::uuid and status='COMPLETED'),
  (select count(*) from dastak_v1.order_lines where order_id='$order_normal'::uuid and status='FULFILLED')")"
[[ "$normal_truth" == "1 1 1 2 2 1 1" ]] || { printf 'atomic normal delivery truth failed: %s\n' "$normal_truth" >&2; exit 1; }
replay="$(call_final "$rider_id" "$mission_normal" VERIFY_DELIVERY '' "$normal_code" "replay-normal-$run_token" replay-normal)"
[[ "$replay" == "409|delivery_code_consumed" || "$replay" == "409|invalid_final_delivery_state" ]] || { printf 'consumed final code replay was unsafe: %s\n' "$replay" >&2; exit 1; }
post_replay="$("${psql_base[@]}" -At -F ' ' -c "select count(*),(select count(*) from dastak_v1.package_custody_events where order_id='$order_normal'::uuid and to_owner_type='CUSTOMER') from dastak_v1.packages where order_id='$order_normal'::uuid and status='DELIVERED'")"
[[ "$post_replay" == "2 2" ]] || { printf 'delivery replay duplicated custody\n' >&2; exit 1; }
delivered_projection="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_json('$order_normal'::uuid,'$customer_id'::uuid)::text")"
[[ "$delivered_projection" == *'DELIVERED'* && "$delivered_projection" != *"$normal_code"* && "$delivered_projection" != *'Hidden Final Delivery Branch'* ]] || { printf 'delivered customer projection was unsafe\n' >&2; exit 1; }
recipient_account_count="$("${psql_base[@]}" -Atc "select count(*) from public.accounts where phone_number='+919959999999'")"
[[ "$recipient_account_count" == "0" ]] || { printf 'shared-code recipient unexpectedly required an account\n' >&2; exit 1; }

start_override="$(call_final "$override_rider_id" "$mission_override" START_FINAL_DELIVERY '' '' "start-override-$run_token" start-override)"
arrive_override="$(call_final "$override_rider_id" "$mission_override" ARRIVE_CUSTOMER '' '' "arrive-override-$run_token" arrive-override)"
[[ "$start_override $arrive_override" == "200|OK 200|OK" ]] || { printf 'override mission setup failed: %s %s\n' "$start_override" "$arrive_override" >&2; exit 1; }
override_path="rider-delivery/$override_rider_id/99500000-0000-4000-8000-000000000402.jpg"
"${psql_base[@]}" -c "insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('dastak-evidence','$override_path','$override_rider_id'::uuid,'$override_rider_id','{\"mimetype\":\"image/jpeg\",\"size\":2048}')" >/dev/null
override_photo="$(call_final "$override_rider_id" "$mission_override" ADD_DELIVERY_EVIDENCE "$override_path" '' "photo-override-$run_token" photo-override)"
[[ "$override_photo" == "200|OK" ]] || { printf 'override evidence capture failed: %s\n' "$override_photo" >&2; exit 1; }
for attempt in 1 2 3; do
  blocked_result="$(call_final "$override_rider_id" "$mission_override" VERIFY_DELIVERY '' 999999 "block-$attempt-$run_token" "block-$attempt")"
done
[[ "$blocked_result" == "409|delivery_code_blocked" ]] || { printf 'invalid-attempt threshold did not block: %s\n' "$blocked_result" >&2; exit 1; }
override_code="$("${psql_base[@]}" -Atc "select private.dastak_v1_handoff_code(id,handoff_type,code_version) from dastak_v1.verification_handoffs where order_id='$order_override'::uuid and handoff_type='RIDER_TO_CUSTOMER'")"
blocked_valid="$(call_final "$override_rider_id" "$mission_override" VERIFY_DELIVERY '' "$override_code" "blocked-valid-$run_token" blocked-valid)"
[[ "$blocked_valid" == "409|delivery_code_blocked" ]] || { printf 'blocked code accepted a later valid attempt: %s\n' "$blocked_valid" >&2; exit 1; }
override_evidence_id="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_evidence where mission_id='$mission_override'::uuid")"
override_version="$("${psql_base[@]}" -Atc "select version from dastak_v1.delivery_missions where id='$mission_override'::uuid")"
if actor_override "$unauthorized_id" "$mission_override" "$override_evidence_id" 'Unauthorized actor attempted exceptional handoff.' "$override_version" "unauthorized-$run_token" >"$work_dir/unauthorized.out" 2>&1; then
  printf 'unauthorized exceptional handoff unexpectedly succeeded\n' >&2; exit 1
fi
grep -Eq 'platform permission required|permission denied' "$work_dir/unauthorized.out"
actor_override "$owner_id" "$mission_override" "$override_evidence_id" 'Operations reviewed rider evidence and authorized recipient handoff.' "$override_version" "authorized-$run_token" >"$work_dir/authorized.out"
override_truth="$("${psql_base[@]}" -At -F ' ' -c "
select
  (select count(*) from dastak_v1.verification_handoffs where order_id='$order_override'::uuid and handoff_type='RIDER_TO_CUSTOMER' and status='OVERRIDDEN' and consumed_at is null and consumed_by is null and overridden_by='$owner_id'::uuid),
  (select count(*) from dastak_v1.exceptional_handoff_authorizations where order_id='$order_override'::uuid and delivery_evidence_id='$override_evidence_id'::uuid and authorized_by='$owner_id'::uuid),
  (select count(*) from dastak_v1.orders where id='$order_override'::uuid and status='DELIVERED'),
  (select count(*) from dastak_v1.packages where order_id='$order_override'::uuid and status='DELIVERED' and current_custody_owner_type='CUSTOMER'),
  (select count(*) from dastak_v1.audit_events where resource_id='$order_override'::uuid and action='DELIVERY_HANDOFF_OVERRIDDEN')")"
[[ "$override_truth" == "1 1 1 2 1" ]] || { printf 'authorized OVERRIDDEN truth failed: %s\n' "$override_truth" >&2; exit 1; }

printf 'Dastak V1 final-delivery evidence, verification, override and custody races passed.\n'
