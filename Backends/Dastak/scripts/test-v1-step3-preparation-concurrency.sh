#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-step3.XXXXXX")"
run_token="$(date +%s)$$"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)
customer_id='99200000-0000-4000-8000-000000000001'
merchant_a='99200000-0000-4000-8000-000000000003'
merchant_c='99200000-0000-4000-8000-000000000005'
branch_a='99200000-0000-4000-8000-000000000021'

if [[ "$("${psql_base[@]}" -Atc "select count(*) from public.accounts where id = '$merchant_c'::uuid")" == "0" ]]; then
  "$(dirname "$0")/test-v1-wave2-payment-concurrency.sh"
fi

merchant_call() {
  local actor_id="$1" sql="$2" output="$3"
  "${psql_base[@]}" -v actor_id="$actor_id" >"$output" 2>&1 <<SQL
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'actor_id', true);
$sql
commit;
SQL
}

expect_merchant_failure() {
  local label="$1" pattern="$2" actor_id="$3" sql="$4"
  if merchant_call "$actor_id" "$sql" "$work_dir/failure.out"; then
    printf '%s unexpectedly succeeded.\n' "$label" >&2
    exit 1
  fi
  grep -Eiq "$pattern" "$work_dir/failure.out" || {
    printf '%s failed for the wrong reason:\n' "$label" >&2
    cat "$work_dir/failure.out" >&2
    exit 1
  }
}

expect_database_failure() {
  local label="$1" pattern="$2" sql="$3"
  if "${psql_base[@]}" -c "$sql" >"$work_dir/failure.out" 2>&1; then
    printf '%s unexpectedly succeeded.\n' "$label" >&2
    exit 1
  fi
  grep -Eiq "$pattern" "$work_dir/failure.out" || {
    printf '%s failed for the wrong reason:\n' "$label" >&2
    cat "$work_dir/failure.out" >&2
    exit 1
  }
}

base_order="$("${psql_base[@]}" -Atc "
  select customer_order.id
  from dastak_v1.orders customer_order
  join dastak_v1.payments payment on payment.order_id = customer_order.id
  where customer_order.customer_id = '$customer_id'::uuid
    and customer_order.status = 'PREPARING'
    and payment.status = 'SUCCEEDED'
  order by customer_order.created_at desc limit 1
")"
[[ -n "$base_order" ]] || { printf 'Step 3 requires the Step 2 paid fixture.\n' >&2; exit 1; }
base_fulfilment="$("${psql_base[@]}" -Atc "select id from dastak_v1.fulfilments where order_id = '$base_order'::uuid order by id limit 1")"

prep_truth="$("${psql_base[@]}" -At -F ' ' -c "
select
  (select count(*) from dastak_v1.orders where id = '$base_order'::uuid and status = 'PREPARING'),
  (select count(*) from dastak_v1.fulfilments where order_id = '$base_order'::uuid and status = 'PREPARING' and prep_started_at is not null and estimated_ready_at = prep_started_at + pg_catalog.make_interval(mins => promised_prep_minutes)),
  (select count(*) from dastak_v1.order_state_journal where order_id = '$base_order'::uuid and to_status = 'PAID'),
  (select count(*) from dastak_v1.order_state_journal where order_id = '$base_order'::uuid and to_status = 'PREPARING'),
  (select count(*) from dastak_v1.domain_events_outbox where aggregate_type = 'ORDER' and aggregate_id = '$base_order'::uuid and event_type = 'PREPARATION_STARTED')
")"
[[ "$prep_truth" == "1 1 1 1 1" ]] || { printf 'Payment preparation invariant failed: %s\n' "$prep_truth" >&2; exit 1; }

read -r provider_order provider_payment amount prep_before <<<"$("${psql_base[@]}" -At -F ' ' -c "
select attempt.provider_order_reference, attempt.provider_payment_reference,
       attempt.amount_paise, extract(epoch from fulfilment.prep_started_at)::bigint
from dastak_v1.payment_attempts attempt
join dastak_v1.fulfilments fulfilment on fulfilment.order_id = attempt.order_id
where attempt.order_id = '$base_order'::uuid and attempt.status = 'SUCCEEDED'
limit 1
")"
"${psql_base[@]}" -At -c "
set role service_role;
select response_status from public.dastak_v1_record_razorpay_event(
  'event_step3duplicate$run_token', 'payment_captured', '$provider_order', '$provider_payment', null,
  '$amount'::bigint, pg_catalog.clock_timestamp(), repeat('b', 64)
)" >/dev/null
prep_after="$("${psql_base[@]}" -Atc "select extract(epoch from prep_started_at)::bigint from dastak_v1.fulfilments where id = '$base_fulfilment'::uuid")"
[[ "$prep_before" == "$prep_after" ]] || { printf 'Duplicate payment reset preparation.\n' >&2; exit 1; }

"${psql_base[@]}" -c "
alter table dastak_v1.fulfilments disable trigger fulfilments_guard;
update dastak_v1.fulfilments
set committed_at = pg_catalog.statement_timestamp() - interval '12 minutes',
    prep_started_at = pg_catalog.statement_timestamp() - interval '11 minutes',
    estimated_ready_at = pg_catalog.statement_timestamp() - interval '1 minute'
where id = '$base_fulfilment'::uuid;
alter table dastak_v1.fulfilments enable trigger fulfilments_guard
" >/dev/null
late_truth="$("${psql_base[@]}" -At -F ' ' -c "
select
  (status = 'PREPARING' and actual_ready_at is null)::integer,
  (pg_catalog.clock_timestamp() > estimated_ready_at)::integer,
  (extract(epoch from (pg_catalog.clock_timestamp() - estimated_ready_at)) > 0)::integer
from dastak_v1.fulfilments where id = '$base_fulfilment'::uuid
")"
[[ "$late_truth" == "1 1 1" ]] || { printf 'Running Late state failed: %s\n' "$late_truth" >&2; exit 1; }
"${psql_base[@]}" -c "
alter table dastak_v1.fulfilments disable trigger fulfilments_guard;
update dastak_v1.fulfilments
set prep_started_at = pg_catalog.statement_timestamp(),
    estimated_ready_at = pg_catalog.statement_timestamp() + interval '10 minutes'
where id = '$base_fulfilment'::uuid;
alter table dastak_v1.fulfilments enable trigger fulfilments_guard
" >/dev/null

expected_version="$("${psql_base[@]}" -Atc "select version from dastak_v1.fulfilments where id = '$base_fulfilment'::uuid")"
expect_database_failure "Prep extension" "cannot change|cannot be extended" \
  "update dastak_v1.fulfilments set promised_prep_minutes = promised_prep_minutes + 5, version = version + 1 where id = '$base_fulfilment'::uuid"
expect_merchant_failure "Ready without packages" "declare package count" "$merchant_c" \
  "select public.dastak_v1_mark_fulfilment_ready('$base_fulfilment'::uuid, 'step3-no-packages-$run_token', $expected_version);"

merchant_call "$merchant_c" "select public.dastak_v1_declare_fulfilment_packages('$base_fulfilment'::uuid, 'step3-packages-$run_token', $expected_version, 2);" "$work_dir/packages.out"
expected_version=$((expected_version + 1))
expect_merchant_failure "Ready without evidence" "Ready evidence is required" "$merchant_c" \
  "select public.dastak_v1_mark_fulfilment_ready('$base_fulfilment'::uuid, 'step3-no-evidence-$run_token', $expected_version);"

suffix="$(printf '%012d' "$((run_token % 1000000000000))")"
evidence_id="99300000-0000-4000-8000-$suffix"
evidence_path="merchant-ready/$merchant_c/$evidence_id.jpg"
"${psql_base[@]}" -c "
insert into storage.objects(bucket_id, name, owner, owner_id, metadata)
values('dastak-evidence', '$evidence_path', '$merchant_c'::uuid, '$merchant_c', '{\"mimetype\":\"image/jpeg\",\"size\":2048}'::jsonb)
" >/dev/null
merchant_call "$merchant_c" "select public.dastak_v1_add_fulfilment_ready_evidence('$base_fulfilment'::uuid, null, '$evidence_path', 'step3-evidence-$run_token', $expected_version);" "$work_dir/evidence.out"
expected_version=$((expected_version + 1))

merchant_call "$merchant_c" "select public.dastak_v1_mark_fulfilment_ready('$base_fulfilment'::uuid, 'step3-ready-$run_token', $expected_version);" "$work_dir/ready-a.out" &
ready_a_pid=$!
merchant_call "$merchant_c" "select public.dastak_v1_mark_fulfilment_ready('$base_fulfilment'::uuid, 'step3-ready-$run_token', $expected_version);" "$work_dir/ready-b.out" &
ready_b_pid=$!
wait "$ready_a_pid"; wait "$ready_b_pid"

ready_truth="$("${psql_base[@]}" -At -F ' ' -c "
select
  (select count(*) from dastak_v1.fulfilments where id = '$base_fulfilment'::uuid and status = 'READY' and actual_ready_at is not null and actual_ready_at < estimated_ready_at),
  (select count(*) from dastak_v1.packages where fulfilment_id = '$base_fulfilment'::uuid and status = 'READY'),
  (select count(*) from dastak_v1.retail_capacity_slots where fulfilment_id = '$base_fulfilment'::uuid and status = 'RELEASED' and version = 2),
  (select count(*) from dastak_v1.domain_events_outbox where aggregate_type = 'FULFILMENT' and aggregate_id = '$base_fulfilment'::uuid and event_type = 'FULFILMENT_READY'),
  (select count(*) from dastak_v1.fulfilment_evidence where fulfilment_id = '$base_fulfilment'::uuid and evidence_type = 'MERCHANT_READY_PHOTO')
")"
[[ "$ready_truth" == "1 2 1 1 1" ]] || { printf 'Ready/capacity invariant failed: %s\n' "$ready_truth" >&2; exit 1; }

ready_version="$("${psql_base[@]}" -Atc "select version from dastak_v1.fulfilments where id = '$base_fulfilment'::uuid")"
expect_database_failure "READY regression" "invalid fulfilment transition" \
  "update dastak_v1.fulfilments set status = 'PREPARING', version = version + 1 where id = '$base_fulfilment'::uuid"
expect_database_failure "Ready package mutation" "declared package count cannot change" \
  "update dastak_v1.fulfilments set package_count = package_count + 1, version = version + 1 where id = '$base_fulfilment'::uuid"
expect_database_failure "Evidence overwrite" "append-only" \
  "update dastak_v1.fulfilment_evidence set object_path = object_path || '.changed' where fulfilment_id = '$base_fulfilment'::uuid"
expect_database_failure "Evidence delete" "append-only" \
  "delete from dastak_v1.fulfilment_evidence where fulfilment_id = '$base_fulfilment'::uuid"
expect_merchant_failure "Merchant isolation" "permission denied" "$merchant_a" \
  "select public.dastak_v1_report_fulfilment_problem('$base_fulfilment'::uuid, 'Wrong merchant must not see this', 'step3-isolation-$run_token', $ready_version);"

merchant_call "$merchant_c" "select public.dastak_v1_report_fulfilment_problem('$base_fulfilment'::uuid, 'Package label needs operator review', 'step3-problem-$run_token', $ready_version);" "$work_dir/problem.out"
post_problem="$("${psql_base[@]}" -At -F ' ' -c "select (select count(*) from dastak_v1.fulfilments where id = '$base_fulfilment'::uuid and status = 'READY' and actual_ready_at is not null), (select count(*) from dastak_v1.fulfilment_problem_reports where fulfilment_id = '$base_fulfilment'::uuid), (select count(*) from dastak_v1.fulfilment_evidence where fulfilment_id = '$base_fulfilment'::uuid)")"
[[ "$post_problem" == "1 1 1" ]] || { printf 'Post-Ready problem history was not preserved.\n' >&2; exit 1; }

order_version="$("${psql_base[@]}" -Atc "select version from dastak_v1.orders where id = '$base_order'::uuid")"
if "${psql_base[@]}" -v customer_id="$customer_id" -v order_id="$base_order" -v order_version="$order_version" >"$work_dir/cancel.out" 2>&1 <<'SQL'
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', :'customer_id', true);
select public.dastak_v1_cancel_prepayment_order(:'order_id'::uuid, 'step3-paid-cancel', :'order_version'::bigint);
commit;
SQL
then
  printf 'Post-payment customer cancellation unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -Eiq 'not allowed after payment|only allowed before payment' "$work_dir/cancel.out"

threshold_truth="$("${psql_base[@]}" -At -F ' ' -c "select dastak_v1.fulfilment_rider_match_eligible_at('PREPARING','2026-08-22 12:05:01+00','2026-08-22 12:00:00+00')::integer, dastak_v1.fulfilment_rider_match_eligible_at('PREPARING','2026-08-22 12:05:00+00','2026-08-22 12:00:00+00')::integer, dastak_v1.fulfilment_rider_match_eligible_at('READY','2026-08-22 13:00:00+00','2026-08-22 12:00:00+00')::integer")"
[[ "$threshold_truth" == "0 1 1" ]] || { printf 'Rider threshold boundary failed: %s\n' "$threshold_truth" >&2; exit 1; }

attempt_id="$("${psql_base[@]}" -Atc "select id from dastak_v1.matching_attempts where order_id = '$base_order'::uuid and wave = 'WAVE_1'")"
second_opportunity="$("${psql_base[@]}" -At -c "
insert into dastak_v1.merchant_opportunities(
  matching_attempt_id, order_id, organization_id, branch_id, wave,
  status, started_at, expires_at
)
select '$attempt_id'::uuid, '$base_order'::uuid, branch.organization_id, branch.id,
       'WAVE_1', 'LOST', pg_catalog.statement_timestamp() - interval '10 minutes',
       pg_catalog.statement_timestamp() - interval '5 minutes'
from dastak_v1.merchant_branches branch where branch.id = '$branch_a'::uuid
returning id
")"
second_fulfilment="$("${psql_base[@]}" -At -c "
insert into dastak_v1.fulfilments(
  order_id, organization_id, branch_id, source_opportunity_id,
  fulfilment_type, status, promised_prep_minutes, committed_at,
  prep_started_at, estimated_ready_at
)
select '$base_order'::uuid, opportunity.organization_id, opportunity.branch_id,
       opportunity.id, 'RETAIL', 'PREPARING', 10,
       pg_catalog.statement_timestamp() - interval '6 minutes',
       pg_catalog.statement_timestamp() - interval '4 minutes 59 seconds',
       pg_catalog.statement_timestamp() + interval '5 minutes 1 second'
from dastak_v1.merchant_opportunities opportunity
where opportunity.id = '$second_opportunity'::uuid
returning id
")"
multi_before="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_rider_match_eligibility('$base_order'::uuid, pg_catalog.clock_timestamp()) ->> 'eligible'")"
[[ "$multi_before" == "false" ]] || { printf 'Multi-fulfilment ALL predicate accepted 05:01.\n' >&2; exit 1; }
"${psql_base[@]}" -c "
alter table dastak_v1.fulfilments disable trigger fulfilments_guard;
update dastak_v1.fulfilments
set prep_started_at = pg_catalog.statement_timestamp() - interval '5 minutes',
    estimated_ready_at = pg_catalog.statement_timestamp() + interval '5 minutes'
where id = '$second_fulfilment'::uuid;
alter table dastak_v1.fulfilments enable trigger fulfilments_guard
" >/dev/null
multi_after="$("${psql_base[@]}" -Atc "select dastak_v1_api.order_rider_match_eligibility('$base_order'::uuid, pg_catalog.clock_timestamp()) ->> 'eligible'")"
[[ "$multi_after" == "true" ]] || { printf 'Multi-fulfilment ALL predicate rejected 05:00.\n' >&2; exit 1; }

printf 'Dastak V1 preparation, Ready, package and evidence runtime races passed.\n'
