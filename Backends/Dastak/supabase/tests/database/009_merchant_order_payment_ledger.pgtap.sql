begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table(
  'private', 'merchant_order_payment_records',
  'payment records stay in the private schema'
);
select has_table(
  'private', 'merchant_order_provider_events',
  'provider events stay in the private schema'
);
select has_table(
  'private', 'merchant_order_ledger_transactions',
  'ledger transactions stay in the private schema'
);
select has_table(
  'private', 'merchant_order_ledger_entries',
  'ledger entries stay in the private schema'
);

select is(
  has_table_privilege('authenticated', 'private.merchant_order_payment_records', 'SELECT'),
  false,
  'authenticated cannot read payment records directly'
);
select is(
  has_table_privilege('authenticated', 'private.merchant_order_ledger_entries', 'INSERT'),
  false,
  'authenticated cannot forge ledger entries'
);

select has_function(
  'public',
  'upsert_merchant_order_financial_rate_card',
  array['uuid', 'uuid', 'integer', 'integer', 'integer', 'boolean', 'text', 'text']
);
select has_function(
  'public',
  'get_owner_merchant_order_financial_snapshot',
  array['uuid', 'uuid']
);
select has_function(
  'public',
  'record_merchant_order_payment_event',
  array[
    'uuid', 'text', 'text', 'text', 'text', 'text', 'bigint',
    'timestamp with time zone', 'text'
  ]
);
select is(
  has_function_privilege(
    'authenticated',
    'public.record_merchant_order_payment_event(uuid,text,text,text,text,text,bigint,timestamp with time zone,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot record provider payment events'
);
select is(
  has_function_privilege(
    'service_role',
    'public.record_merchant_order_payment_event(uuid,text,text,text,text,text,bigint,timestamp with time zone,text)',
    'EXECUTE'
  ),
  true,
  'service role can record a verified provider event'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '82000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ledger-owner@example.test', '',
  now(), now(), now()
),
(
  '82000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ledger-merchant@example.test', '',
  now(), now(), now()
),
(
  '82000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ledger-customer@example.test', '',
  now(), now(), now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
  ('82000000-0000-4000-8000-000000000001', 'Ledger Owner', '+919200000001'),
  ('82000000-0000-4000-8000-000000000002', 'Ledger Merchant', '+919200000002'),
  ('82000000-0000-4000-8000-000000000003', 'Ledger Customer', '+919200000003');

insert into private.account_memberships (account_id, role, approved_at) values
  ('82000000-0000-4000-8000-000000000001', 'owner', now()),
  ('82000000-0000-4000-8000-000000000002', 'merchant', now()),
  ('82000000-0000-4000-8000-000000000003', 'customer', null);

insert into public.service_zones (id, name, boundary, active) values (
  '82000000-0000-4000-8000-000000000010',
  'Payment Ledger Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.55 12.60,78.55 12.75,78.75 12.75,78.75 12.60,78.55 12.60))',
    4326
  ),
  true
);

insert into private.merchant_stores (
  id, merchant_account_id, service_zone_id, name, address, location,
  is_published, accepting_orders
) values (
  '82000000-0000-4000-8000-000000000020',
  '82000000-0000-4000-8000-000000000002',
  '82000000-0000-4000-8000-000000000010',
  'Payment Ledger Store',
  '1 Ledger Road',
  extensions.st_setsrid(extensions.st_makepoint(78.6200, 12.6800), 4326),
  true,
  true
);

select is(
  (
    select response_status
    from public.upsert_merchant_order_financial_rate_card(
      '82000000-0000-4000-8000-000000000001',
      '82000000-0000-4000-8000-000000000010',
      4000,
      1000,
      3000,
      true,
      'ledger-rate-1',
      'ledger-rate-digest-1'
    )
  ),
  200,
  'owner configures commission and courier payout'
);

select is(
  (
    select response_status
    from public.upsert_merchant_order_financial_rate_card(
      '82000000-0000-4000-8000-000000000003',
      '82000000-0000-4000-8000-000000000010',
      4000,
      1000,
      3000,
      true,
      'customer-rate-1',
      'customer-rate-digest-1'
    )
  ),
  403,
  'customer cannot configure financial terms'
);

insert into private.merchant_order_quotes (
  id, customer_account_id, store_id, rate_card_id, rate_card_version,
  dropoff, item_subtotal_paise, delivery_fee_paise, total_paise, expires_at,
  consumed_at
) select
  '82000000-0000-4000-8000-000000000071',
  '82000000-0000-4000-8000-000000000003',
  '82000000-0000-4000-8000-000000000020',
  rate.id,
  rate.version,
  extensions.st_setsrid(extensions.st_makepoint(78.6300, 12.6900), 4326),
  10000,
  4000,
  14000,
  now() + interval '5 minutes',
  now()
from private.merchant_order_rate_cards as rate
where rate.service_zone_id = '82000000-0000-4000-8000-000000000010';

insert into private.merchant_order_quotes (
  id, customer_account_id, store_id, rate_card_id, rate_card_version,
  dropoff, item_subtotal_paise, delivery_fee_paise, total_paise, expires_at,
  consumed_at
) select
  '82000000-0000-4000-8000-000000000072',
  '82000000-0000-4000-8000-000000000003',
  '82000000-0000-4000-8000-000000000020',
  rate.id,
  rate.version,
  extensions.st_setsrid(extensions.st_makepoint(78.6310, 12.6910), 4326),
  11000,
  4000,
  15000,
  now() + interval '5 minutes',
  now()
from private.merchant_order_rate_cards as rate
where rate.service_zone_id = '82000000-0000-4000-8000-000000000010';

insert into private.merchant_orders (
  id, customer_account_id, store_id, service_zone_id, quote_id,
  status, payment_state, dropoff, item_subtotal_paise,
  delivery_fee_paise, total_paise
) values
(
  '82000000-0000-4000-8000-000000000081',
  '82000000-0000-4000-8000-000000000003',
  '82000000-0000-4000-8000-000000000020',
  '82000000-0000-4000-8000-000000000010',
  '82000000-0000-4000-8000-000000000071',
  'payment_pending',
  'payment_pending',
  extensions.st_setsrid(extensions.st_makepoint(78.6300, 12.6900), 4326),
  10000, 4000, 14000
),
(
  '82000000-0000-4000-8000-000000000082',
  '82000000-0000-4000-8000-000000000003',
  '82000000-0000-4000-8000-000000000020',
  '82000000-0000-4000-8000-000000000010',
  '82000000-0000-4000-8000-000000000072',
  'payment_pending',
  'payment_pending',
  extensions.st_setsrid(extensions.st_makepoint(78.6310, 12.6910), 4326),
  11000, 4000, 15000
);

select is(
  (
    select merchant_commission_paise
    from private.merchant_orders
    where id = '82000000-0000-4000-8000-000000000081'
  ),
  1000::bigint,
  'order snapshots a ten-percent merchant commission in integer paise'
);
select is(
  (
    select courier_payout_paise
    from private.merchant_orders
    where id = '82000000-0000-4000-8000-000000000081'
  ),
  3000,
  'order snapshots the configured courier payout'
);
select is(
  (
    select state
    from private.merchant_order_payment_records
    where order_id = '82000000-0000-4000-8000-000000000081'
  ),
  'pending',
  'new order starts with a server-owned pending payment record'
);

select is(
  (
    select response_status
    from public.record_merchant_order_payment_event(
      '82000000-0000-4000-8000-000000000081',
      'foundation',
      'payment-captured-1',
      'payment_captured',
      'provider-order-1',
      'provider-payment-1',
      14000,
      now(),
      'payment-captured-digest-1'
    )
  ),
  200,
  'verified capture records the exact server total'
);

select is(
  (
    select state
    from private.merchant_order_payment_records
    where order_id = '82000000-0000-4000-8000-000000000081'
  ),
  'captured',
  'payment record becomes captured'
);

select is(
  (
    select response_status
    from public.record_merchant_order_payment_event(
      '82000000-0000-4000-8000-000000000081',
      'foundation',
      'payment-captured-1',
      'payment_captured',
      'provider-order-1',
      'provider-payment-1',
      14000,
      now(),
      'payment-captured-digest-1'
    )
  ),
  200,
  'exact provider replay is idempotent'
);
select is(
  (
    select count(*)::integer
    from private.merchant_order_provider_events
    where provider = 'foundation'
      and provider_event_id = 'payment-captured-1'
  ),
  1,
  'provider replay creates one immutable event'
);
select is(
  (
    select response_status
    from public.record_merchant_order_payment_event(
      '82000000-0000-4000-8000-000000000081',
      'foundation',
      'payment-captured-1',
      'payment_captured',
      'provider-order-1',
      'provider-payment-1',
      14000,
      now(),
      'different-digest'
    )
  ),
  409,
  'provider event identifier rejects a different payload'
);

do $$
declare
  v_status text;
begin
  foreach v_status in array array[
    'merchant_accepted',
    'ready',
    'assigned',
    'en_route_to_pickup',
    'at_store',
    'picked_up',
    'in_transit',
    'delivered'
  ]::text[]
  loop
    update private.merchant_orders as merchant_order
    set status = v_status,
        state_version = merchant_order.state_version + 1,
        updated_at = now()
    where merchant_order.id = '82000000-0000-4000-8000-000000000081';
  end loop;
end;
$$;

select is(
  (
    select settlement_state
    from private.merchant_order_payment_records
    where order_id = '82000000-0000-4000-8000-000000000081'
  ),
  'settled',
  'delivery completion allocates the captured funds once'
);
select is(
  (
    select coalesce(sum(entry.amount_paise), 0)::bigint
    from private.merchant_order_ledger_entries as entry
    join private.merchant_order_ledger_transactions as transaction
      on transaction.id = entry.transaction_id
    where transaction.order_id = '82000000-0000-4000-8000-000000000081'
      and transaction.kind = 'order_settlement'
      and entry.account_code = 'merchant_payable'
      and entry.side = 'credit'
  ),
  9000::bigint,
  'merchant payable excludes commission'
);
select is(
  (
    select coalesce(sum(entry.amount_paise), 0)::bigint
    from private.merchant_order_ledger_entries as entry
    join private.merchant_order_ledger_transactions as transaction
      on transaction.id = entry.transaction_id
    where transaction.order_id = '82000000-0000-4000-8000-000000000081'
      and transaction.kind = 'order_settlement'
      and entry.account_code = 'courier_payable'
      and entry.side = 'credit'
  ),
  3000::bigint,
  'courier payable uses the snapshotted payout'
);

select is(
  (
    select response_body #>> '{platformMerchantCommission,paise}'
    from public.get_owner_merchant_order_financial_snapshot(
      '82000000-0000-4000-8000-000000000001',
      '82000000-0000-4000-8000-000000000081'
    )
  ),
  '1000',
  'owner financial snapshot exposes the server-calculated commission'
);
select is(
  (
    select response_status
    from public.get_owner_merchant_order_financial_snapshot(
      '82000000-0000-4000-8000-000000000003',
      '82000000-0000-4000-8000-000000000081'
    )
  ),
  403,
  'customer cannot read owner financial snapshots'
);

select is(
  (
    select response_status
    from public.record_merchant_order_payment_event(
      '82000000-0000-4000-8000-000000000082',
      'foundation',
      'payment-captured-2',
      'payment_captured',
      'provider-order-2',
      'provider-payment-2',
      15000,
      now(),
      'payment-captured-digest-2'
    )
  ),
  200,
  'second order captures before refund testing'
);

select is(
  (
    select response_status
    from public.customer_cancel_order(
      '82000000-0000-4000-8000-000000000003',
      '82000000-0000-4000-8000-000000000082',
      'Changed mind before merchant acceptance',
      'ledger-cancel-1',
      'ledger-cancel-digest-1'
    )
  ),
  200,
  'eligible cancellation creates a refund request'
);
select is(
  (
    select refund_reserved_paise
    from private.merchant_order_payment_records
    where order_id = '82000000-0000-4000-8000-000000000082'
  ),
  15000::bigint,
  'eligible refund reserves the captured amount in the ledger'
);

select is(
  (
    select response_status
    from public.record_merchant_order_payment_event(
      '82000000-0000-4000-8000-000000000082',
      'foundation',
      'refund-succeeded-2',
      'refund_succeeded',
      'provider-order-2',
      'provider-payment-2',
      15000,
      now(),
      'refund-succeeded-digest-2'
    )
  ),
  200,
  'verified refund completes the reserved refund'
);
select is(
  (
    select payment_state
    from private.merchant_orders
    where id = '82000000-0000-4000-8000-000000000082'
  ),
  'refunded',
  'order payment state follows the verified refund'
);
select is(
  (
    select refunded_paise
    from private.merchant_order_payment_records
    where order_id = '82000000-0000-4000-8000-000000000082'
  ),
  15000::bigint,
  'payment record stores the completed refund amount'
);

select ok(
  not exists (
    select transaction.id
    from private.merchant_order_ledger_transactions as transaction
    left join private.merchant_order_ledger_entries as entry
      on entry.transaction_id = transaction.id
    group by transaction.id
    having coalesce(sum(entry.amount_paise) filter (where entry.side = 'debit'), 0)
      <> coalesce(sum(entry.amount_paise) filter (where entry.side = 'credit'), 0)
  ),
  'every financial transaction is balanced in integer paise'
);

reset role;

select throws_ok(
  $$
    update private.merchant_order_ledger_entries
    set amount_paise = amount_paise + 1
    where order_id = '82000000-0000-4000-8000-000000000081'
  $$,
  '23514',
  'merchant_order_ledger_immutable',
  'ledger history cannot be rewritten'
);

select * from finish();
rollback;
