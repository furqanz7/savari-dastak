#!/usr/bin/env bash
set -euo pipefail

database_url="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dastak-v1-batch1.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

psql_base=(psql "$database_url" -X -q -v ON_ERROR_STOP=1)

"${psql_base[@]}" <<'SQL'
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '99000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'v1-concurrency-customer@example.test', '',
  now(), now(), now()
),
(
  '99000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'v1-concurrency-owner@example.test', '',
  now(), now(), now()
) on conflict (id) do nothing;

insert into public.accounts (id, display_name, phone_number) values
  ('99000000-0000-4000-8000-000000000001', 'Concurrency Customer', '+919900000001'),
  ('99000000-0000-4000-8000-000000000002', 'Concurrency Owner', '+919900000002')
on conflict (id) do nothing;

insert into private.account_memberships (account_id, role, approved_at) values
  ('99000000-0000-4000-8000-000000000001', 'customer', null),
  ('99000000-0000-4000-8000-000000000002', 'owner', now())
on conflict (account_id, role) do nothing;

insert into dastak_v1.categories (id, name, slug, status, created_by) values (
  '99000000-0000-4000-8000-000000000010',
  'Concurrency Category',
  'concurrency-category',
  'ACTIVE',
  '99000000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;

insert into dastak_v1.subcategories (
  id, category_id, name, slug, status, created_by
) values (
  '99000000-0000-4000-8000-000000000011',
  '99000000-0000-4000-8000-000000000010',
  'Concurrency Subcategory',
  'concurrency-subcategory',
  'ACTIVE',
  '99000000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;

insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, status, created_by
) values (
  '99000000-0000-4000-8000-000000000012',
  '99000000-0000-4000-8000-000000000011',
  'Concurrency Product',
  'concurrency-product',
  '1 unit',
  500,
  450,
  'ACTIVE',
  '99000000-0000-4000-8000-000000000002'
) on conflict (id) do nothing;
SQL

submit_order() {
  "${psql_base[@]}" -At <<'SQL'
begin;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '99000000-0000-4000-8000-000000000001',
  true
);
select public.dastak_v1_submit_order(
  'concurrent-submit-1',
  0,
  '{
    "deliveryAddress":{
      "line1":"1 Concurrency Road",
      "city":"Vaniyambadi",
      "countryCode":"IN"
    },
    "recipient":{
      "name":"Concurrency Customer",
      "phoneNumber":"+919900000001"
    },
    "lines":[{
      "lineType":"RETAIL_SKU",
      "skuId":"99000000-0000-4000-8000-000000000012",
      "quantity":1
    }]
  }'::jsonb
) ->> 'id';
commit;
SQL
}

submit_order >"$work_dir/first.out" 2>"$work_dir/first.err" &
first_pid=$!
submit_order >"$work_dir/second.out" 2>"$work_dir/second.err" &
second_pid=$!

wait "$first_pid"
wait "$second_pid"

first_order_id="$(tail -n 1 "$work_dir/first.out")"
second_order_id="$(tail -n 1 "$work_dir/second.out")"
if [[ -z "$first_order_id" || "$first_order_id" != "$second_order_id" ]]; then
  printf 'Concurrent replay returned different order IDs: %s / %s\n' \
    "$first_order_id" "$second_order_id" >&2
  exit 1
fi

read -r order_count idempotency_count event_count audit_count < <(
  "${psql_base[@]}" -At -F ' ' <<'SQL'
select
  (select count(*) from dastak_v1.orders
    where customer_id = '99000000-0000-4000-8000-000000000001'),
  (select count(*) from dastak_v1.idempotency_records
    where actor_id = '99000000-0000-4000-8000-000000000001'
      and command_name = 'submitOrder'
      and idempotency_key = 'concurrent-submit-1'),
  (select count(*) from dastak_v1.domain_events_outbox
    where actor_id = '99000000-0000-4000-8000-000000000001'
      and event_type = 'ORDER_SUBMITTED'),
  (select count(*) from dastak_v1.audit_events
    where actor_id = '99000000-0000-4000-8000-000000000001'
      and action = 'ORDER_SUBMITTED');
SQL
)

if [[ "$order_count $idempotency_count $event_count $audit_count" != "1 1 1 1" ]]; then
  printf 'Expected one order, idempotency record, event, and audit row; got %s %s %s %s\n' \
    "$order_count" "$idempotency_count" "$event_count" "$audit_count" >&2
  exit 1
fi

printf 'Dastak V1 Batch 1 concurrency gate passed.\n'
