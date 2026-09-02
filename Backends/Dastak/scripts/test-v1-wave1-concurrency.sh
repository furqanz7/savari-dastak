#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-wave1.XXXXXX")"
run_id="$(date +%s)-$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)

"${psql_base[@]}" <<'SQL'
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '99100000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-race-customer@example.test', '',
  now(), now(), now()
),
(
  '99100000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-race-owner@example.test', '',
  now(), now(), now()
),
(
  '99100000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-race-merchant-a@example.test', '',
  now(), now(), now()
),
(
  '99100000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-race-merchant-b@example.test', '',
  now(), now(), now()
)
on conflict (id) do nothing;

insert into public.accounts (id, display_name, phone_number) values
  ('99100000-0000-4000-8000-000000000001', 'Wave One Race Customer', '+919910000001'),
  ('99100000-0000-4000-8000-000000000002', 'Wave One Race Owner', '+919910000002'),
  ('99100000-0000-4000-8000-000000000003', 'Wave One Race Merchant A', '+919910000003'),
  ('99100000-0000-4000-8000-000000000004', 'Wave One Race Merchant B', '+919910000004')
on conflict (id) do nothing;

insert into private.account_memberships (account_id, role, approved_at) values
  ('99100000-0000-4000-8000-000000000001', 'customer', null),
  ('99100000-0000-4000-8000-000000000002', 'owner', now()),
  ('99100000-0000-4000-8000-000000000003', 'merchant', now()),
  ('99100000-0000-4000-8000-000000000004', 'merchant', now())
on conflict (account_id, role) do nothing;

insert into public.service_zones (id, name, boundary, active) values (
  '99100000-0000-4000-8000-000000000010',
  'Wave One Race Zone',
  extensions.st_geomfromtext(
    'POLYGON((78 12,79 12,79 13,78 13,78 12))',
    4326
  ),
  true
) on conflict (id) do nothing;

insert into dastak_v1.category_types (id, name, slug, status, created_by) values (
  '99100000-0000-4000-8000-000000000009',
  'Wave One Race Type',
  'wave-one-race-type',
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;

insert into dastak_v1.categories (
  id, category_type_id, name, slug, status, created_by
) values (
  '99100000-0000-4000-8000-000000000011',
  '99100000-0000-4000-8000-000000000009',
  'Wave One Race Category',
  'wave-one-race-category',
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;

insert into dastak_v1.subcategories (
  id, category_id, name, slug, status, created_by
) values (
  '99100000-0000-4000-8000-000000000012',
  '99100000-0000-4000-8000-000000000011',
  'Wave One Race Subcategory',
  'wave-one-race-subcategory',
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;

insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, status,
  qa_status, qa_verified_at, qa_verified_by, created_by
) values (
  '99100000-0000-4000-8000-000000000013',
  '99100000-0000-4000-8000-000000000012',
  'Wave One Race Product',
  'wave-one-race-product',
  '1 unit',
  500,
  450,
  'DRAFT',
  'VERIFIED',
  now(),
  '99100000-0000-4000-8000-000000000002',
  '99100000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;

insert into dastak_v1.sku_images (
  id, sku_id, image_key, role, source_type, source_reference,
  status, created_by, verified_by, verified_at,
  rights_status, rights_reference, rights_verified_by, rights_verified_at
) values (
  '99100000-0000-4000-8000-000000000014',
  '99100000-0000-4000-8000-000000000013',
  'test-fixtures/wave-one-race-product.webp',
  'PRIMARY','OWNER_CAPTURE','V1 race fixture','VERIFIED',
  '99100000-0000-4000-8000-000000000002',
  '99100000-0000-4000-8000-000000000002',now(),
  'CLEARED','Test fixture rights clearance',
  '99100000-0000-4000-8000-000000000002',now()
) on conflict (id) do nothing;

update dastak_v1.skus
set status='ACTIVE', updated_at=now(), version=version+1
where id='99100000-0000-4000-8000-000000000013'
  and status <> 'ACTIVE';

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values
(
  '99100000-0000-4000-8000-000000000020',
  'Wave One Race Merchant A Private Limited',
  'Wave One Race Merchant A',
  'RETAIL',
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
),
(
  '99100000-0000-4000-8000-000000000030',
  'Wave One Race Merchant B Private Limited',
  'Wave One Race Merchant B',
  'RETAIL',
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
)
on conflict (id) do nothing;

insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id, address_snapshot,
  location, capacity_limit, status, created_by
) values
(
  '99100000-0000-4000-8000-000000000021',
  '99100000-0000-4000-8000-000000000020',
  'Wave One Race Branch A',
  '99100000-0000-4000-8000-000000000010',
  '{"line1":"21 Race Road"}'::jsonb,
  extensions.st_setsrid(extensions.st_makepoint(78.60, 12.68), 4326),
  5,
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
),
(
  '99100000-0000-4000-8000-000000000031',
  '99100000-0000-4000-8000-000000000030',
  'Wave One Race Branch B',
  '99100000-0000-4000-8000-000000000010',
  '{"line1":"31 Race Road"}'::jsonb,
  extensions.st_setsrid(extensions.st_makepoint(78.61, 12.68), 4326),
  5,
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
)
on conflict (id) do nothing;

insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values
(
  '99100000-0000-4000-8000-000000000022',
  '99100000-0000-4000-8000-000000000020',
  '99100000-0000-4000-8000-000000000003',
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
),
(
  '99100000-0000-4000-8000-000000000032',
  '99100000-0000-4000-8000-000000000030',
  '99100000-0000-4000-8000-000000000004',
  'ACTIVE',
  '99100000-0000-4000-8000-000000000002'
)
on conflict (id) do nothing;

insert into dastak_v1.merchant_permission_grants (
  id, merchant_user_id, organization_id, bundle_id, branch_id,
  granted_by, grant_reason
) values
(
  '99100000-0000-4000-8000-000000000023',
  '99100000-0000-4000-8000-000000000022',
  '99100000-0000-4000-8000-000000000020',
  '10000000-0000-4000-8000-000000000002',
  '99100000-0000-4000-8000-000000000021',
  '99100000-0000-4000-8000-000000000002',
  'Wave One acceptance race access.'
),
(
  '99100000-0000-4000-8000-000000000033',
  '99100000-0000-4000-8000-000000000032',
  '99100000-0000-4000-8000-000000000030',
  '10000000-0000-4000-8000-000000000002',
  '99100000-0000-4000-8000-000000000031',
  '99100000-0000-4000-8000-000000000002',
  'Wave One acceptance race access.'
)
on conflict (id) do nothing;

insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values
(
  '99100000-0000-4000-8000-000000000021',
  true,
  true,
  '99100000-0000-4000-8000-000000000003'
),
(
  '99100000-0000-4000-8000-000000000031',
  true,
  true,
  '99100000-0000-4000-8000-000000000004'
)
on conflict (branch_id) do update
set is_open = excluded.is_open,
    accepting_orders = excluded.accepting_orders,
    updated_by = excluded.updated_by,
    version = dastak_v1.branch_operational_states.version + 1;

insert into dastak_v1.merchant_sku_selections (
  branch_id, sku_id, state, selected_by
) values
(
  '99100000-0000-4000-8000-000000000021',
  '99100000-0000-4000-8000-000000000013',
  'SELECTED',
  '99100000-0000-4000-8000-000000000003'
),
(
  '99100000-0000-4000-8000-000000000031',
  '99100000-0000-4000-8000-000000000013',
  'SELECTED',
  '99100000-0000-4000-8000-000000000004'
)
on conflict (branch_id, sku_id) do nothing;

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
)
select
  '99100000-0000-4000-8000-000000000040',
  'matching.retail_radius_meters',
  'GLOBAL',
  '30000'::jsonb,
  '99100000-0000-4000-8000-000000000002',
  'Wave One race reachability.'
where not exists (
  select 1 from dastak_v1.platform_settings
  where setting_key = 'matching.retail_radius_meters'
    and scope_type = 'GLOBAL'
    and scope_id is null
);

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
)
select
  '99100000-0000-4000-8000-000000000041',
  'retail.prep_time_options_minutes',
  'GLOBAL',
  '[10,15,20]'::jsonb,
  '99100000-0000-4000-8000-000000000002',
  'Wave One race preparation options.'
where not exists (
  select 1 from dastak_v1.platform_settings
  where setting_key = 'retail.prep_time_options_minutes'
    and scope_type = 'GLOBAL'
    and scope_id is null
);

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
)
select setting.id, setting.key, 'GLOBAL', setting.value,
  '99100000-0000-4000-8000-000000000002', 'Wave One coordinator runtime.'
from (values
  ('99100000-0000-4000-8000-000000000042'::uuid, 'matching.wave2_timeout_seconds', '120'::jsonb),
  ('99100000-0000-4000-8000-000000000043'::uuid, 'matching.wave2_hold_seconds', '180'::jsonb),
  ('99100000-0000-4000-8000-000000000044'::uuid, 'payment.reservation_seconds', '300'::jsonb),
  ('99100000-0000-4000-8000-000000000045'::uuid, 'matching.wave2_max_pickup_route_meters', '50000'::jsonb),
  ('99100000-0000-4000-8000-000000000046'::uuid, 'matching.operational_reliability_bps', '9000'::jsonb),
  ('99100000-0000-4000-8000-000000000047'::uuid, 'delivery.transport_load_profiles', '[{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]'::jsonb),
  ('99100000-0000-4000-8000-000000000048'::uuid, 'delivery.default_sku_logistics', '{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}'::jsonb),
  ('99100000-0000-4000-8000-000000000049'::uuid, 'merchant.reachability_stale_seconds', '300'::jsonb)
) setting(id, key, value)
where not exists (
  select 1 from dastak_v1.platform_settings existing
  where existing.setting_key = setting.key
    and existing.scope_type = 'GLOBAL'
    and existing.scope_id is null
);
SQL

submit_order() {
  local key="$1"
  "${psql_base[@]}" -At -v key="$key" <<'SQL' | tail -n 1
begin;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '99100000-0000-4000-8000-000000000001',
  true
);
select public.dastak_v1_submit_order(
  :'key',
  0,
  '{
    "deliveryAddress":{
      "line1":"1 Wave One Race Road",
      "countryCode":"IN",
      "latitude":12.68,
      "longitude":78.62
    },
    "recipient":{
      "name":"Wave One Race Customer",
      "phoneNumber":"+919910000001"
    },
    "lines":[{
      "lineType":"RETAIL_SKU",
      "skuId":"99100000-0000-4000-8000-000000000013",
      "quantity":1
    }]
  }'::jsonb
) ->> 'id';
commit;
SQL
}

opportunity_for_branch() {
  local order_id="$1"
  local branch_id="$2"
  "${psql_base[@]}" -At -v order_id="$order_id" -v branch_id="$branch_id" <<'SQL'
select id
from dastak_v1.merchant_opportunities
where order_id = :'order_id'::uuid
  and branch_id = :'branch_id'::uuid;
SQL
}

attempt_for_order() {
  local order_id="$1"
  "${psql_base[@]}" -At -v order_id="$order_id" <<'SQL'
select id
from dastak_v1.matching_attempts
where order_id = :'order_id'::uuid
  and wave = 'WAVE_1';
SQL
}

accept_opportunity() {
  local actor_id="$1"
  local opportunity_id="$2"
  local key="$3"
  "${psql_base[@]}" -At \
    -v actor_id="$actor_id" \
    -v opportunity_id="$opportunity_id" \
    -v key="$key" <<'SQL'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_accept_wave1_opportunity(
  :'opportunity_id'::uuid,
  :'key',
  1,
  10
);
commit;
SQL
}

cancel_order() {
  local order_id="$1"
  local key="$2"
  local attempt expected_version
  for attempt in 1 2 3; do
    expected_version="$("${psql_base[@]}" -At -v order_id="$order_id" <<'SQL'
select version from dastak_v1.orders where id = :'order_id'::uuid;
SQL
)"
    if "${psql_base[@]}" -At -v order_id="$order_id" -v key="$key-$attempt" \
      -v expected_version="$expected_version" <<'SQL'
begin;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '99100000-0000-4000-8000-000000000001',
  true
);
select public.dastak_v1_cancel_prepayment_order(
  :'order_id'::uuid,
  :'key',
  :'expected_version'::bigint
);
commit;
SQL
    then
      return 0
    fi
  done
  return 1
}

assert_cancelled_and_released() {
  local order_id="$1"
  local result
  result="$("${psql_base[@]}" -At -F ' ' -v order_id="$order_id" <<'SQL'
select
  (select count(*) from dastak_v1.orders
    where id = :'order_id'::uuid
      and status = 'CANCELLED_PREPAYMENT'),
  (select count(*) from dastak_v1.matching_attempts
    where order_id = :'order_id'::uuid
      and status = 'OPEN'),
  (select count(*) from dastak_v1.merchant_opportunities
    where order_id = :'order_id'::uuid
      and status = 'OFFERED'),
  (select count(*)
    from dastak_v1.inventory_holds hold
    join dastak_v1.fulfilments fulfilment on fulfilment.id = hold.fulfilment_id
    where fulfilment.order_id = :'order_id'::uuid
      and hold.status = 'HELD'),
  (select count(*)
    from dastak_v1.retail_capacity_slots slot
    join dastak_v1.fulfilments fulfilment on fulfilment.id = slot.fulfilment_id
    where fulfilment.order_id = :'order_id'::uuid
      and slot.status = 'HELD'),
  (select count(*)
    from dastak_v1.retail_line_allocations allocation
    join dastak_v1.order_lines order_line on order_line.id = allocation.order_line_id
    where order_line.order_id = :'order_id'::uuid
      and allocation.status <> 'RELEASED');
SQL
)"
  if [[ "$result" != "1 0 0 0 0 0" ]]; then
    printf 'Expected cancelled/released order truth; got %s for %s\n' \
      "$result" "$order_id" >&2
    exit 1
  fi
}

# First valid backend commit wins under simultaneous merchant acceptance.
winner_order="$(submit_order "wave1-race-winner-$run_id")"
winner_a="$(opportunity_for_branch "$winner_order" '99100000-0000-4000-8000-000000000021')"
winner_b="$(opportunity_for_branch "$winner_order" '99100000-0000-4000-8000-000000000031')"

accept_opportunity \
  '99100000-0000-4000-8000-000000000003' \
  "$winner_a" \
  "wave1-race-accept-a-$run_id" \
  >"$work_dir/winner-a.out" 2>"$work_dir/winner-a.err" &
winner_a_pid=$!
accept_opportunity \
  '99100000-0000-4000-8000-000000000004' \
  "$winner_b" \
  "wave1-race-accept-b-$run_id" \
  >"$work_dir/winner-b.out" 2>"$work_dir/winner-b.err" &
winner_b_pid=$!

set +e
wait "$winner_a_pid"
winner_a_exit=$?
wait "$winner_b_pid"
winner_b_exit=$?
set -e

if [[ "$winner_a_exit" -eq 0 && "$winner_b_exit" -eq 0 ]] \
  || [[ "$winner_a_exit" -ne 0 && "$winner_b_exit" -ne 0 ]]; then
  printf 'Expected exactly one simultaneous accept to commit; exits %s / %s\n' \
    "$winner_a_exit" "$winner_b_exit" >&2
  exit 1
fi

winner_truth="$("${psql_base[@]}" -At -F ' ' -v order_id="$winner_order" <<'SQL'
select
  (select count(*) from dastak_v1.merchant_opportunities
    where order_id = :'order_id'::uuid and status = 'SELECTED'),
  (select count(*) from dastak_v1.fulfilments
    where order_id = :'order_id'::uuid and status = 'RESERVED_PREPAYMENT'),
  (select count(*)
    from dastak_v1.inventory_holds hold
    join dastak_v1.fulfilments fulfilment on fulfilment.id = hold.fulfilment_id
    where fulfilment.order_id = :'order_id'::uuid and hold.status = 'HELD'),
  (select count(*)
    from dastak_v1.retail_capacity_slots slot
    join dastak_v1.fulfilments fulfilment on fulfilment.id = slot.fulfilment_id
    where fulfilment.order_id = :'order_id'::uuid and slot.status = 'HELD'),
  (select count(*) from dastak_v1.orders
    where id = :'order_id'::uuid
      and status = 'AWAITING_PAYMENT'
      and fully_secured_at is not null
      and payment_expires_at is not null);
SQL
)"
if [[ "$winner_truth" != "1 1 1 1 1" ]]; then
  printf 'Simultaneous accept invariant failed: %s\n' "$winner_truth" >&2
  exit 1
fi
cancel_order "$winner_order" "wave1-race-winner-cleanup-$run_id" >/dev/null

# Cancel vs Accept: cancellation is final whether it wins before or after the
# unpaid physical reservation transaction.
cancel_accept_order="$(submit_order "wave1-race-cancel-accept-$run_id")"
cancel_accept_opportunity="$(
  opportunity_for_branch \
    "$cancel_accept_order" \
    '99100000-0000-4000-8000-000000000021'
)"

accept_opportunity \
  '99100000-0000-4000-8000-000000000003' \
  "$cancel_accept_opportunity" \
  "wave1-race-cancel-accept-merchant-$run_id" \
  >"$work_dir/cancel-accept-merchant.out" \
  2>"$work_dir/cancel-accept-merchant.err" &
cancel_accept_merchant_pid=$!
cancel_order \
  "$cancel_accept_order" \
  "wave1-race-cancel-accept-customer-$run_id" \
  >"$work_dir/cancel-accept-customer.out" \
  2>"$work_dir/cancel-accept-customer.err" &
cancel_accept_customer_pid=$!

set +e
wait "$cancel_accept_merchant_pid"
cancel_accept_merchant_exit=$?
wait "$cancel_accept_customer_pid"
cancel_accept_customer_exit=$?
set -e

if [[ "$cancel_accept_customer_exit" -ne 0 ]]; then
  cat "$work_dir/cancel-accept-customer.err" >&2
  exit 1
fi
assert_cancelled_and_released "$cancel_accept_order"

# Cancellation after a committed pre-payment winner releases every resource.
post_winner_order="$(submit_order "wave1-race-post-winner-$run_id")"
post_winner_opportunity="$(
  opportunity_for_branch \
    "$post_winner_order" \
    '99100000-0000-4000-8000-000000000021'
)"
accept_opportunity \
  '99100000-0000-4000-8000-000000000003' \
  "$post_winner_opportunity" \
  "wave1-race-post-winner-accept-$run_id" >/dev/null
cancel_order \
  "$post_winner_order" \
  "wave1-race-post-winner-cancel-$run_id" >/dev/null
assert_cancelled_and_released "$post_winner_order"

# Cancel vs Wave 1 expiry. The deadline rewrite is test-only and occurs before
# either racing transaction; production guards remain enabled during the race.
cancel_expiry_order="$(submit_order "wave1-race-cancel-expiry-$run_id")"
cancel_expiry_attempt="$(attempt_for_order "$cancel_expiry_order")"
"${psql_base[@]}" -v order_id="$cancel_expiry_order" <<'SQL'
alter table dastak_v1.matching_attempts disable trigger matching_attempts_guard;
alter table dastak_v1.merchant_opportunities disable trigger merchant_opportunities_guard;
update dastak_v1.matching_attempts
set started_at = now() - interval '4 minutes',
    expires_at = now() - interval '1 minute'
where order_id = :'order_id'::uuid and wave = 'WAVE_1';
update dastak_v1.merchant_opportunities
set started_at = now() - interval '4 minutes',
    expires_at = now() - interval '1 minute'
where order_id = :'order_id'::uuid;
alter table dastak_v1.merchant_opportunities enable trigger merchant_opportunities_guard;
alter table dastak_v1.matching_attempts enable trigger matching_attempts_guard;
SQL

cancel_order \
  "$cancel_expiry_order" \
  "wave1-race-cancel-expiry-customer-$run_id" \
  >"$work_dir/cancel-expiry-customer.out" \
  2>"$work_dir/cancel-expiry-customer.err" &
cancel_expiry_customer_pid=$!
"${psql_base[@]}" -At -v attempt_id="$cancel_expiry_attempt" \
  >"$work_dir/cancel-expiry-worker.out" \
  2>"$work_dir/cancel-expiry-worker.err" <<'SQL' &
select dastak_v1_api.expire_wave1_attempt(:'attempt_id'::uuid);
SQL
cancel_expiry_worker_pid=$!

set +e
wait "$cancel_expiry_customer_pid"
cancel_expiry_customer_exit=$?
wait "$cancel_expiry_worker_pid"
cancel_expiry_worker_exit=$?
set -e

if [[ "$cancel_expiry_customer_exit" -ne 0 || "$cancel_expiry_worker_exit" -ne 0 ]]; then
  cat "$work_dir/cancel-expiry-customer.err" >&2
  cat "$work_dir/cancel-expiry-worker.err" >&2
  exit 1
fi
assert_cancelled_and_released "$cancel_expiry_order"

printf 'Dastak V1 Wave 1 concurrency and cancellation races passed.\n'
