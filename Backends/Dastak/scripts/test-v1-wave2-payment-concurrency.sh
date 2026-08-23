#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-step2.XXXXXX")"
run_token="$(date +%s)$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
customer_id='99200000-0000-4000-8000-000000000001'
owner_id='99200000-0000-4000-8000-000000000002'
merchant_a='99200000-0000-4000-8000-000000000003'
merchant_b='99200000-0000-4000-8000-000000000004'
merchant_c='99200000-0000-4000-8000-000000000005'
branch_a='99200000-0000-4000-8000-000000000021'
branch_b='99200000-0000-4000-8000-000000000031'
branch_c='99200000-0000-4000-8000-000000000041'

"${psql_base[@]}" <<'SQL'
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
('99200000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-race-customer@example.test', '', now(), now(), now()),
('99200000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-race-owner@example.test', '', now(), now(), now()),
('99200000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-race-a@example.test', '', now(), now(), now()),
('99200000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-race-b@example.test', '', now(), now(), now()),
('99200000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-race-c@example.test', '', now(), now(), now())
on conflict (id) do nothing;

insert into public.accounts (id, display_name, phone_number) values
('99200000-0000-4000-8000-000000000001', 'Step Two Race Customer', '+919920000001'),
('99200000-0000-4000-8000-000000000002', 'Step Two Race Owner', '+919920000002'),
('99200000-0000-4000-8000-000000000003', 'Step Two Race Merchant A', '+919920000003'),
('99200000-0000-4000-8000-000000000004', 'Step Two Race Merchant B', '+919920000004'),
('99200000-0000-4000-8000-000000000005', 'Step Two Race Merchant C', '+919920000005')
on conflict (id) do nothing;

insert into private.account_memberships (account_id, role, approved_at) values
('99200000-0000-4000-8000-000000000001', 'customer', null),
('99200000-0000-4000-8000-000000000002', 'owner', now()),
('99200000-0000-4000-8000-000000000003', 'merchant', now()),
('99200000-0000-4000-8000-000000000004', 'merchant', now()),
('99200000-0000-4000-8000-000000000005', 'merchant', now())
on conflict (account_id, role) do nothing;

insert into public.service_zones (id, name, boundary, active) values (
  '99200000-0000-4000-8000-000000000010', 'Step Two Race Zone',
  extensions.st_geomfromtext('POLYGON((80 15,81 15,81 16,80 16,80 15))', 4326), true
) on conflict (id) do nothing;

insert into dastak_v1.categories (id, name, slug, status, created_by) values (
  '99200000-0000-4000-8000-000000000011', 'Step Two Race Category',
  'step-two-race-category', 'ACTIVE', '99200000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;
insert into dastak_v1.subcategories (
  id, category_id, name, slug, status, created_by
) values (
  '99200000-0000-4000-8000-000000000012',
  '99200000-0000-4000-8000-000000000011', 'Step Two Race Subcategory',
  'step-two-race-subcategory', 'ACTIVE', '99200000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;
insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, logistics_attributes, status, created_by
) values
('99200000-0000-4000-8000-000000000013',
 '99200000-0000-4000-8000-000000000012', 'Step Two Race Product A',
 'step-two-race-product-a', '1 unit', 1200, 1000,
 '{"weightGrams":400,"lengthMillimetres":150,"widthMillimetres":100,"heightMillimetres":80,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}',
 'ACTIVE', '99200000-0000-4000-8000-000000000002'),
('99200000-0000-4000-8000-000000000014',
 '99200000-0000-4000-8000-000000000012', 'Step Two Race Product B',
 'step-two-race-product-b', '1 unit', 2200, 2000,
 '{"weightGrams":600,"lengthMillimetres":200,"widthMillimetres":100,"heightMillimetres":90,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}',
 'ACTIVE', '99200000-0000-4000-8000-000000000002')
on conflict (id) do nothing;

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values
('99200000-0000-4000-8000-000000000020', 'Step Two Race A Private Limited',
 'Step Two Race A', 'RETAIL', 'ACTIVE', '99200000-0000-4000-8000-000000000002'),
('99200000-0000-4000-8000-000000000030', 'Step Two Race B Private Limited',
 'Step Two Race B', 'RETAIL', 'ACTIVE', '99200000-0000-4000-8000-000000000002'),
('99200000-0000-4000-8000-000000000040', 'Step Two Race C Private Limited',
 'Step Two Race C', 'DASTAK_CONVENIENCE_STORE', 'ACTIVE',
 '99200000-0000-4000-8000-000000000002')
on conflict (id) do nothing;

insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id, address_snapshot,
  location, capacity_limit, status, created_by
) values
('99200000-0000-4000-8000-000000000021', '99200000-0000-4000-8000-000000000020',
 'Step Two Race Branch A', '99200000-0000-4000-8000-000000000010', '{}',
 extensions.st_setsrid(extensions.st_makepoint(80.60, 15.68), 4326), 1, 'ACTIVE',
 '99200000-0000-4000-8000-000000000002'),
('99200000-0000-4000-8000-000000000031', '99200000-0000-4000-8000-000000000030',
 'Step Two Race Branch B', '99200000-0000-4000-8000-000000000010', '{}',
 extensions.st_setsrid(extensions.st_makepoint(80.61, 15.68), 4326), 1, 'ACTIVE',
 '99200000-0000-4000-8000-000000000002'),
('99200000-0000-4000-8000-000000000041', '99200000-0000-4000-8000-000000000040',
 'Step Two Race Branch C', '99200000-0000-4000-8000-000000000010', '{}',
 extensions.st_setsrid(extensions.st_makepoint(80.62, 15.68), 4326), 1, 'ACTIVE',
 '99200000-0000-4000-8000-000000000002')
on conflict (id) do nothing;

insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values
('99200000-0000-4000-8000-000000000022', '99200000-0000-4000-8000-000000000020',
 '99200000-0000-4000-8000-000000000003', 'ACTIVE', '99200000-0000-4000-8000-000000000002'),
('99200000-0000-4000-8000-000000000032', '99200000-0000-4000-8000-000000000030',
 '99200000-0000-4000-8000-000000000004', 'ACTIVE', '99200000-0000-4000-8000-000000000002'),
('99200000-0000-4000-8000-000000000042', '99200000-0000-4000-8000-000000000040',
 '99200000-0000-4000-8000-000000000005', 'ACTIVE', '99200000-0000-4000-8000-000000000002')
on conflict (id) do nothing;

insert into dastak_v1.merchant_permission_grants (
  id, merchant_user_id, organization_id, bundle_id, branch_id, granted_by, grant_reason
) values
('99200000-0000-4000-8000-000000000023', '99200000-0000-4000-8000-000000000022',
 '99200000-0000-4000-8000-000000000020', '10000000-0000-4000-8000-000000000002',
 '99200000-0000-4000-8000-000000000021', '99200000-0000-4000-8000-000000000002', 'Step 2 race A.'),
('99200000-0000-4000-8000-000000000033', '99200000-0000-4000-8000-000000000032',
 '99200000-0000-4000-8000-000000000030', '10000000-0000-4000-8000-000000000002',
 '99200000-0000-4000-8000-000000000031', '99200000-0000-4000-8000-000000000002', 'Step 2 race B.'),
('99200000-0000-4000-8000-000000000043', '99200000-0000-4000-8000-000000000042',
 '99200000-0000-4000-8000-000000000040', '10000000-0000-4000-8000-000000000002',
 '99200000-0000-4000-8000-000000000041', '99200000-0000-4000-8000-000000000002', 'Step 2 race C.')
on conflict (id) do nothing;

insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values
('99200000-0000-4000-8000-000000000021', true, true, '99200000-0000-4000-8000-000000000003'),
('99200000-0000-4000-8000-000000000031', true, true, '99200000-0000-4000-8000-000000000004'),
('99200000-0000-4000-8000-000000000041', true, true, '99200000-0000-4000-8000-000000000005')
on conflict (branch_id) do update
set is_open = true, accepting_orders = true, updated_by = excluded.updated_by,
    version = dastak_v1.branch_operational_states.version + 1;

insert into dastak_v1.merchant_sku_selections (
  branch_id, sku_id, state, selected_by
) values
('99200000-0000-4000-8000-000000000021', '99200000-0000-4000-8000-000000000013',
 'SELECTED', '99200000-0000-4000-8000-000000000003'),
('99200000-0000-4000-8000-000000000031', '99200000-0000-4000-8000-000000000014',
 'SELECTED', '99200000-0000-4000-8000-000000000004'),
('99200000-0000-4000-8000-000000000041', '99200000-0000-4000-8000-000000000013',
 'SELECTED', '99200000-0000-4000-8000-000000000005'),
('99200000-0000-4000-8000-000000000041', '99200000-0000-4000-8000-000000000014',
 'SELECTED', '99200000-0000-4000-8000-000000000005')
on conflict (branch_id, sku_id) do update
set state = 'SELECTED', selected_by = excluded.selected_by;

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
)
select setting.id, setting.key, 'GLOBAL', setting.value,
  '99200000-0000-4000-8000-000000000002', 'Step 2 race runtime.'
from (values
  ('99200000-0000-4000-8000-000000000050'::uuid, 'matching.retail_radius_meters', '30000'::jsonb),
  ('99200000-0000-4000-8000-000000000051'::uuid, 'retail.prep_time_options_minutes', '[10,15,20]'::jsonb),
  ('99200000-0000-4000-8000-000000000052'::uuid, 'matching.wave2_timeout_seconds', '120'::jsonb),
  ('99200000-0000-4000-8000-000000000053'::uuid, 'matching.wave2_hold_seconds', '180'::jsonb),
  ('99200000-0000-4000-8000-000000000054'::uuid, 'payment.reservation_seconds', '300'::jsonb),
  ('99200000-0000-4000-8000-000000000055'::uuid, 'matching.wave2_max_pickup_route_meters', '50000'::jsonb),
  ('99200000-0000-4000-8000-000000000056'::uuid, 'matching.operational_reliability_bps', '9000'::jsonb),
  ('99200000-0000-4000-8000-000000000057'::uuid, 'delivery.transport_load_profiles', '[{"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},{"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500},{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]'::jsonb),
  ('99200000-0000-4000-8000-000000000058'::uuid, 'delivery.default_sku_logistics', '{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}'::jsonb),
  ('99200000-0000-4000-8000-000000000059'::uuid, 'merchant.reachability_stale_seconds', '300'::jsonb)
) setting(id, key, value)
where not exists (
  select 1 from dastak_v1.platform_settings existing
  where existing.setting_key = setting.key
    and existing.scope_type = 'GLOBAL' and existing.scope_id is null
);
SQL

submit_order() {
  local key="$1"
  "${psql_base[@]}" -At -v key="$key" -v customer_id="$customer_id" <<'SQL' | tail -n 1
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'customer_id', true);
select public.dastak_v1_submit_order(
  :'key', 0,
  '{"deliveryAddress":{"line1":"1 Step Two Race Road","countryCode":"IN","latitude":15.68,"longitude":80.62},"recipient":{"name":"Step Two Race Customer","phoneNumber":"+919920000001"},"lines":[{"lineType":"RETAIL_SKU","skuId":"99200000-0000-4000-8000-000000000013","quantity":1},{"lineType":"RETAIL_SKU","skuId":"99200000-0000-4000-8000-000000000014","quantity":1}]}'::jsonb
) ->> 'id';
commit;
SQL
}

attempt_for_order() {
  "${psql_base[@]}" -At -v order_id="$1" -v wave="$2" <<'SQL'
select id from dastak_v1.matching_attempts
where order_id = :'order_id'::uuid and wave = :'wave'::dastak_v1.matching_wave;
SQL
}

opportunity_for_branch() {
  "${psql_base[@]}" -At -v order_id="$1" -v branch_id="$2" -v wave="$3" <<'SQL'
select id from dastak_v1.merchant_opportunities
where order_id = :'order_id'::uuid and branch_id = :'branch_id'::uuid
  and wave = :'wave'::dastak_v1.matching_wave;
SQL
}

start_wave2() {
  local order_id="$1" attempt_id
  attempt_id="$(attempt_for_order "$order_id" WAVE_1)"
  "${psql_base[@]}" -v order_id="$order_id" -v attempt_id="$attempt_id" <<'SQL' >/dev/null
alter table dastak_v1.matching_attempts disable trigger matching_attempts_guard;
alter table dastak_v1.merchant_opportunities disable trigger merchant_opportunities_guard;
update dastak_v1.matching_attempts
set started_at = now() - interval '4 minutes', expires_at = now() - interval '1 second'
where id = :'attempt_id'::uuid;
update dastak_v1.merchant_opportunities
set started_at = now() - interval '4 minutes', expires_at = now() - interval '1 second'
where order_id = :'order_id'::uuid and wave = 'WAVE_1';
alter table dastak_v1.merchant_opportunities enable trigger merchant_opportunities_guard;
alter table dastak_v1.matching_attempts enable trigger matching_attempts_guard;
select dastak_v1_api.expire_wave1_attempt(:'attempt_id'::uuid);
SQL
  attempt_for_order "$order_id" WAVE_2
}

make_wave2_due() {
  local order_id="$1" attempt_id="$2"
  "${psql_base[@]}" -v order_id="$order_id" -v attempt_id="$attempt_id" <<'SQL' >/dev/null
alter table dastak_v1.matching_attempts disable trigger matching_attempts_guard;
alter table dastak_v1.merchant_opportunities disable trigger merchant_opportunities_guard;
update dastak_v1.matching_attempts
set started_at = now() - interval '4 minutes', expires_at = now() - interval '1 second'
where id = :'attempt_id'::uuid;
update dastak_v1.merchant_opportunities
set started_at = now() - interval '4 minutes', expires_at = now() - interval '1 second'
where order_id = :'order_id'::uuid and wave = 'WAVE_2' and status = 'OFFERED';
alter table dastak_v1.merchant_opportunities enable trigger merchant_opportunities_guard;
alter table dastak_v1.matching_attempts enable trigger matching_attempts_guard;
SQL
}

accept_wave1() {
  "${psql_base[@]}" -At -v actor_id="$1" -v opportunity_id="$2" -v key="$3" <<'SQL'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_accept_wave1_opportunity(:'opportunity_id'::uuid, :'key', 1, 10);
commit;
SQL
}

accept_wave2() {
  "${psql_base[@]}" -At -v actor_id="$1" -v opportunity_id="$2" -v key="$3" <<'SQL'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_accept_wave2_opportunity(:'opportunity_id'::uuid, :'key', 1, 10);
commit;
SQL
}

cancel_order() {
  local order_id="$1" key="$2" attempt expected_version
  for attempt in 1 2 3; do
    expected_version="$("${psql_base[@]}" -At -v order_id="$order_id" <<'SQL'
select version from dastak_v1.orders where id = :'order_id'::uuid;
SQL
)"
    if "${psql_base[@]}" -At -v customer_id="$customer_id" -v order_id="$order_id" \
      -v key="$key-$attempt" -v expected_version="$expected_version" <<'SQL'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'customer_id', true);
select public.dastak_v1_cancel_prepayment_order(
  :'order_id'::uuid, :'key', :'expected_version'::bigint
);
commit;
SQL
    then return 0; fi
  done
  return 1
}

secure_wave1_order() {
  local key="$1" order_id opportunity_id
  order_id="$(submit_order "$key")"
  opportunity_id="$(opportunity_for_branch "$order_id" "$branch_c" WAVE_1)"
  accept_wave1 "$merchant_c" "$opportunity_id" "$key-accept" >/dev/null
  printf '%s\n' "$order_id"
}

prepare_payment() {
  local order_id="$1" key="$2" provider_order="$3"
  "${psql_base[@]}" -At -F ' ' -v customer_id="$customer_id" -v order_id="$order_id" \
    -v key="$key" -v provider_order="$provider_order" <<'SQL'
set role service_role;
with attempt as materialized (
  select public.dastak_v1_prepare_razorpay_checkout(
    :'customer_id'::uuid, :'order_id'::uuid, :'key'
  ) body
), attached as materialized (
  select public.dastak_v1_attach_razorpay_order(
    :'customer_id'::uuid, (attempt.body ->> 'attemptId')::uuid,
    :'provider_order', (attempt.body ->> 'amountPaise')::bigint, 'INR'
  ) from attempt
)
select attempt.body ->> 'attemptId', attempt.body ->> 'amountPaise'
from attempt cross join attached;
SQL
}

capture_payment() {
  "${psql_base[@]}" -At -v event_id="$1" -v provider_order="$2" \
    -v provider_payment="$3" -v amount="$4" -v digest_char="$5" <<'SQL'
set role service_role;
select response_status from public.dastak_v1_record_razorpay_event(
  :'event_id', 'payment_captured', :'provider_order', :'provider_payment',
  null, :'amount'::bigint, now(), repeat(:'digest_char', 64)
);
SQL
}

make_payment_due() {
  "${psql_base[@]}" -v order_id="$1" <<'SQL' >/dev/null
alter table dastak_v1.payments disable trigger payments_guard;
update dastak_v1.payments
set reserved_at = now() - interval '4 minutes', expires_at = now() - interval '1 second'
where order_id = :'order_id'::uuid;
alter table dastak_v1.payments enable trigger payments_guard;
SQL
}

assert_cancelled_released() {
  local truth
  truth="$("${psql_base[@]}" -At -F ' ' -v order_id="$1" <<'SQL'
select
  (select count(*) from dastak_v1.orders where id = :'order_id'::uuid and status = 'CANCELLED_PREPAYMENT'),
  (select count(*) from dastak_v1.wave2_provisional_holds where order_id = :'order_id'::uuid and status = 'HELD'),
  (select count(*) from dastak_v1.inventory_holds hold join dastak_v1.fulfilments f on f.id = hold.fulfilment_id where f.order_id = :'order_id'::uuid and hold.status = 'HELD'),
  (select count(*) from dastak_v1.retail_capacity_slots slot join dastak_v1.fulfilments f on f.id = slot.fulfilment_id where f.order_id = :'order_id'::uuid and slot.status = 'HELD'),
  (select count(*) from dastak_v1.payments where order_id = :'order_id'::uuid and status = 'RESERVED');
SQL
)"
  [[ "$truth" == "1 0 0 0 0" ]] || { printf 'Cancellation release invariant failed: %s\n' "$truth" >&2; exit 1; }
}

# Concurrent partial acceptances create a two-merchant plan; the later full
# merchant creates a competing one-merchant plan, which must win.
plan_order="$(submit_order "step2-plan-$run_token")"
plan_attempt="$(start_wave2 "$plan_order")"
plan_a="$(opportunity_for_branch "$plan_order" "$branch_a" WAVE_2)"
plan_b="$(opportunity_for_branch "$plan_order" "$branch_b" WAVE_2)"
plan_c="$(opportunity_for_branch "$plan_order" "$branch_c" WAVE_2)"
accept_wave2 "$merchant_a" "$plan_a" "step2-plan-a-$run_token" >"$work_dir/plan-a.out" 2>"$work_dir/plan-a.err" &
plan_a_pid=$!
accept_wave2 "$merchant_b" "$plan_b" "step2-plan-b-$run_token" >"$work_dir/plan-b.out" 2>"$work_dir/plan-b.err" &
plan_b_pid=$!
wait "$plan_a_pid"; wait "$plan_b_pid"
accept_wave2 "$merchant_c" "$plan_c" "step2-plan-c-$run_token" >/dev/null
plan_truth="$("${psql_base[@]}" -At -F ' ' -v order_id="$plan_order" -v branch_c="$branch_c" <<'SQL'
select
  (select count(*) from dastak_v1.orders where id = :'order_id'::uuid and status = 'AWAITING_PAYMENT'),
  (select count(*) from dastak_v1.fulfilment_plans where order_id = :'order_id'::uuid and status = 'LOCKED' and merchant_count = 1),
  (select count(*) from dastak_v1.fulfilments where order_id = :'order_id'::uuid and branch_id = :'branch_c'::uuid and status = 'RESERVED_PREPAYMENT'),
  (select count(*) from dastak_v1.wave2_provisional_holds where order_id = :'order_id'::uuid and status = 'SELECTED'),
  (select count(*) from dastak_v1.wave2_provisional_holds where order_id = :'order_id'::uuid and status = 'RELEASED');
SQL
)"
[[ "$plan_truth" == "1 1 1 2 2" ]] || { printf 'Competing plan invariant failed: %s\n' "$plan_truth" >&2; exit 1; }
cancel_order "$plan_order" "step2-plan-cleanup-$run_token" >/dev/null

# Expiry locks an already-complete A+B plan and rejects a stale C acceptance.
stale_order="$(submit_order "step2-stale-$run_token")"
stale_attempt="$(start_wave2 "$stale_order")"
stale_a="$(opportunity_for_branch "$stale_order" "$branch_a" WAVE_2)"
stale_b="$(opportunity_for_branch "$stale_order" "$branch_b" WAVE_2)"
stale_c="$(opportunity_for_branch "$stale_order" "$branch_c" WAVE_2)"
accept_wave2 "$merchant_a" "$stale_a" "step2-stale-a-$run_token" >/dev/null
accept_wave2 "$merchant_b" "$stale_b" "step2-stale-b-$run_token" >/dev/null
make_wave2_due "$stale_order" "$stale_attempt"
"${psql_base[@]}" -At -v attempt_id="$stale_attempt" <<'SQL' >/dev/null
select dastak_v1_api.expire_wave2_attempt(:'attempt_id'::uuid);
SQL
set +e
accept_wave2 "$merchant_c" "$stale_c" "step2-stale-c-$run_token" >/dev/null 2>"$work_dir/stale.err"
stale_exit=$?
set -e
[[ "$stale_exit" -ne 0 ]] || { printf 'Stale Wave 2 acceptance unexpectedly committed.\n' >&2; exit 1; }
cancel_order "$stale_order" "step2-stale-cleanup-$run_token" >/dev/null

# Capacity is provisional until final lock and is revalidated atomically.
capacity_order="$(submit_order "step2-capacity-$run_token")"
capacity_attempt="$(start_wave2 "$capacity_order")"
capacity_c="$(opportunity_for_branch "$capacity_order" "$branch_c" WAVE_2)"
accept_wave2 "$merchant_c" "$capacity_c" "step2-capacity-hold-$run_token" >/dev/null
blocker_order="$(secure_wave1_order "step2-capacity-blocker-$run_token")"
make_wave2_due "$capacity_order" "$capacity_attempt"
"${psql_base[@]}" -At -v attempt_id="$capacity_attempt" <<'SQL' >/dev/null
select dastak_v1_api.expire_wave2_attempt(:'attempt_id'::uuid);
SQL
capacity_truth="$("${psql_base[@]}" -At -F ' ' -v order_id="$capacity_order" <<'SQL'
select
  (select count(*) from dastak_v1.orders where id = :'order_id'::uuid and status = 'UNAVAILABLE'),
  (select count(*) from dastak_v1.fulfilment_plans where order_id = :'order_id'::uuid and rejection_reason = 'BRANCH_CAPACITY_LOST'),
  (select count(*) from dastak_v1.wave2_provisional_holds where order_id = :'order_id'::uuid and status = 'RELEASED'),
  (select count(*) from dastak_v1.retail_capacity_slots slot join dastak_v1.fulfilments f on f.id = slot.fulfilment_id where f.order_id = :'order_id'::uuid);
SQL
)"
[[ "$capacity_truth" == "1 1 2 0" ]] || { printf 'Capacity revalidation invariant failed: %s\n' "$capacity_truth" >&2; exit 1; }
cancel_order "$blocker_order" "step2-capacity-blocker-cleanup-$run_token" >/dev/null
"${psql_base[@]}" -v branch_c="$branch_c" <<'SQL' >/dev/null
update dastak_v1.merchant_branches set capacity_limit = 3
where id = :'branch_c'::uuid;
SQL

# Due expiry and a late acceptance contend on the same order/attempt rows.
expiry_order="$(submit_order "step2-expiry-accept-$run_token")"
expiry_attempt="$(start_wave2 "$expiry_order")"
expiry_c="$(opportunity_for_branch "$expiry_order" "$branch_c" WAVE_2)"
make_wave2_due "$expiry_order" "$expiry_attempt"
accept_wave2 "$merchant_c" "$expiry_c" "step2-expiry-accept-c-$run_token" >"$work_dir/expiry-accept.out" 2>"$work_dir/expiry-accept.err" &
expiry_accept_pid=$!
"${psql_base[@]}" -At -v attempt_id="$expiry_attempt" >"$work_dir/expiry-worker.out" 2>"$work_dir/expiry-worker.err" <<'SQL' &
select dastak_v1_api.expire_wave2_attempt(:'attempt_id'::uuid);
SQL
expiry_worker_pid=$!
set +e
wait "$expiry_accept_pid"; expiry_accept_exit=$?
wait "$expiry_worker_pid"; expiry_worker_exit=$?
set -e
[[ "$expiry_worker_exit" -eq 0 && "$expiry_accept_exit" -ne 0 ]] || { printf 'Expiry/accept race exits: %s/%s\n' "$expiry_worker_exit" "$expiry_accept_exit" >&2; exit 1; }

# Cancellation must remain final when racing both final-plan locking paths.
cancel_lock_order="$(submit_order "step2-cancel-lock-$run_token")"
cancel_lock_attempt="$(start_wave2 "$cancel_lock_order")"
cancel_lock_a="$(opportunity_for_branch "$cancel_lock_order" "$branch_a" WAVE_2)"
cancel_lock_b="$(opportunity_for_branch "$cancel_lock_order" "$branch_b" WAVE_2)"
accept_wave2 "$merchant_a" "$cancel_lock_a" "step2-cancel-lock-a-$run_token" >/dev/null
accept_wave2 "$merchant_b" "$cancel_lock_b" "step2-cancel-lock-b-$run_token" >/dev/null
make_wave2_due "$cancel_lock_order" "$cancel_lock_attempt"
cancel_order "$cancel_lock_order" "step2-cancel-lock-customer-$run_token" >"$work_dir/cancel-lock.out" 2>"$work_dir/cancel-lock.err" &
cancel_lock_pid=$!
"${psql_base[@]}" -At -v attempt_id="$cancel_lock_attempt" >"$work_dir/cancel-lock-worker.out" 2>"$work_dir/cancel-lock-worker.err" <<'SQL' &
select dastak_v1_api.expire_wave2_attempt(:'attempt_id'::uuid);
SQL
cancel_lock_worker_pid=$!
wait "$cancel_lock_pid"; wait "$cancel_lock_worker_pid"
assert_cancelled_released "$cancel_lock_order"

cancel_transition_order="$(submit_order "step2-cancel-transition-$run_token")"
cancel_transition_attempt="$(start_wave2 "$cancel_transition_order")"
cancel_transition_a="$(opportunity_for_branch "$cancel_transition_order" "$branch_a" WAVE_2)"
cancel_transition_b="$(opportunity_for_branch "$cancel_transition_order" "$branch_b" WAVE_2)"
cancel_transition_c="$(opportunity_for_branch "$cancel_transition_order" "$branch_c" WAVE_2)"
accept_wave2 "$merchant_a" "$cancel_transition_a" "step2-cancel-transition-a-$run_token" >/dev/null
accept_wave2 "$merchant_b" "$cancel_transition_b" "step2-cancel-transition-b-$run_token" >/dev/null
accept_wave2 "$merchant_c" "$cancel_transition_c" "step2-cancel-transition-c-$run_token" >"$work_dir/cancel-transition-merchant.out" 2>"$work_dir/cancel-transition-merchant.err" &
cancel_transition_merchant_pid=$!
cancel_order "$cancel_transition_order" "step2-cancel-transition-customer-$run_token" >"$work_dir/cancel-transition-customer.out" 2>"$work_dir/cancel-transition-customer.err" &
cancel_transition_customer_pid=$!
set +e
wait "$cancel_transition_merchant_pid"
wait "$cancel_transition_customer_pid"; cancel_transition_customer_exit=$?
set -e
[[ "$cancel_transition_customer_exit" -eq 0 ]] || { cat "$work_dir/cancel-transition-customer.err" >&2; exit 1; }
assert_cancelled_released "$cancel_transition_order"

# Retry remains in the same reservation; concurrent duplicate callbacks commit
# one provider event, one paid transition, and one preparation start.
paid_order="$(secure_wave1_order "step2-paid-$run_token")"
read -r failed_attempt paid_amount <<<"$(prepare_payment "$paid_order" "step2-failed-attempt-$run_token" "order_step2failed$run_token")"
"${psql_base[@]}" -At -v customer_id="$customer_id" -v attempt_id="$failed_attempt" <<'SQL' >/dev/null
set role service_role;
select public.dastak_v1_mark_payment_attempt_failed(
  :'customer_id'::uuid, :'attempt_id'::uuid, 'CHECKOUT_CANCELLED'
);
SQL
read -r paid_attempt paid_amount <<<"$(prepare_payment "$paid_order" "step2-paid-attempt-$run_token" "order_step2paid$run_token")"
capture_payment "event_step2duplicate$run_token" "order_step2paid$run_token" "pay_step2paid$run_token" "$paid_amount" a >"$work_dir/duplicate-a.out" 2>"$work_dir/duplicate-a.err" &
duplicate_a_pid=$!
capture_payment "event_step2duplicate$run_token" "order_step2paid$run_token" "pay_step2paid$run_token" "$paid_amount" a >"$work_dir/duplicate-b.out" 2>"$work_dir/duplicate-b.err" &
duplicate_b_pid=$!
wait "$duplicate_a_pid"; wait "$duplicate_b_pid"
paid_truth="$("${psql_base[@]}" -At -F ' ' -v order_id="$paid_order" <<'SQL'
select
  (select count(*) from dastak_v1.orders where id = :'order_id'::uuid and status = 'PREPARING'),
  (select count(*) from dastak_v1.payments where order_id = :'order_id'::uuid and status = 'SUCCEEDED'),
  (select count(*) from dastak_v1.payment_attempts where order_id = :'order_id'::uuid),
  (select count(*) from dastak_v1.payment_provider_events where order_id = :'order_id'::uuid),
  (select count(*) from dastak_v1.order_state_journal where order_id = :'order_id'::uuid and to_status = 'PAID'),
  (select count(*) from dastak_v1.order_state_journal where order_id = :'order_id'::uuid and to_status = 'PREPARING'),
  (select count(*) from dastak_v1.domain_events_outbox where aggregate_type = 'ORDER' and aggregate_id = :'order_id'::uuid and event_type = 'PREPARATION_STARTED'),
  (select count(*) from dastak_v1.financial_journal_transactions transaction
    join dastak_v1.payments payment on payment.id=transaction.payment_id
    where transaction.order_id=:'order_id'::uuid
      and transaction.transaction_type='PLATFORM_FEE_RECOGNITION'
      and transaction.amount_paise=dastak_v1_api.calculate_platform_fee(payment.amount_paise)),
  (select count(*) from dastak_v1.financial_journal_transactions transaction
    where transaction.order_id=:'order_id'::uuid
      and transaction.transaction_type='MERCHANT_ROYALTY_EARNING');
SQL
)"
[[ "$paid_truth" == "1 1 2 1 1 1 1 1 0" ]] || { printf 'Payment/fee/preparation idempotency invariant failed: %s\n' "$paid_truth" >&2; exit 1; }

# Two expiry workers and a late provider capture race. Resources and capacity
# release once; the late success is reconciled and cannot resurrect the order.
late_order="$(secure_wave1_order "step2-late-$run_token")"
read -r late_attempt late_amount <<<"$(prepare_payment "$late_order" "step2-late-attempt-$run_token" "order_step2late$run_token")"
make_payment_due "$late_order"
"${psql_base[@]}" -At -v order_id="$late_order" >"$work_dir/payment-expiry-a.out" 2>"$work_dir/payment-expiry-a.err" <<'SQL' &
select dastak_v1_api.expire_payment_reservation(:'order_id'::uuid);
SQL
payment_expiry_a_pid=$!
"${psql_base[@]}" -At -v order_id="$late_order" >"$work_dir/payment-expiry-b.out" 2>"$work_dir/payment-expiry-b.err" <<'SQL' &
select dastak_v1_api.expire_payment_reservation(:'order_id'::uuid);
SQL
payment_expiry_b_pid=$!
capture_payment "event_step2late$run_token" "order_step2late$run_token" "pay_step2late$run_token" "$late_amount" c >"$work_dir/payment-late.out" 2>"$work_dir/payment-late.err" &
payment_late_pid=$!
wait "$payment_expiry_a_pid"; wait "$payment_expiry_b_pid"; wait "$payment_late_pid"
late_truth="$("${psql_base[@]}" -At -F ' ' -v order_id="$late_order" <<'SQL'
select
  (select count(*) from dastak_v1.orders where id = :'order_id'::uuid and status = 'PAYMENT_EXPIRED'),
  (select count(*) from dastak_v1.order_state_journal where order_id = :'order_id'::uuid and to_status = 'PAYMENT_EXPIRED'),
  (select count(*) from dastak_v1.payment_reconciliation_cases where order_id = :'order_id'::uuid and reason = 'LATE_SUCCESS_AFTER_PAYMENT_EXPIRED'),
  (select count(*) from dastak_v1.retail_capacity_slots slot join dastak_v1.fulfilments f on f.id = slot.fulfilment_id where f.order_id = :'order_id'::uuid and slot.status = 'RELEASED' and slot.version = 2),
  (select count(*) from dastak_v1.inventory_holds hold join dastak_v1.fulfilments f on f.id = hold.fulfilment_id where f.order_id = :'order_id'::uuid and hold.status = 'RELEASED' and hold.version = 2),
  (select count(*) from dastak_v1.order_state_journal where order_id = :'order_id'::uuid and to_status = 'PAID');
SQL
)"
[[ "$late_truth" == "1 1 1 1 2 0" ]] || { printf 'Payment expiry race invariant failed: %s\n' "$late_truth" >&2; exit 1; }

printf 'Dastak V1 Wave 2, coordinator and payment concurrency races passed.\n'
