#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-restaurant-e2e.XXXXXX")"
run_token="$(date +%s)$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
owner_id='99800000-0000-4000-8000-000000000002'
customer_id='99800000-0000-4000-8000-000000000001'
merchant_id='99800000-0000-4000-8000-000000000003'
rider_id='99800000-0000-4000-8000-000000000004'
mixed_rider_id='99800000-0000-4000-8000-000000000005'
zone_id='99800000-0000-4000-8000-000000000010'
restaurant_branch='99800000-0000-4000-8000-000000000021'
retail_branch='99800000-0000-4000-8000-000000000031'

if [[ "$("${psql_base[@]}" -Atc "select count(*) from public.accounts where id='$customer_id'::uuid")" == "0" ]]; then
  "$(dirname "$0")/test-v1-restaurant-concurrency.sh" >/dev/null
fi

food_order="$("${psql_base[@]}" -Atc "
  select id from dastak_v1.orders
  where customer_id='$customer_id'::uuid and order_type='FOOD_ONLY' and status='PREPARING'
    and exists (select 1 from dastak_v1.fulfilments where order_id=orders.id and status='READY')
  order by created_at limit 1")"
mixed_order="$("${psql_base[@]}" -Atc "
  select id from dastak_v1.orders
  where customer_id='$customer_id'::uuid and order_type='MIXED' and status='PREPARING'
  order by created_at limit 1")"

if [[ -z "$food_order" || -z "$mixed_order" ]]; then
  delivered_food="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.orders where customer_id='$customer_id'::uuid and order_type='FOOD_ONLY' and status='DELIVERED'")"
  delivered_mixed="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.orders where customer_id='$customer_id'::uuid and order_type='MIXED' and status='DELIVERED'")"
  if [[ "$delivered_food" -ge 1 && "$delivered_mixed" -ge 1 ]]; then
    printf 'Restaurant-only and mixed Food + Retail end-to-end gates already passed.\n'
    exit 0
  fi
  printf 'Restaurant E2E requires the committed Restaurant runtime fixture. Reset the local database and rerun.\n' >&2
  exit 1
fi

"${psql_base[@]}" <<'SQL'
begin;
insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,
  email_confirmed_at,created_at,updated_at
) values (
  '99800000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'restaurant-e2e-rider@example.test','',now(),now(),now()
) , (
  '99800000-0000-4000-8000-000000000005',
  '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'restaurant-mixed-e2e-rider@example.test','',now(),now(),now()
) on conflict (id) do nothing;
insert into public.accounts(id,display_name,phone_number) values
  ('99800000-0000-4000-8000-000000000004','Restaurant E2E Rider','+919980000004'),
  ('99800000-0000-4000-8000-000000000005','Restaurant Mixed E2E Rider','+919980000005')
on conflict (id) do nothing;
insert into private.account_memberships(account_id,role,approved_at) values
  ('99800000-0000-4000-8000-000000000004','dastak_partner',now()),
  ('99800000-0000-4000-8000-000000000005','dastak_partner',now())
on conflict (account_id,role) do update set approved_at=excluded.approved_at;
insert into private.delivery_partner_applications (
  id,account_id,delivery_method,identity_evidence_object_path,
  verification_version,vehicle_registration_number,vehicle_make_model,
  vehicle_evidence_object_path,status,submitted_at,reviewed_at,reviewed_by
) values (
  '99800000-0000-4000-8000-000000000084',
  '99800000-0000-4000-8000-000000000004','motorbike',
  'dastak-partner/99800000-0000-4000-8000-000000000004/identity.pdf',2,
  'TN 23 V1 0001','Restaurant E2E Motorbike',
  'dastak-partner/99800000-0000-4000-8000-000000000004/vehicle.pdf',
  'approved',now(),now(),'99800000-0000-4000-8000-000000000002'
) , (
  '99800000-0000-4000-8000-000000000085',
  '99800000-0000-4000-8000-000000000005','motorbike',
  'dastak-partner/99800000-0000-4000-8000-000000000005/identity.pdf',2,
  'TN 23 V1 0002','Restaurant Mixed E2E Motorbike',
  'dastak-partner/99800000-0000-4000-8000-000000000005/vehicle.pdf',
  'approved',now(),now(),'99800000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;
insert into private.delivery_partner_profiles(
  account_id,approved_application_id,delivery_method
) values
  ('99800000-0000-4000-8000-000000000004',
   '99800000-0000-4000-8000-000000000084','motorbike'),
  ('99800000-0000-4000-8000-000000000005',
   '99800000-0000-4000-8000-000000000085','motorbike')
on conflict (account_id) do update set delivery_method=excluded.delivery_method;
insert into private.delivery_partner_availability(
  account_id,status,location,service_zone_id,last_seen_at,available_until
) values
  ('99800000-0000-4000-8000-000000000004','online',
   extensions.st_setsrid(extensions.st_makepoint(78.6201,12.6800),4326),
   '99800000-0000-4000-8000-000000000010',now(),now()+interval '4 hours'),
  ('99800000-0000-4000-8000-000000000005','online',
   extensions.st_setsrid(extensions.st_makepoint(78.6202,12.6801),4326),
   '99800000-0000-4000-8000-000000000010',now(),now()+interval '4 hours')
on conflict (account_id) do update set status='online',location=excluded.location,
  service_zone_id=excluded.service_zone_id,last_seen_at=excluded.last_seen_at,
  available_until=excluded.available_until,
  state_version=private.delivery_partner_availability.state_version+1;
commit;
SQL

configure_setting() {
  local key="$1" value="$2" id="$3"
  "${psql_base[@]}" -v key="$key" -v value="$value" -v id="$id" \
    -v owner_id="$owner_id" <<'SQL' >/dev/null
update dastak_v1.platform_settings
set setting_value=:'value'::jsonb,updated_by=:'owner_id'::uuid,
    update_reason='Restaurant E2E runtime configuration.',version=version+1
where setting_key=:'key' and scope_type='GLOBAL' and scope_id is null;
insert into dastak_v1.platform_settings(
  id,setting_key,scope_type,setting_value,updated_by,update_reason
)
select :'id'::uuid,:'key','GLOBAL',:'value'::jsonb,:'owner_id'::uuid,
  'Restaurant E2E runtime configuration.'
where not exists (
  select 1 from dastak_v1.platform_settings
  where setting_key=:'key' and scope_type='GLOBAL' and scope_id is null
);
SQL
}

configure_setting 'delivery.rider_initial_pool_size' '3' '99800000-0000-4000-8000-000000000070'
configure_setting 'delivery.rider_offer_timeout_seconds' '30' '99800000-0000-4000-8000-000000000071'
configure_setting 'delivery.rider_pool_expansion' '{"initialRadiusMeters":3000,"radiusStepMeters":3000,"additionalRidersPerRound":3,"maximumRounds":4}' '99800000-0000-4000-8000-000000000072'
configure_setting 'delivery.verification_invalid_attempt_limit' '5' '99800000-0000-4000-8000-000000000073'
configure_setting 'settlement.rider_distance_payout' '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}' '99800000-0000-4000-8000-000000000074'

merchant_call() {
  local sql="$1"
  "${psql_base[@]}" -v actor_id="$merchant_id" <<SQL >/dev/null
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'actor_id', true);
$sql
commit;
SQL
}

ready_fulfilment() {
  local fulfilment_id="$1" evidence_uuid="$2" key_prefix="$3" version path
  version="$("${psql_base[@]}" -Atc "select version from dastak_v1.fulfilments where id='$fulfilment_id'::uuid")"
  path="merchant-ready/$merchant_id/$evidence_uuid.jpg"
  "${psql_base[@]}" -c "insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('dastak-evidence','$path','$merchant_id'::uuid,'$merchant_id','{\"mimetype\":\"image/jpeg\",\"size\":2048}') on conflict do nothing" >/dev/null
  merchant_call "select public.dastak_v1_declare_fulfilment_packages('$fulfilment_id'::uuid,'$key_prefix-packages-$run_token',$version,1);"
  version=$((version+1))
  merchant_call "select public.dastak_v1_add_fulfilment_ready_evidence('$fulfilment_id'::uuid,null,'$path','$key_prefix-evidence-$run_token',$version);"
  version=$((version+1))
  merchant_call "select public.dastak_v1_mark_fulfilment_ready('$fulfilment_id'::uuid,'$key_prefix-ready-$run_token',$version);"
}

while IFS= read -r fulfilment_id; do
  fulfilment_type="$("${psql_base[@]}" -Atc "select fulfilment_type from dastak_v1.fulfilments where id='$fulfilment_id'::uuid")"
  if [[ "$fulfilment_type" == 'FOOD' ]]; then
    ready_fulfilment "$fulfilment_id" '99800000-0000-4000-8000-000000000094' 'mixed-food'
  else
    ready_fulfilment "$fulfilment_id" '99800000-0000-4000-8000-000000000095' 'mixed-retail'
  fi
done < <("${psql_base[@]}" -Atc "select id from dastak_v1.fulfilments where order_id='$mixed_order'::uuid and status='PREPARING' order by fulfilment_type")

deliver_order() {
  local order_id="$1" label="$2" photo_uuid="$3" rider_account_id="$4"
  local mission_id offer_id stop_id package_count pickup_code final_code photo_path result
  mission_id="$("${psql_base[@]}" -Atc "select dastak_v1_api.ensure_delivery_mission('$order_id'::uuid)" | tail -n 1)"
  offer_id="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_id'::uuid and rider_id='$rider_account_id'::uuid and status='OFFERED'")"
  if [[ -z "$offer_id" ]]; then
    "${psql_base[@]}" -c "select dastak_v1_api.expand_rider_pool_if_due('$mission_id'::uuid,greatest(pg_catalog.clock_timestamp(),(select updated_at + interval '31 seconds' from dastak_v1.delivery_missions where id='$mission_id'::uuid)))" >/dev/null
    offer_id="$("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_offers where mission_id='$mission_id'::uuid and rider_id='$rider_account_id'::uuid and status='OFFERED'")"
  fi
  [[ -n "$mission_id" && -n "$offer_id" ]] || {
    printf '%s did not create a rider offer.\n' "$label" >&2; exit 1;
  }
  result="$("${psql_base[@]}" -At -F '|' -c "select response_status,coalesce(response_body->'error'->>'code','OK') from public.dastak_v1_accept_delivery_offer('$rider_account_id'::uuid,'$offer_id'::uuid,'$label-accept-$run_token','$label-accept')")"
  [[ "$result" == '200|OK' ]] || { printf '%s rider acceptance failed: %s\n' "$label" "$result" >&2; exit 1; }
  "${psql_base[@]}" -c "select * from public.dastak_v1_advance_delivery_mission('$rider_account_id'::uuid,'$mission_id'::uuid,'START_PICKUPS',null,null,null,null,'$label-start-$run_token','$label-start')" >/dev/null
  while IFS= read -r stop_id; do
    package_count="$("${psql_base[@]}" -Atc "select declared_package_count from dastak_v1.delivery_stops where id='$stop_id'::uuid")"
    pickup_code="$("${psql_base[@]}" -Atc "select private.dastak_v1_handoff_code(id,handoff_type,code_version) from dastak_v1.verification_handoffs where mission_id='$mission_id'::uuid and fulfilment_id=(select fulfilment_id from dastak_v1.delivery_stops where id='$stop_id'::uuid)")"
    result="$("${psql_base[@]}" -At -F '|' -c "select response_status,coalesce(response_body->'error'->>'code','OK') from public.dastak_v1_advance_delivery_mission('$rider_account_id'::uuid,'$mission_id'::uuid,'VERIFY_PICKUP','$stop_id'::uuid,$package_count,'$pickup_code',null,'$label-pickup-$stop_id','$label-pickup')")"
    [[ "$result" == '200|OK' ]] || { printf '%s pickup failed: %s\n' "$label" "$result" >&2; exit 1; }
  done < <("${psql_base[@]}" -Atc "select id from dastak_v1.delivery_stops where mission_id='$mission_id'::uuid order by stop_sequence")
  result="$("${psql_base[@]}" -At -F '|' -c "select response_status,coalesce(response_body->'error'->>'code','OK') from public.dastak_v1_advance_final_delivery('$rider_account_id'::uuid,'$mission_id'::uuid,'START_FINAL_DELIVERY',null,null,'$label-final-$run_token','$label-final')")"
  [[ "$result" == '200|OK' ]] || { printf '%s final delivery start failed: %s\n' "$label" "$result" >&2; exit 1; }
  "${psql_base[@]}" -c "select * from public.dastak_v1_advance_final_delivery('$rider_account_id'::uuid,'$mission_id'::uuid,'ARRIVE_CUSTOMER',null,null,'$label-arrive-$run_token','$label-arrive')" >/dev/null
  photo_path="rider-delivery/$rider_account_id/$photo_uuid.jpg"
  "${psql_base[@]}" -c "insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('dastak-evidence','$photo_path','$rider_account_id'::uuid,'$rider_account_id','{\"mimetype\":\"image/jpeg\",\"size\":2048}') on conflict do nothing" >/dev/null
  "${psql_base[@]}" -c "select * from public.dastak_v1_advance_final_delivery('$rider_account_id'::uuid,'$mission_id'::uuid,'ADD_DELIVERY_EVIDENCE','$photo_path',null,'$label-photo-$run_token','$label-photo')" >/dev/null
  final_code="$("${psql_base[@]}" -Atc "select private.dastak_v1_handoff_code(id,handoff_type,code_version) from dastak_v1.verification_handoffs where order_id='$order_id'::uuid and handoff_type='RIDER_TO_CUSTOMER'")"
  result="$("${psql_base[@]}" -At -F '|' -c "select response_status,coalesce(response_body->'error'->>'code','OK') from public.dastak_v1_advance_final_delivery('$rider_account_id'::uuid,'$mission_id'::uuid,'VERIFY_DELIVERY',null,'$final_code','$label-deliver-$run_token','$label-deliver')")"
  [[ "$result" == '200|OK' ]] || { printf '%s final verification failed: %s\n' "$label" "$result" >&2; exit 1; }
}

deliver_order "$food_order" 'restaurant-only' '99800000-0000-4000-8000-000000000096' "$rider_id"
deliver_order "$mixed_order" 'restaurant-mixed' '99800000-0000-4000-8000-000000000097' "$mixed_rider_id"

food_truth="$("${psql_base[@]}" -At -F '|' -c "
select customer_order.status::text,
  (select count(*) from dastak_v1.packages where order_id=customer_order.id and status='DELIVERED' and current_custody_owner_type='CUSTOMER'),
  (select count(*) from dastak_v1.settlement_entries where order_id=customer_order.id and subject_type='MERCHANT_ORGANIZATION' and status='ELIGIBLE' and amount_paise=7000),
  (select count(*) from dastak_v1.restaurant_capacity_commitments where order_id=customer_order.id and status='RELEASED')
from dastak_v1.orders customer_order where customer_order.id='$food_order'::uuid")"
[[ "$food_truth" == 'DELIVERED|1|1|1' ]] || { printf 'Restaurant-only completion truth failed: %s\n' "$food_truth" >&2; exit 1; }

mixed_truth="$("${psql_base[@]}" -At -F '|' -c "
select customer_order.status::text,
  (select count(*) from dastak_v1.fulfilments where order_id=customer_order.id and status='COMPLETED'),
  (select count(*) from dastak_v1.packages where order_id=customer_order.id and status='DELIVERED' and current_custody_owner_type='CUSTOMER'),
  (select count(*) from dastak_v1.settlement_entries where order_id=customer_order.id and subject_type='MERCHANT_ORGANIZATION' and status='ELIGIBLE'),
  (select count(*) from dastak_v1.settlement_entries where order_id=customer_order.id and subject_type='RIDER' and status='ELIGIBLE')
from dastak_v1.orders customer_order where customer_order.id='$mixed_order'::uuid")"
[[ "$mixed_truth" == 'DELIVERED|2|2|2|1' ]] || { printf 'Mixed Food + Retail completion truth failed: %s\n' "$mixed_truth" >&2; exit 1; }

customer_projection="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_json('$mixed_order'::uuid,'$customer_id'::uuid)::text")"
[[ "$customer_projection" == *'V1 Cafe'* \
   && "$customer_projection" != *'Secret Retail Branch'* \
   && "$customer_projection" != *"$retail_branch"* ]] || {
  printf 'Mixed customer projection violated restaurant visibility or retail privacy.\n' >&2
  exit 1
}

printf 'Restaurant-only and mixed Food + Retail payment-to-settlement E2E gates passed.\n'
