#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-step6.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
event_version="$("${psql_base[@]}" -Atc "select coalesce(max(aggregate_version),1)+1 from dastak_v1.domain_events_outbox where aggregate_type='ORDER' and aggregate_id='99700000-0000-4000-8000-000000000010'")"
event_key="99700000-0000-4000-8000-000000000010:ORDER_SUBMITTED:$event_version"

"${psql_base[@]}" -v event_key="$event_key" -v event_version="$event_version" <<'SQL'
begin;
insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,
  email_confirmed_at,created_at,updated_at
) values (
  '99700000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','step6-customer@example.test','',
  now(),now(),now()
) on conflict (id) do nothing;
insert into public.accounts (id,display_name,phone_number) values (
  '99700000-0000-4000-8000-000000000001','Step 6 Customer','+919970000001'
) on conflict (id) do nothing;
insert into private.account_memberships (account_id,role,approved_at) values (
  '99700000-0000-4000-8000-000000000001','customer',null
) on conflict (account_id,role) do nothing;
insert into dastak_v1.category_types (id,name,slug,status,created_by) values (
  '99700000-0000-4000-8000-000000000019','Step Six Type',
  'step-six-type','ACTIVE','99700000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;
insert into dastak_v1.categories (id,category_type_id,name,slug,status,created_by) values (
  '99700000-0000-4000-8000-000000000020',
  '99700000-0000-4000-8000-000000000019','Step Six Category',
  'step-six-category','ACTIVE','99700000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;
insert into dastak_v1.subcategories (
  id,category_id,name,slug,status,created_by
) values (
  '99700000-0000-4000-8000-000000000021',
  '99700000-0000-4000-8000-000000000020','Step Six Subcategory',
  'step-six-subcategory','ACTIVE','99700000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;
insert into dastak_v1.skus (
  id,subcategory_id,canonical_name,slug,pack_size,list_price_paise,
  selling_price_paise,logistics_attributes,status,
  qa_status,qa_verified_at,qa_verified_by,created_by
) values (
  '99700000-0000-4000-8000-000000000022',
  '99700000-0000-4000-8000-000000000021','Step Six Product',
  'step-six-product','1 unit',1000,900,
  '{"weightGrams":100,"lengthMillimetres":100,"widthMillimetres":100,"heightMillimetres":100,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}',
  'DRAFT','VERIFIED',now(),'99700000-0000-4000-8000-000000000001',
  '99700000-0000-4000-8000-000000000001'
) on conflict (id) do nothing;
insert into dastak_v1.sku_images (
  id,sku_id,image_key,role,source_type,source_reference,status,
  created_by,verified_by,verified_at,rights_status,rights_reference,
  rights_verified_by,rights_verified_at
) values (
  '99700000-0000-4000-8000-000000000024','99700000-0000-4000-8000-000000000022',
  'test-fixtures/step-six-product.webp','PRIMARY','OWNER_CAPTURE','V1 race fixture','VERIFIED',
  '99700000-0000-4000-8000-000000000001','99700000-0000-4000-8000-000000000001',now(),
  'CLEARED','Test fixture rights clearance','99700000-0000-4000-8000-000000000001',now()
) on conflict (id) do nothing;
update dastak_v1.skus set status='ACTIVE',updated_at=now(),version=version+1
where id='99700000-0000-4000-8000-000000000022' and status <> 'ACTIVE';
insert into dastak_v1.orders (
  id,display_order_number,customer_id,order_type,status,submitted_at,version
) values (
  '99700000-0000-4000-8000-000000000010','DV1-STEP6-RACE',
  '99700000-0000-4000-8000-000000000001','RETAIL_ONLY','MATCHING',now(),:event_version
) on conflict (id) do update set version = excluded.version;
insert into dastak_v1.order_lines (
  id,order_id,line_type,sku_id,product_name_snapshot,pack_size_snapshot,
  quantity,unit_price_paise,status
) values (
  '99700000-0000-4000-8000-000000000023',
  '99700000-0000-4000-8000-000000000010','RETAIL_SKU',
  '99700000-0000-4000-8000-000000000022','Step Six Product',
  '1 unit',1,900,'ORDERED'
) on conflict (id) do nothing;
select public.dastak_v1_register_device_token(
  '99700000-0000-4000-8000-000000000001','step6-race-device','ios'
);
insert into dastak_v1.domain_events_outbox (
  event_key,aggregate_type,aggregate_id,aggregate_version,
  event_type,actor_id,payload
) values (
  :'event_key',
  'ORDER','99700000-0000-4000-8000-000000000010',:event_version,
  'ORDER_SUBMITTED','99700000-0000-4000-8000-000000000001',
  '{"orderId":"99700000-0000-4000-8000-000000000010"}'::jsonb
) on conflict (event_key) do nothing;
commit;
SQL

("${psql_base[@]}" -Atc "select public.dastak_v1_fanout_outbox('step6-fanout-a',500)->>'eventsPublished'" >"$work_dir/fanout-a") &
fanout_a_pid=$!
("${psql_base[@]}" -Atc "select public.dastak_v1_fanout_outbox('step6-fanout-b',500)->>'eventsPublished'" >"$work_dir/fanout-b") &
fanout_b_pid=$!
wait "$fanout_a_pid"
wait "$fanout_b_pid"

fanout_state="$("${psql_base[@]}" -Atc "select (event.status = 'PUBLISHED')::text || '|' || count(intent.id)::text || '|' || count(delivery.id)::text from dastak_v1.domain_events_outbox event left join dastak_v1.notification_intents intent on intent.event_id=event.id left join dastak_v1.notification_deliveries delivery on delivery.intent_id=intent.id where event.event_key='$event_key' group by event.status")"
[[ "$fanout_state" == "true|2|1" ]] || {
  printf 'concurrent fan-out did not publish both platform intents and one registered-device delivery: %s\n' "$fanout_state" >&2
  exit 1
}

delivery_id="$("${psql_base[@]}" -Atc "select delivery.id from dastak_v1.notification_deliveries delivery join dastak_v1.domain_events_outbox event on event.id=delivery.event_id where event.event_key='$event_key'")"
("${psql_base[@]}" -Atc "select count(*) from jsonb_array_elements(public.dastak_v1_claim_notification_deliveries('step6-claim-a',500)) job where job->>'deliveryId'='$delivery_id'" >"$work_dir/claim-a") &
claim_a_pid=$!
("${psql_base[@]}" -Atc "select count(*) from jsonb_array_elements(public.dastak_v1_claim_notification_deliveries('step6-claim-b',500)) job where job->>'deliveryId'='$delivery_id'" >"$work_dir/claim-b") &
claim_b_pid=$!
wait "$claim_a_pid"
wait "$claim_b_pid"

claim_total="$(awk '{sum += $1} END {print sum + 0}' "$work_dir/claim-a" "$work_dir/claim-b")"
[[ "$claim_total" == "1" ]] || {
  printf 'concurrent delivery claim produced %s winners instead of one\n' "$claim_total" >&2
  exit 1
}

worker_id="$("${psql_base[@]}" -Atc "select locked_by from dastak_v1.notification_deliveries where id='$delivery_id'")"
("${psql_base[@]}" -Atc "select public.dastak_v1_complete_notification_delivery('$delivery_id','$worker_id',true,false,200,'')->>'status'" >"$work_dir/complete-a") &
complete_a_pid=$!
("${psql_base[@]}" -Atc "select public.dastak_v1_complete_notification_delivery('$delivery_id','$worker_id',true,false,200,'')->>'status'" >"$work_dir/complete-b") &
complete_b_pid=$!
wait "$complete_a_pid"
wait "$complete_b_pid"

delivery_state="$("${psql_base[@]}" -Atc "select status::text || '|' || attempts::text || '|' || (sent_at is not null)::text from dastak_v1.notification_deliveries where id='$delivery_id'")"
[[ "$delivery_state" == "SENT|1|true" ]] || {
  printf 'duplicate completion corrupted durable delivery state: %s\n' "$delivery_state" >&2
  exit 1
}

intent_count="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.notification_intents where event_id=(select id from dastak_v1.domain_events_outbox where event_key='$event_key')")"
delivery_count="$("${psql_base[@]}" -Atc "select count(*) from dastak_v1.notification_deliveries where event_id=(select id from dastak_v1.domain_events_outbox where event_key='$event_key')")"
[[ "$intent_count" == "2" && "$delivery_count" == "1" ]] || {
  printf 'notification dedupe failed: intents=%s deliveries=%s\n' "$intent_count" "$delivery_count" >&2
  exit 1
}

printf 'Step 6 outbox fan-out, claim and completion concurrency gates passed.\n'
