#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-razorpayx.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)

rider_id='94300000-0000-4000-8000-000000000001'
operations_id='94300000-0000-4000-8000-000000000002'

"${psql_base[@]}" <<'SQL'
insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at
) values
('94300000-0000-4000-8000-000000000001',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'razorpayx-race-rider@example.test','',now(),now(),now()),
('94300000-0000-4000-8000-000000000002',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'razorpayx-race-operations@example.test','',now(),now(),now())
on conflict(id) do nothing;
insert into public.accounts(id,display_name,phone_number) values
('94300000-0000-4000-8000-000000000001','RazorpayX Race Rider','+919430000001'),
('94300000-0000-4000-8000-000000000002','RazorpayX Race Operations','+919430000002')
on conflict(id) do nothing;
insert into private.account_memberships(account_id,role,approved_at) values
('94300000-0000-4000-8000-000000000001','dastak_partner',now()),
('94300000-0000-4000-8000-000000000002','owner',now())
on conflict(account_id,role) do update set approved_at=excluded.approved_at;
insert into private.delivery_partner_applications (
  id,account_id,delivery_method,identity_evidence_object_path,verification_version,
  vehicle_registration_number,vehicle_make_model,vehicle_evidence_object_path,
  status,submitted_at,reviewed_at,reviewed_by
) values (
  '94300000-0000-4000-8000-000000000010',
  '94300000-0000-4000-8000-000000000001','motorbike',
  'test/razorpayx-race/identity.pdf',2,'TN 01 RX 0002','RazorpayX Race Motorbike',
  'test/razorpayx-race/vehicle.pdf','approved',now(),now(),
  '94300000-0000-4000-8000-000000000002'
) on conflict(id) do nothing;
insert into private.delivery_partner_profiles(
  account_id,approved_application_id,delivery_method
) values (
  '94300000-0000-4000-8000-000000000001',
  '94300000-0000-4000-8000-000000000010','motorbike'
) on conflict(account_id) do update set delivery_method=excluded.delivery_method;
insert into dastak_v1.platform_permission_grants(
  account_id,bundle_id,granted_by,grant_reason
)
select '94300000-0000-4000-8000-000000000002',bundle.id,
  '94300000-0000-4000-8000-000000000002','RazorpayX race permission.'
from dastak_v1.permission_bundles bundle
where bundle.id='10000000-0000-4000-8000-000000000009'
and not exists (
  select 1 from dastak_v1.platform_permission_grants grant_row
  where grant_row.account_id='94300000-0000-4000-8000-000000000002'
    and grant_row.bundle_id=bundle.id and grant_row.revoked_at is null
);
select dastak_v1_api.post_balanced_financial_transaction(
  'RACE:RAZORPAYX:EARNING','RIDER_ROYALTY_EARNING',50000,
  'RIDER_DELIVERY_COST',null,null,
  'RIDER_ROYALTY_PAYABLE','RIDER','94300000-0000-4000-8000-000000000001',
  null,null,null,null,null,null,null,null,
  'RazorpayX concurrency earning.','{"test":true}'
);
select dastak_v1_api.finalize_razorpayx_payout_destination(
  '94300000-0000-4000-8000-000000000001','RIDER',
  '94300000-0000-4000-8000-000000000001','UPI',
  'cont_razorpayxrace','fa_razorpayxrace',
  '94300000-0000-4000-8000-000000000001','RazorpayX Race Rider',
  'UPI • ra***@okaxis',repeat('a',64),'{"maskedAddress":"ra***@okaxis"}'
);
SQL

withdrawal_id="$("${psql_base[@]}" -Atc "
select dastak_v1_api.request_royalty_withdrawal(
  '$rider_id','RIDER','$rider_id',30000,'razorpayx-race-withdrawal'
)->>'withdrawalId';
")"

set +e
for suffix in a b; do
  "${psql_base[@]}" -Atc "
  select dastak_v1_api.claim_razorpayx_withdrawal(
    '$rider_id','$withdrawal_id',1
  );" >"$work_dir/claim-$suffix.out" 2>"$work_dir/claim-$suffix.err" &
  if [[ "$suffix" == "a" ]]; then claim_a=$!; else claim_b=$!; fi
done
wait "$claim_a"; claim_status_a=$?
wait "$claim_b"; claim_status_b=$?
set -e
if [[ "$claim_status_a" -eq 0 && "$claim_status_b" -eq 0 ]] ||
   [[ "$claim_status_a" -ne 0 && "$claim_status_b" -ne 0 ]]; then
  echo "expected exactly one simultaneous withdrawal execution claim" >&2
  exit 1
fi

attempt_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.royalty_withdrawal_attempts
where withdrawal_id='$withdrawal_id' and provider='RAZORPAYX';
")"
payout_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.razorpayx_payouts
where withdrawal_id='$withdrawal_id' and payout_idempotency_key='$withdrawal_id';
")"
if [[ "$attempt_count" != "1" || "$payout_count" != "1" ]]; then
  echo "simultaneous execution created duplicate external payout state" >&2
  exit 1
fi

apply_event_concurrently() {
  local event_id="$1"
  local event_type="$2"
  local provider_status="$3"
  local digest="$4"
  local occurred_at="$5"
  set +e
  for suffix in a b; do
    "${psql_base[@]}" -Atc "
    select dastak_v1_api.apply_razorpayx_payout_status(
      '$event_id','WEBHOOK','$withdrawal_id',null,
      'pout_razorpayxrace','$event_type','$provider_status',30000,'INR',
      'fa_razorpayxrace',repeat('$digest',64),'{}','$occurred_at',
      '2026-08-23T12:59:00Z',null,'{}'
    );" >"$work_dir/$event_id-$suffix.out" 2>"$work_dir/$event_id-$suffix.err" &
    if [[ "$suffix" == "a" ]]; then callback_a=$!; else callback_b=$!; fi
  done
  wait "$callback_a"; callback_status_a=$?
  wait "$callback_b"; callback_status_b=$?
  set -e
  if [[ "$callback_status_a" -ne 0 || "$callback_status_b" -ne 0 ]]; then
    command cat "$work_dir/$event_id-a.err" "$work_dir/$event_id-b.err" >&2
    echo "concurrent duplicate $provider_status webhook was not replay-safe" >&2
    exit 1
  fi
}

apply_event_concurrently \
  'evt-razorpayx-race-paid' 'payout.processed' 'processed' 'b' \
  '2026-08-23T13:00:00Z'

paid_event_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.razorpayx_provider_events
where provider_event_id='evt-razorpayx-race-paid';
")"
paid_transaction_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.financial_journal_transactions
where withdrawal_id='$withdrawal_id' and transaction_type='WITHDRAWAL_PAID';
")"
if [[ "$paid_event_count" != "1" || "$paid_transaction_count" != "1" ]]; then
  echo "duplicate success duplicated payout completion" >&2
  exit 1
fi

apply_event_concurrently \
  'evt-razorpayx-race-reversed' 'payout.reversed' 'reversed' 'c' \
  '2026-08-23T13:01:00Z'

reversal_event_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.razorpayx_provider_events
where provider_event_id='evt-razorpayx-race-reversed';
")"
reversal_transaction_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.financial_journal_transactions
where transaction_key='$withdrawal_id:RAZORPAYX_REVERSAL:pout_razorpayxrace';
")"
final_balance="$("${psql_base[@]}" -Atc "
select dastak_v1_api.royalty_balance_paise('RIDER','$rider_id');
")"
if [[ "$reversal_event_count" != "1" || "$reversal_transaction_count" != "1" ||
      "$final_balance" != "50000" ]]; then
  echo "duplicate reversal restored Royalty incorrectly" >&2
  exit 1
fi

echo "Dastak V1 RazorpayX payout concurrency gates passed."
