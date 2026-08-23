#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-restaurant.XXXXXX")"
run_token="$(date +%s)$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
customer_id='99800000-0000-4000-8000-000000000001'
merchant_id='99800000-0000-4000-8000-000000000003'
restaurant_branch='99800000-0000-4000-8000-000000000021'
retail_branch='99800000-0000-4000-8000-000000000031'
menu_item='99800000-0000-4000-8000-000000000041'
menu_option='99800000-0000-4000-8000-000000000043'
retail_sku='99800000-0000-4000-8000-000000000052'

# Reuse the executable Restaurant fixture contract under an isolated UUID namespace.
# The fixture is committed only in the disposable local test database.
if [[ "$("${psql_base[@]}" -Atc "select count(*) from public.accounts where id='$customer_id'::uuid")" == "0" ]]; then
  sed -e 's/99700000/99800000/g' -e 's/^rollback;$/commit;/' \
    "$(dirname "$0")/../supabase/tests/database/037_dastak_v1_restaurant_cafe.pgtap.sql" \
    | "${psql_base[@]}" >"$work_dir/fixture.out"
fi

submit_food() {
  local key="$1"
  "${psql_base[@]}" -At -v actor_id="$customer_id" -v key="$key" \
    -v branch_id="$restaurant_branch" -v menu_item="$menu_item" \
    -v menu_option="$menu_option" <<'SQL' | tail -n 1
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_submit_order(
  :'key',0,pg_catalog.jsonb_build_object(
    'restaurantBranchId',:'branch_id',
    'deliveryAddress',pg_catalog.jsonb_build_object(
      'line1','1 Restaurant Race Road','countryCode','IN',
      'latitude',12.68,'longitude',78.63),
    'recipient',pg_catalog.jsonb_build_object(
      'name','Restaurant Race Customer','phoneNumber','+919980000001'),
    'lines',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'lineType','FOOD_MENU_ITEM','menuItemId',:'menu_item',
      'optionIds',pg_catalog.jsonb_build_array(:'menu_option'),'quantity',1))
  )
)->>'id';
commit;
SQL
}

submit_mixed() {
  local key="$1"
  "${psql_base[@]}" -At -v actor_id="$customer_id" -v key="$key" \
    -v branch_id="$restaurant_branch" -v menu_item="$menu_item" \
    -v menu_option="$menu_option" -v sku_id="$retail_sku" <<'SQL' | tail -n 1
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_submit_order(
  :'key',0,pg_catalog.jsonb_build_object(
    'restaurantBranchId',:'branch_id',
    'deliveryAddress',pg_catalog.jsonb_build_object(
      'line1','2 Mixed Race Road','countryCode','IN',
      'latitude',12.68,'longitude',78.63),
    'recipient',pg_catalog.jsonb_build_object(
      'name','Restaurant Race Customer','phoneNumber','+919980000001'),
    'lines',pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'lineType','FOOD_MENU_ITEM','menuItemId',:'menu_item',
        'optionIds',pg_catalog.jsonb_build_array(:'menu_option'),'quantity',1),
      pg_catalog.jsonb_build_object(
        'lineType','RETAIL_SKU','skuId',:'sku_id','quantity',1))
  )
)->>'id';
commit;
SQL
}

request_for() {
  "${psql_base[@]}" -At -v order_id="$1" <<'SQL'
select id from dastak_v1.restaurant_order_requests where order_id=:'order_id'::uuid;
SQL
}

run_restaurant_response() {
  local request_id="$1" response="$2" key="$3" output="$4"
  local prep_sql='null' reason_sql="'Kitchen cannot accept this order'"
  if [[ "$response" == "CONFIRM" ]]; then prep_sql='20'; reason_sql='null'; fi
  "${psql_base[@]}" -v actor_id="$merchant_id" -v request_id="$request_id" \
    -v key="$key" >"$output" 2>&1 <<SQL
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_respond_restaurant_request(
  :'request_id'::uuid,'$response',$prep_sql,$reason_sql,1,:'key'
);
commit;
SQL
}

run_customer_cancel() {
  local order_id="$1" key="$2" output="$3"
  "${psql_base[@]}" -v actor_id="$customer_id" -v order_id="$order_id" \
    -v key="$key" >"$output" 2>&1 <<'SQL'
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_cancel_prepayment_order(:'order_id'::uuid,:'key',2);
commit;
SQL
}

background_result() {
  local status_file="$1"
  shift
  if "$@"; then printf 'success\n' >"$status_file"; else printf 'failure\n' >"$status_file"; fi
}

assert_one_success() {
  local first="$1" second="$2" label="$3" successes
  successes="$(awk '$1=="success"{count++} END{print count+0}' "$first" "$second")"
  [[ "$successes" == "1" ]] || {
    printf '%s produced %s successful writers instead of one.\n' "$label" "$successes" >&2
    exit 1
  }
}

# CONFIRM and DECLINE race on the same immutable request: one terminal truth wins.
terminal_order="$(submit_food "restaurant-terminal-$run_token")"
terminal_request="$(request_for "$terminal_order")"
background_result "$work_dir/terminal-confirm.status" run_restaurant_response \
  "$terminal_request" CONFIRM "terminal-confirm-$run_token" "$work_dir/terminal-confirm.out" &
confirm_pid=$!
background_result "$work_dir/terminal-decline.status" run_restaurant_response \
  "$terminal_request" DECLINE "terminal-decline-$run_token" "$work_dir/terminal-decline.out" &
decline_pid=$!
wait "$confirm_pid"; wait "$decline_pid"
assert_one_success "$work_dir/terminal-confirm.status" "$work_dir/terminal-decline.status" \
  'Restaurant confirm/decline race'
terminal_truth="$("${psql_base[@]}" -At -F '|' -v order_id="$terminal_order" <<'SQL'
select request.status::text,customer_order.status::text,
  (select count(*) from dastak_v1.fulfilments where order_id=customer_order.id),
  (select count(*) from dastak_v1.restaurant_capacity_commitments where order_id=customer_order.id)
from dastak_v1.orders customer_order
join dastak_v1.restaurant_order_requests request on request.order_id=customer_order.id
where customer_order.id=:'order_id'::uuid;
SQL
)"
[[ "$terminal_truth" == 'CONFIRMED|AWAITING_PAYMENT|1|1' \
   || "$terminal_truth" == 'DECLINED|UNAVAILABLE|0|0' ]] || {
  printf 'Restaurant terminal race left inconsistent truth: %s\n' "$terminal_truth" >&2
  exit 1
}

# Cancellation and confirmation serialize on the parent order and cannot orphan capacity.
cancel_order="$(submit_food "restaurant-cancel-race-$run_token")"
cancel_request="$(request_for "$cancel_order")"
background_result "$work_dir/cancel-confirm.status" run_restaurant_response \
  "$cancel_request" CONFIRM "cancel-confirm-$run_token" "$work_dir/cancel-confirm.out" &
confirm_pid=$!
background_result "$work_dir/cancel.status" run_customer_cancel \
  "$cancel_order" "cancel-order-$run_token" "$work_dir/cancel.out" &
cancel_pid=$!
wait "$confirm_pid"; wait "$cancel_pid"
assert_one_success "$work_dir/cancel-confirm.status" "$work_dir/cancel.status" \
  'Restaurant confirmation/cancellation race'
cancel_truth="$("${psql_base[@]}" -At -F '|' -v order_id="$cancel_order" <<'SQL'
select customer_order.status::text,request.status::text,
  (select count(*) from dastak_v1.fulfilments where order_id=customer_order.id),
  (select count(*) from dastak_v1.restaurant_capacity_commitments
    where order_id=customer_order.id and status='COMMITTED'),
  (select count(*) from dastak_v1.payments
    where order_id=customer_order.id and status='RESERVED')
from dastak_v1.orders customer_order
join dastak_v1.restaurant_order_requests request on request.order_id=customer_order.id
where customer_order.id=:'order_id'::uuid;
SQL
)"
[[ "$cancel_truth" == 'AWAITING_PAYMENT|CONFIRMED|1|1|1' \
   || "$cancel_truth" == 'CANCELLED_PREPAYMENT|RELEASED|0|0|0' ]] || {
  printf 'Restaurant cancellation race left inconsistent truth: %s\n' "$cancel_truth" >&2
  exit 1
}

# The soft threshold remains advisory under real concurrent confirmations.
soft_order_a="$(submit_food "restaurant-soft-a-$run_token")"
soft_order_b="$(submit_food "restaurant-soft-b-$run_token")"
soft_request_a="$(request_for "$soft_order_a")"
soft_request_b="$(request_for "$soft_order_b")"
background_result "$work_dir/soft-a.status" run_restaurant_response \
  "$soft_request_a" CONFIRM "soft-a-$run_token" "$work_dir/soft-a.out" &
soft_a_pid=$!
background_result "$work_dir/soft-b.status" run_restaurant_response \
  "$soft_request_b" CONFIRM "soft-b-$run_token" "$work_dir/soft-b.out" &
soft_b_pid=$!
wait "$soft_a_pid"; wait "$soft_b_pid"
soft_successes="$(awk '$1=="success"{count++} END{print count+0}' \
  "$work_dir/soft-a.status" "$work_dir/soft-b.status")"
[[ "$soft_successes" == "2" ]] || {
  printf 'Soft restaurant capacity rejected a valid concurrent acceptance.\n' >&2
  exit 1
}
soft_truth="$("${psql_base[@]}" -At -v order_a="$soft_order_a" -v order_b="$soft_order_b" <<'SQL'
select count(*) from dastak_v1.restaurant_capacity_commitments
where order_id in (:'order_a'::uuid,:'order_b'::uuid)
  and status='COMMITTED' and accepted_above_threshold;
SQL
)"
[[ "$soft_truth" == "2" ]] || {
  printf 'Soft-threshold snapshots were not preserved for both orders: %s\n' "$soft_truth" >&2
  exit 1
}

# Food and retail confirmations may race, but one mixed parent reaches payment exactly once.
mixed_order="$(submit_mixed "restaurant-mixed-race-$run_token")"
mixed_request="$(request_for "$mixed_order")"
mixed_opportunity="$("${psql_base[@]}" -At -v order_id="$mixed_order" \
  -v branch_id="$retail_branch" <<'SQL'
select id from dastak_v1.merchant_opportunities
where order_id=:'order_id'::uuid and branch_id=:'branch_id'::uuid;
SQL
)"
background_result "$work_dir/mixed-food.status" run_restaurant_response \
  "$mixed_request" CONFIRM "mixed-food-$run_token" "$work_dir/mixed-food.out" &
food_pid=$!
(
  if "${psql_base[@]}" -v actor_id="$merchant_id" -v opportunity_id="$mixed_opportunity" \
    -v key="mixed-retail-$run_token" >"$work_dir/mixed-retail.out" 2>&1 <<'SQL'
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'actor_id', true);
select public.dastak_v1_accept_wave1_opportunity(
  :'opportunity_id'::uuid,:'key',1,10
);
commit;
SQL
  then printf 'success\n' >"$work_dir/mixed-retail.status";
  else printf 'failure\n' >"$work_dir/mixed-retail.status"; fi
) &
retail_pid=$!
wait "$food_pid"; wait "$retail_pid"
mixed_truth="$("${psql_base[@]}" -At -F '|' -v order_id="$mixed_order" <<'SQL'
select customer_order.status::text,
  (select count(*) from dastak_v1.fulfilments where order_id=customer_order.id
    and status='RESERVED_PREPAYMENT'),
  (select count(*) from dastak_v1.payments where order_id=customer_order.id
    and status='RESERVED'),
  (select count(*) from dastak_v1.order_state_journal where order_id=customer_order.id
    and to_status='AWAITING_PAYMENT')
from dastak_v1.orders customer_order where customer_order.id=:'order_id'::uuid;
SQL
)"
[[ "$(<"$work_dir/mixed-food.status")" == 'success' \
   && "$(<"$work_dir/mixed-retail.status")" == 'success'
   && "$mixed_truth" == 'AWAITING_PAYMENT|2|1|1' ]] || {
  printf 'Mixed Restaurant/retail race failed: %s\n' "$mixed_truth" >&2
  exit 1
}

printf 'Restaurant terminal, cancellation, soft-capacity and mixed-order concurrency gates passed.\n'
