#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
if [[ ! "$database_url" =~ (127\.0\.0\.1|localhost|\[::1\]) ]]; then
  printf 'Group A concurrency rehearsal is local-only; refusing database URL: %s\n' "$database_url" >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-delivery-group-a.XXXXXX")"
psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)

cleanup() {
  set +e
  "${psql_base[@]}" >/dev/null 2>&1 <<'SQL'
set session_replication_role = replica;
delete from dastak_v1.idempotency_records
where actor_id = md5('group-a-concurrency-owner')::uuid;
delete from dastak_v1.platform_permission_grants
where account_id = md5('group-a-concurrency-owner')::uuid;
delete from dastak_v1.delivery_missions
where id in (
  select md5('group-a-' || label || '-v1')::uuid
  from (values
    ('v1-legacy'),('v1-parcel'),('v1-return'),
    ('compatible-recovery'),('incompatible-source')
  ) labels(label)
);
delete from dastak_v1.return_missions
where id in (
  select md5('group-a-' || label || '-return')::uuid
  from (values
    ('v1-return'),('return-legacy'),('return-parcel'),('replay'),
    ('compatible-recovery'),('incompatible-source')
  ) labels(label)
);
delete from private.delivery_assignment_attempts
where id in (
  select md5('group-a-' || label || '-legacy')::uuid
  from (values
    ('v1-legacy'),('return-legacy'),('legacy-parcel')
  ) labels(label)
);
delete from private.parcel_assignment_attempts
where id in (
  select md5('group-a-' || label || '-parcel')::uuid
  from (values
    ('v1-parcel'),('return-parcel'),('legacy-parcel')
  ) labels(label)
);
delete from private.account_memberships
where account_id = md5('group-a-concurrency-owner')::uuid;
delete from public.accounts
where display_name like 'Group A concurrency%';
delete from auth.users
where email like 'group-a-concurrency-%@example.test';
set session_replication_role = origin;
SQL
  rm -rf "$work_dir"
}
trap cleanup EXIT

"${psql_base[@]}" <<'SQL'
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
select
  account_id,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'authenticated',
  'authenticated',
  email,
  '',
  now(), now(), now()
from (
  select md5('group-a-concurrency-owner')::uuid as account_id,
    'group-a-concurrency-owner@example.test'::text as email
  union all
  select md5('group-a-' || label || '-rider')::uuid,
    'group-a-concurrency-' || label || '@example.test'
  from (values
    ('v1-legacy'),('v1-parcel'),('v1-return'),
    ('return-legacy'),('return-parcel'),('legacy-parcel'),('replay'),
    ('compatible-recovery'),('incompatible-source')
  ) labels(label)
) fixture;

insert into public.accounts (id, display_name, phone_number)
select account_id, display_name, phone_number
from (
  select md5('group-a-concurrency-owner')::uuid as account_id,
    'Group A concurrency owner'::text as display_name,
    '+919750000001'::text as phone_number
  union all
  select md5('group-a-' || label || '-rider')::uuid,
    'Group A concurrency ' || label,
    '+91975' || pg_catalog.lpad(ordinal::text, 7, '0')
  from (values
    ('v1-legacy',101),('v1-parcel',102),('v1-return',103),
    ('return-legacy',104),('return-parcel',105),('legacy-parcel',106),
    ('replay',107),('compatible-recovery',108),('incompatible-source',109)
  ) labels(label, ordinal)
) fixture;

set session_replication_role = replica;
insert into private.account_memberships (account_id, role, approved_at)
values (md5('group-a-concurrency-owner')::uuid, 'owner', now());
insert into dastak_v1.platform_permission_grants (
  id, account_id, bundle_id, granted_by, grant_reason
) values (
  md5('group-a-concurrency-permission')::uuid,
  md5('group-a-concurrency-owner')::uuid,
  '10000000-0000-4000-8000-000000000008'::uuid,
  md5('group-a-concurrency-owner')::uuid,
  'Local Group A idempotency replay fixture.'
);

insert into dastak_v1.delivery_missions (
  id, order_id, status, transport_snapshot, pickup_count,
  delivery_distance_meters, rider_payout_quote_paise,
  rider_payout_quote_snapshot, assigned_rider_id,
  assigned_transport_type, assigned_at
)
select
  md5('group-a-' || label || '-v1')::uuid,
  md5('group-a-' || label || '-v1-order')::uuid,
  case
    when label = 'compatible-recovery' then 'DELIVERY_RECOVERY'
    when label = 'incompatible-source' then 'ASSIGNED'
    else 'SEARCHING_RIDER'
  end::dastak_v1.delivery_mission_status,
  '{}', 1, 1000, 100, '{}',
  case
    when label in ('compatible-recovery', 'incompatible-source')
      then md5('group-a-' || label || '-rider')::uuid
  end,
  case
    when label in ('compatible-recovery', 'incompatible-source')
      then 'MOTORBIKE'::dastak_v1.transport_type
  end,
  case
    when label in ('compatible-recovery', 'incompatible-source') then now()
  end
from (values
  ('v1-legacy'),('v1-parcel'),('v1-return'),
  ('compatible-recovery'),('incompatible-source')
) labels(label);

insert into dastak_v1.return_missions (
  id, return_id, order_id, status,
  assigned_rider_id, assigned_transport_type, assigned_at,
  source_delivery_mission_id
)
select
  md5('group-a-' || label || '-return')::uuid,
  md5('group-a-' || label || '-return-parent')::uuid,
  md5('group-a-' || label || '-return-order')::uuid,
  case when label = 'replay' then 'ASSIGNED' else 'RIDER_SEARCH' end::dastak_v1.return_mission_status,
  case when label = 'replay' then md5('group-a-replay-rider')::uuid end,
  case when label = 'replay' then 'MOTORBIKE'::dastak_v1.transport_type end,
  case when label = 'replay' then now() end,
  case
    when label in ('compatible-recovery', 'incompatible-source')
      then md5('group-a-' || label || '-v1')::uuid
  end
from (values
  ('v1-return'),('return-legacy'),('return-parcel'),('replay'),
  ('compatible-recovery'),('incompatible-source')
) labels(label);

insert into private.delivery_assignment_attempts (
  id, order_id, partner_account_id, attempt_number, status,
  distance_meters, offered_at, respond_by
)
select
  md5('group-a-' || label || '-legacy')::uuid,
  md5('group-a-' || label || '-legacy-order')::uuid,
  md5('group-a-' || label || '-rider')::uuid,
  1, 'offered', 100, now(), now() + interval '5 minutes'
from (values
  ('v1-legacy'),('return-legacy'),('legacy-parcel')
) labels(label);

insert into private.parcel_assignment_attempts (
  id, parcel_id, partner_account_id, attempt_number, status,
  distance_meters, offered_at, respond_by
)
select
  md5('group-a-' || label || '-parcel')::uuid,
  md5('group-a-' || label || '-parcel-parent')::uuid,
  md5('group-a-' || label || '-rider')::uuid,
  1, 'offered', 100, now(), now() + interval '5 minutes'
from (values
  ('v1-parcel'),('return-parcel'),('legacy-parcel')
) labels(label);

insert into dastak_v1.idempotency_records (
  actor_id, command_name, idempotency_key, request_hash,
  response_body, response_status, resource_id
) values (
  md5('group-a-concurrency-owner')::uuid,
  'assignReturnRider',
  'group-a-replay',
  dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'returnMissionId', md5('group-a-replay-return')::uuid,
    'riderId', md5('group-a-replay-rider')::uuid,
    'expectedVersion', 1
  )),
  pg_catalog.jsonb_build_object(
    'returnMissionId', md5('group-a-replay-return')::uuid,
    'missionStatus', 'ASSIGNED',
    'riderId', md5('group-a-replay-rider')::uuid
  ),
  200,
  md5('group-a-replay-return')::uuid
);
set session_replication_role = origin;
SQL

domain_sql() {
  local label="$1"
  local domain="$2"
  case "$domain" in
    v1)
      cat <<SQL
select pg_catalog.pg_sleep(0.25);
update dastak_v1.delivery_missions
set status='ASSIGNED',
    assigned_rider_id=md5('group-a-$label-rider')::uuid,
    assigned_transport_type='MOTORBIKE',
    assigned_at=pg_catalog.clock_timestamp(),
    version=version+1
where id=md5('group-a-$label-v1')::uuid;
SQL
      ;;
    return)
      cat <<SQL
select pg_catalog.pg_sleep(0.25);
update dastak_v1.return_missions
set status='ASSIGNED',
    assigned_rider_id=md5('group-a-$label-rider')::uuid,
    assigned_transport_type='MOTORBIKE',
    assigned_at=pg_catalog.clock_timestamp(),
    version=version+1
where id=md5('group-a-$label-return')::uuid;
SQL
      ;;
    legacy)
      cat <<SQL
select pg_catalog.pg_sleep(0.25);
update private.delivery_assignment_attempts
set status='accepted', responded_at=pg_catalog.clock_timestamp(), updated_at=now()
where id=md5('group-a-$label-legacy')::uuid;
SQL
      ;;
    parcel)
      cat <<SQL
select pg_catalog.pg_sleep(0.25);
update private.parcel_assignment_attempts
set status='acknowledged', responded_at=pg_catalog.clock_timestamp(), updated_at=now()
where id=md5('group-a-$label-parcel')::uuid;
SQL
      ;;
    *)
      printf 'Unknown acquisition domain: %s\n' "$domain" >&2
      return 2
      ;;
  esac
}

run_pair() {
  local label="$1"
  local first="$2"
  local second="$3"
  local first_output="$work_dir/$label-$first.out"
  local second_output="$work_dir/$label-$second.out"

  set +e
  domain_sql "$label" "$first" | "${psql_base[@]}" >"$first_output" 2>&1 &
  local first_pid=$!
  domain_sql "$label" "$second" | "${psql_base[@]}" >"$second_output" 2>&1 &
  local second_pid=$!
  wait "$first_pid"
  local first_rc=$?
  wait "$second_pid"
  local second_rc=$?
  set -e

  local successes=0
  (( first_rc == 0 )) && successes=$((successes + 1))
  (( second_rc == 0 )) && successes=$((successes + 1))
  if (( successes != 1 )); then
    printf '%s + %s expected one acquisition; got rc=%s/%s\n' \
      "$first" "$second" "$first_rc" "$second_rc" >&2
    sed -n '1,120p' "$first_output" >&2
    sed -n '1,120p' "$second_output" >&2
    exit 1
  fi

  local failed_output="$first_output"
  (( first_rc == 0 )) && failed_output="$second_output"
  grep -q 'RIDER_ACTIVE_WORK_CONFLICT' "$failed_output" || {
    printf '%s + %s loser did not receive the structured active-work conflict\n' \
      "$first" "$second" >&2
    sed -n '1,120p' "$failed_output" >&2
    exit 1
  }

  local active_count
  active_count="$("${psql_base[@]}" -Atc "
    select count(*)
    from private.delivery_partner_active_work(
      md5('group-a-$label-rider')::uuid, null, null, null
    )")"
  [[ "$active_count" == '1' ]] || {
    printf '%s + %s left %s authoritative active jobs\n' \
      "$first" "$second" "$active_count" >&2
    exit 1
  }
  printf 'ok - %s + %s serialize to one active job\n' "$first" "$second"
}

run_pair 'v1-legacy' v1 legacy
run_pair 'v1-parcel' v1 parcel
run_pair 'v1-return' v1 return
run_pair 'return-legacy' return legacy
run_pair 'return-parcel' return parcel
run_pair 'legacy-parcel' legacy parcel

"${psql_base[@]}" <<'SQL'
update dastak_v1.return_missions
set status = 'ASSIGNED',
    assigned_rider_id = md5('group-a-compatible-recovery-rider')::uuid,
    assigned_transport_type = 'MOTORBIKE',
    assigned_at = pg_catalog.clock_timestamp(),
    version = version + 1
where id = md5('group-a-compatible-recovery-return')::uuid;
SQL
compatible_status="$("${psql_base[@]}" -Atc "
  select status
  from dastak_v1.return_missions
  where id = md5('group-a-compatible-recovery-return')::uuid")"
[[ "$compatible_status" == 'ASSIGNED' ]] || {
  printf 'a return could not continue its source DELIVERY_RECOVERY custody\n' >&2
  exit 1
}
printf 'ok - return and its source DELIVERY_RECOVERY remain one compatible job\n'

incompatible_output="$work_dir/incompatible-source.out"
set +e
"${psql_base[@]}" >"$incompatible_output" 2>&1 <<'SQL'
update dastak_v1.return_missions
set status = 'ASSIGNED',
    assigned_rider_id = md5('group-a-incompatible-source-rider')::uuid,
    assigned_transport_type = 'MOTORBIKE',
    assigned_at = pg_catalog.clock_timestamp(),
    version = version + 1
where id = md5('group-a-incompatible-source-return')::uuid;
SQL
incompatible_rc=$?
set -e
if (( incompatible_rc == 0 )); then
  printf 'a non-recovery source delivery was incorrectly treated as compatible\n' >&2
  exit 1
fi
grep -q 'RIDER_ACTIVE_WORK_CONFLICT' "$incompatible_output" || {
  printf 'non-recovery source conflict did not return the structured error\n' >&2
  sed -n '1,120p' "$incompatible_output" >&2
  exit 1
}
printf 'ok - only a source DELIVERY_RECOVERY mission is compatible with its return\n'

replay_one="$("${psql_base[@]}" -Atc "
select dastak_v1_api.assign_return_rider(
  md5('group-a-concurrency-owner')::uuid,
  md5('group-a-replay-return')::uuid,
  md5('group-a-replay-rider')::uuid,
  1,
  'group-a-replay'
)
from (
  select pg_catalog.set_config(
    'request.jwt.claim.sub',
    md5('group-a-concurrency-owner')::text,
    false
  )
) actor")"
replay_two="$("${psql_base[@]}" -Atc "
select dastak_v1_api.assign_return_rider(
  md5('group-a-concurrency-owner')::uuid,
  md5('group-a-replay-return')::uuid,
  md5('group-a-replay-rider')::uuid,
  1,
  'group-a-replay'
)
from (
  select pg_catalog.set_config(
    'request.jwt.claim.sub',
    md5('group-a-concurrency-owner')::text,
    false
  )
) actor")"
[[ "$replay_one" == "$replay_two" && "$replay_one" == *'"missionStatus": "ASSIGNED"'* ]] || {
  printf 'same-command idempotent return assignment replay changed its result\n' >&2
  exit 1
}
printf 'ok - same-command replay returns the authoritative result\n'

printf 'Delivery Group A concurrency rehearsal passed.\n'
