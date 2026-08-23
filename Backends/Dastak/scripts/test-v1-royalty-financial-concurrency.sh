#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-royalty.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)

rider_id='94100000-0000-4000-8000-000000000001'
operations_id='94100000-0000-4000-8000-000000000002'

"${psql_base[@]}" <<'SQL'
insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at
) values
('94100000-0000-4000-8000-000000000001',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'royalty-race-rider@example.test','',now(),now(),now()),
('94100000-0000-4000-8000-000000000002',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'royalty-race-operations@example.test','',now(),now(),now())
on conflict(id) do nothing;
insert into public.accounts(id,display_name,phone_number) values
('94100000-0000-4000-8000-000000000001','Royalty Race Rider','+919410000001'),
('94100000-0000-4000-8000-000000000002','Royalty Race Operations','+919410000002')
on conflict(id) do nothing;
insert into private.account_memberships(account_id,role,approved_at) values
('94100000-0000-4000-8000-000000000001','dastak_partner',now()),
('94100000-0000-4000-8000-000000000002','owner',now())
on conflict(account_id,role) do update set approved_at=excluded.approved_at;
insert into private.delivery_partner_applications (
  id,account_id,delivery_method,identity_evidence_object_path,verification_version,
  vehicle_registration_number,vehicle_make_model,vehicle_evidence_object_path,
  status,submitted_at,reviewed_at,reviewed_by
) values (
  '94100000-0000-4000-8000-000000000010',
  '94100000-0000-4000-8000-000000000001','motorbike',
  'test/royalty-race/identity.pdf',2,'TN 01 RR 0001','Royalty Race Motorbike',
  'test/royalty-race/vehicle.pdf','approved',now(),now(),
  '94100000-0000-4000-8000-000000000002'
) on conflict(id) do nothing;
insert into private.delivery_partner_profiles(
  account_id,approved_application_id,delivery_method
) values (
  '94100000-0000-4000-8000-000000000001',
  '94100000-0000-4000-8000-000000000010','motorbike'
) on conflict(account_id) do update set delivery_method=excluded.delivery_method;
insert into dastak_v1.platform_permission_grants(
  account_id,bundle_id,granted_by,grant_reason
)
select '94100000-0000-4000-8000-000000000002',bundle.id,
  '94100000-0000-4000-8000-000000000002',
  'Royalty concurrency payout permission.'
from dastak_v1.permission_bundles bundle
where bundle.id='10000000-0000-4000-8000-000000000009'
and not exists (
  select 1 from dastak_v1.platform_permission_grants grant_row
  where grant_row.account_id='94100000-0000-4000-8000-000000000002'
    and grant_row.bundle_id=bundle.id and grant_row.revoked_at is null
);
select dastak_v1_api.post_balanced_financial_transaction(
  'RACE:RIDER:EARNING:BASE','RIDER_ROYALTY_EARNING',50000,
  'RIDER_DELIVERY_COST',null,null,
  'RIDER_ROYALTY_PAYABLE','RIDER','94100000-0000-4000-8000-000000000001',
  null,null,null,null,null,null,null,null,
  'Royalty concurrency base earning.','{"test":true}'
);
select dastak_v1_api.register_royalty_payout_destination(
  '94100000-0000-4000-8000-000000000001','RIDER',
  '94100000-0000-4000-8000-000000000001','PROVIDER_DESTINATION',
  'TEST_PAYOUT','royalty-race-destination','Test payout • race','{"test":true}'
);
SQL

set +e
"${psql_base[@]}" -Atc "
select dastak_v1_api.request_royalty_withdrawal(
  '$rider_id','RIDER','$rider_id',40000,'race-withdrawal-a'
);" >"$work_dir/withdraw-a.out" 2>"$work_dir/withdraw-a.err" &
pid_a=$!
"${psql_base[@]}" -Atc "
select dastak_v1_api.request_royalty_withdrawal(
  '$rider_id','RIDER','$rider_id',40000,'race-withdrawal-b'
);" >"$work_dir/withdraw-b.out" 2>"$work_dir/withdraw-b.err" &
pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if [[ "$status_a" -eq 0 && "$status_b" -eq 0 ]] ||
   [[ "$status_a" -ne 0 && "$status_b" -ne 0 ]]; then
  echo "expected exactly one concurrent withdrawal winner" >&2
  exit 1
fi

withdrawal_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.royalty_withdrawals
where subject_type='RIDER' and subject_id='$rider_id';
")"
balance_after_reservation="$("${psql_base[@]}" -Atc "
select dastak_v1_api.royalty_balance_paise('RIDER','$rider_id');
")"
if [[ "$withdrawal_count" != "1" || "$balance_after_reservation" != "10000" ]]; then
  echo "concurrent withdrawals overspent or failed to reserve exactly once" >&2
  exit 1
fi

withdrawal_id="$("${psql_base[@]}" -Atc "
select id from dastak_v1.royalty_withdrawals
where subject_type='RIDER' and subject_id='$rider_id';
")"
attempt_id="$("${psql_base[@]}" -Atc "
select dastak_v1_api.start_royalty_withdrawal(
  '$operations_id','$withdrawal_id',1,'race-provider-request'
)->>'attemptId';
")"

set +e
for suffix in a b; do
  "${psql_base[@]}" -Atc "
  select dastak_v1_api.record_royalty_withdrawal_result(
    '$withdrawal_id','$attempt_id','TEST_PAYOUT','race-provider-event',
    'PAID','race-payout-reference',null,repeat('c',64),
    jsonb_build_object('test',true),now()
  );" >"$work_dir/callback-$suffix.out" 2>"$work_dir/callback-$suffix.err" &
  if [[ "$suffix" == "a" ]]; then callback_a=$!; else callback_b=$!; fi
done
wait "$callback_a"; callback_status_a=$?
wait "$callback_b"; callback_status_b=$?
set -e
if [[ "$callback_status_a" -ne 0 || "$callback_status_b" -ne 0 ]]; then
  for suffix in a b; do
    if [[ -s "$work_dir/callback-$suffix.err" ]]; then
      echo "callback $suffix error:" >&2
      command cat "$work_dir/callback-$suffix.err" >&2
    fi
  done
  echo "duplicate concurrent payout callback was not idempotent" >&2
  exit 1
fi

provider_event_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.royalty_withdrawal_provider_events
where provider='TEST_PAYOUT' and provider_event_id='race-provider-event';
")"
paid_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.royalty_withdrawals
where id='$withdrawal_id' and status='PAID'
  and provider_payout_reference='race-payout-reference';
")"
if [[ "$provider_event_count" != "1" || "$paid_count" != "1" ]]; then
  echo "payout callback duplicated or failed to finalize exactly once" >&2
  exit 1
fi

set +e
for suffix in a b; do
  "${psql_base[@]}" -Atc "
  select dastak_v1_api.post_balanced_financial_transaction(
    'RACE:RIDER:EARNING:RETRY','RIDER_ROYALTY_EARNING',9000,
    'RIDER_DELIVERY_COST',null,null,
    'RIDER_ROYALTY_PAYABLE','RIDER','$rider_id',
    null,null,null,null,null,null,null,null,
    'Concurrent earning retry.',jsonb_build_object('test',true)
  );" >"$work_dir/earning-$suffix.out" 2>"$work_dir/earning-$suffix.err" &
  if [[ "$suffix" == "a" ]]; then earning_a=$!; else earning_b=$!; fi
done
wait "$earning_a"; earning_status_a=$?
wait "$earning_b"; earning_status_b=$?
set -e
if [[ "$earning_status_a" -ne 0 || "$earning_status_b" -ne 0 ]]; then
  echo "concurrent earning credit retries were not idempotent" >&2
  exit 1
fi

earning_count="$("${psql_base[@]}" -Atc "
select count(*) from dastak_v1.financial_journal_transactions
where transaction_key='RACE:RIDER:EARNING:RETRY';
")"
final_balance="$("${psql_base[@]}" -Atc "
select dastak_v1_api.royalty_balance_paise('RIDER','$rider_id');
")"
if [[ "$earning_count" != "1" || "$final_balance" != "19000" ]]; then
  echo "earning retry duplicated credit or produced the wrong derived balance" >&2
  exit 1
fi

echo "Dastak V1 Royalty financial concurrency gates passed."
