begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table('private', 'merchant_order_rate_cards', 'private rate cards exist');
select has_table('private', 'merchant_order_quotes', 'private checkout quotes exist');
select has_table('private', 'merchant_order_quote_lines', 'private quote lines exist');
select has_table('private', 'merchant_orders', 'private merchant orders exist');
select has_table('private', 'merchant_order_lines', 'private order lines exist');
select has_table(
  'private',
  'merchant_order_refund_decisions',
  'private refund decisions exist'
);

select has_function(
  'public',
  'upsert_merchant_order_rate_card',
  array['uuid', 'uuid', 'integer', 'boolean', 'text', 'text']
);
select has_function(
  'public',
  'quote_merchant_order',
  array[
    'uuid', 'uuid', 'jsonb', 'double precision', 'double precision', 'text', 'text'
  ]
);
select has_function(
  'public',
  'create_merchant_order',
  array['uuid', 'uuid', 'text', 'text']
);
select has_function(
  'public',
  'confirm_merchant_order_payment',
  array['uuid', 'text', 'bigint', 'text', 'text']
);
select has_function(
  'public',
  'merchant_accept_order',
  array['uuid', 'uuid', 'text', 'text']
);
select has_function(
  'public',
  'merchant_reject_order',
  array['uuid', 'uuid', 'text', 'text', 'text']
);
select has_function(
  'public',
  'merchant_mark_order_ready',
  array['uuid', 'uuid', 'text', 'text']
);
select has_function(
  'public',
  'customer_cancel_order',
  array['uuid', 'uuid', 'text', 'text', 'text']
);
select has_function('public', 'get_customer_orders', array['uuid']);
select has_function('public', 'get_merchant_orders', array['uuid']);

select is(
  has_table_privilege('authenticated', 'private.merchant_orders', 'SELECT'),
  false,
  'authenticated cannot read private orders directly'
);
select is(
  has_table_privilege('authenticated', 'private.merchant_order_lines', 'INSERT'),
  false,
  'authenticated cannot forge order lines'
);
select is(
  has_table_privilege(
    'authenticated',
    'private.merchant_order_refund_decisions',
    'UPDATE'
  ),
  false,
  'authenticated cannot alter refund decisions'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.quote_merchant_order(uuid,uuid,jsonb,double precision,double precision,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass checkout Edge Function'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.confirm_merchant_order_payment(uuid,text,bigint,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot confirm its own payment'
);
select is(
  has_function_privilege(
    'service_role',
    'public.quote_merchant_order(uuid,uuid,jsonb,double precision,double precision,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can execute verified checkout'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '11111111-1111-4111-8111-111111111116',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'checkout-owner@example.test', '',
  now(), now(), now()
),
(
  '22222222-2222-4222-8222-222222222226',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'checkout-merchant-a@example.test', '',
  now(), now(), now()
),
(
  '33333333-3333-4333-8333-333333333336',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'checkout-merchant-b@example.test', '',
  now(), now(), now()
),
(
  '44444444-4444-4444-8444-444444444446',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'checkout-customer-a@example.test', '',
  now(), now(), now()
),
(
  '55555555-5555-4555-8555-555555555556',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'checkout-customer-b@example.test', '',
  now(), now(), now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number)
values
  ('11111111-1111-4111-8111-111111111116', 'Checkout Owner', '+14155552801'),
  ('22222222-2222-4222-8222-222222222226', 'Checkout Merchant A', '+14155552802'),
  ('33333333-3333-4333-8333-333333333336', 'Checkout Merchant B', '+14155552803'),
  ('44444444-4444-4444-8444-444444444446', 'Checkout Customer A', '+14155552804'),
  ('55555555-5555-4555-8555-555555555556', 'Checkout Customer B', '+14155552805');

insert into private.account_memberships (account_id, role, approved_at)
values
  ('11111111-1111-4111-8111-111111111116', 'owner', now()),
  ('22222222-2222-4222-8222-222222222226', 'merchant', now()),
  ('33333333-3333-4333-8333-333333333336', 'merchant', now()),
  ('44444444-4444-4444-8444-444444444446', 'customer', null),
  ('55555555-5555-4555-8555-555555555556', 'customer', null);

insert into public.service_zones (id, name, boundary, active)
values (
  '66666666-6666-4666-8666-666666666666',
  'Checkout Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.60 12.66,78.65 12.66,78.65 12.70,78.60 12.70,78.60 12.66))',
    4326
  ),
  true
);

insert into private.merchant_stores (
  id, merchant_account_id, service_zone_id, name, address, location,
  is_published, accepting_orders
) values
(
  '77777777-7777-4777-8777-777777777777',
  '22222222-2222-4222-8222-222222222226',
  '66666666-6666-4666-8666-666666666666',
  'Checkout Store A',
  '12 Main Road',
  extensions.st_setsrid(extensions.st_makepoint(78.6201, 12.6819), 4326),
  true,
  true
),
(
  '88888888-8888-4888-8888-888888888888',
  '33333333-3333-4333-8333-333333333336',
  '66666666-6666-4666-8666-666666666666',
  'Checkout Store B',
  '14 Main Road',
  extensions.st_setsrid(extensions.st_makepoint(78.6210, 12.6820), 4326),
  true,
  true
);

insert into private.catalogue_categories (
  id, store_id, name, display_order, is_active
) values (
  '99999999-9999-4999-8999-999999999999',
  '77777777-7777-4777-8777-777777777777',
  'Checkout Products',
  1,
  true
);

insert into private.catalogue_products (
  id, store_id, category_id, name, unit_label, price_paise,
  availability, catalogue_kind, restricted_approval_state, is_active
) values
(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '77777777-7777-4777-8777-777777777777',
  '99999999-9999-4999-8999-999999999999',
  'Server Priced Product',
  '1 pack',
  10000,
  'in_stock',
  'general',
  'not_applicable',
  true
),
(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
  '77777777-7777-4777-8777-777777777777',
  '99999999-9999-4999-8999-999999999999',
  'Unavailable Product',
  '1 pack',
  5000,
  'out_of_stock',
  'general',
  'not_applicable',
  true
),
(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
  '77777777-7777-4777-8777-777777777777',
  '99999999-9999-4999-8999-999999999999',
  'Restricted Product',
  '1 pack',
  20000,
  'in_stock',
  'paan_corner',
  'pending',
  true
);

create temporary table checkout_test_state (
  key text primary key,
  value uuid not null
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":2}]',
      12.6819,
      78.6201,
      'quote-without-pricing',
      'digest-quote-without-pricing'
    )
  ),
  'pricing_unavailable',
  'checkout fails closed until the owner configures server pricing'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_merchant_order_rate_card(
      '44444444-4444-4444-8444-444444444446',
      '66666666-6666-4666-8666-666666666666',
      4000,
      true,
      'customer-rate-key',
      'digest-customer-rate'
    )
  ),
  'access_denied',
  'a customer cannot configure checkout pricing'
);

select is(
  (
    select (response_body -> 'deliveryFee' ->> 'paise')::integer
    from public.upsert_merchant_order_rate_card(
      '11111111-1111-4111-8111-111111111116',
      '66666666-6666-4666-8666-666666666666',
      4000,
      true,
      'owner-rate-key',
      'digest-owner-rate'
    )
  ),
  4000,
  'active owner configures the server delivery fee'
);

select is(
  (
    select (response_body ->> 'version')::bigint
    from public.upsert_merchant_order_rate_card(
      '11111111-1111-4111-8111-111111111116',
      '66666666-6666-4666-8666-666666666666',
      4000,
      true,
      'owner-rate-key',
      'digest-owner-rate'
    )
  ),
  1::bigint,
  'identical rate-card request replays without a second version'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_merchant_order_rate_card(
      '11111111-1111-4111-8111-111111111116',
      '66666666-6666-4666-8666-666666666666',
      5000,
      true,
      'owner-rate-key',
      'changed-owner-rate-digest'
    )
  ),
  'idempotency_conflict',
  'a rate-card key cannot be reused with changed pricing'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":999999999999999999999999}]',
      12.6819,
      78.6201,
      'quote-overflow-quantity',
      'digest-quote-overflow-quantity'
    )
  ),
  'validation_failed',
  'oversized quantities fail validation without a database cast error'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":1},{"productId":"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1","quantity":1}]',
      12.6819,
      78.6201,
      'quote-duplicate-case',
      'digest-quote-duplicate-case'
    )
  ),
  'validation_failed',
  'UUID casing cannot bypass duplicate-product rejection'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":1}]',
      13.0000,
      79.0000,
      'quote-outside-zone',
      'digest-quote-outside-zone'
    )
  ),
  'outside_service_area',
  'dropoff must remain inside the merchant service zone'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2","quantity":1}]',
      12.6819,
      78.6201,
      'quote-out-of-stock',
      'digest-quote-out-of-stock'
    )
  ),
  'catalogue_changed',
  'out-of-stock products cannot enter checkout'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3","quantity":1}]',
      12.6819,
      78.6201,
      'quote-restricted',
      'digest-quote-restricted'
    )
  ),
  'catalogue_changed',
  'controlled products stay outside ordinary checkout'
);

insert into checkout_test_state (key, value)
select
  'quote-price-change',
  (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  '77777777-7777-4777-8777-777777777777',
  '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":2}]',
  12.6819,
  78.6201,
  'quote-price-change',
  'digest-quote-price-change'
);

select is(
  (
    select (response_body -> 'itemSubtotal' ->> 'paise')::bigint
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":2}]',
      12.6819,
      78.6201,
      'quote-price-change',
      'digest-quote-price-change'
    )
  ),
  20000::bigint,
  'quote uses the current server product price'
);

select is(
  (
    select (response_body -> 'total' ->> 'paise')::bigint
    from public.quote_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      '77777777-7777-4777-8777-777777777777',
      '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":2}]',
      12.6819,
      78.6201,
      'quote-price-change',
      'digest-quote-price-change'
    )
  ),
  24000::bigint,
  'quote adds only the owner-configured server delivery fee'
);

update private.catalogue_products
set price_paise = 11000
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';

select is(
  (
    select response_body #>> '{error,code}'
    from public.create_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'quote-price-change'),
      'create-price-change',
      'digest-create-price-change'
    )
  ),
  'catalogue_changed',
  'order creation rejects a quote after a product price changes'
);

update private.catalogue_products
set price_paise = 10000
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';

insert into checkout_test_state (key, value)
select
  'quote-rate-change',
  (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  '77777777-7777-4777-8777-777777777777',
  '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":1}]',
  12.6819,
  78.6201,
  'quote-rate-change',
  'digest-quote-rate-change'
);

select is(
  (
    select (response_body -> 'deliveryFee' ->> 'paise')::integer
    from public.upsert_merchant_order_rate_card(
      '11111111-1111-4111-8111-111111111116',
      '66666666-6666-4666-8666-666666666666',
      5000,
      true,
      'owner-rate-change',
      'digest-owner-rate-change'
    )
  ),
  5000,
  'owner can revise the server checkout fee'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.create_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'quote-rate-change'),
      'create-rate-change',
      'digest-create-rate-change'
    )
  ),
  'catalogue_changed',
  'order creation rejects a quote after the server rate changes'
);

select is(
  (
    select (response_body -> 'deliveryFee' ->> 'paise')::integer
    from public.upsert_merchant_order_rate_card(
      '11111111-1111-4111-8111-111111111116',
      '66666666-6666-4666-8666-666666666666',
      4000,
      true,
      'owner-rate-restore',
      'digest-owner-rate-restore'
    )
  ),
  4000,
  'owner restores the checkout fee for remaining lifecycle cases'
);

insert into checkout_test_state (key, value)
select
  'quote-main',
  (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  '77777777-7777-4777-8777-777777777777',
  '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":2}]',
  12.6819,
  78.6201,
  'quote-main',
  'digest-quote-main'
);

insert into checkout_test_state (key, value)
select
  'order-main',
  (response_body ->> 'orderId')::uuid
from public.create_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  (select value from checkout_test_state where key = 'quote-main'),
  'create-main',
  'digest-create-main'
);

select is(
  (
    select (response_body ->> 'orderId')::uuid
    from public.create_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'quote-main'),
      'create-main',
      'digest-create-main'
    )
  ),
  (select value from checkout_test_state where key = 'order-main'),
  'identical order creation replays the original order'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.create_merchant_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'quote-main'),
      'create-main-second-key',
      'digest-create-main-second-key'
    )
  ),
  'quote_unavailable',
  'a consumed quote cannot create a second order'
);

select is(
  (
    select count(*)::integer
    from private.merchant_orders
    where quote_id = (select value from checkout_test_state where key = 'quote-main')
  ),
  1,
  'one checkout quote creates at most one order'
);

select is(
  (
    select status
    from private.merchant_orders
    where id = (select value from checkout_test_state where key = 'order-main')
  ),
  'payment_pending',
  'new order requires server-confirmed in-app payment'
);

select is(
  (
    select unit_price_paise
    from private.merchant_order_lines
    where order_id = (select value from checkout_test_state where key = 'order-main')
  ),
  10000,
  'order line retains the server price snapshot'
);

select is(
  (
    select count(*)::integer
    from public.get_merchant_orders('22222222-2222-4222-8222-222222222226'),
      lateral jsonb_array_elements(response_body -> 'orders')
  ),
  0,
  'merchant cannot see an unpaid order'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.confirm_merchant_order_payment(
      (select value from checkout_test_state where key = 'order-main'),
      'provider-main-wrong',
      1,
      'payment-main-wrong',
      'digest-payment-main-wrong'
    )
  ),
  'payment_amount_mismatch',
  'payment confirmation rejects the wrong amount'
);

select is(
  (
    select response_body ->> 'status'
    from public.confirm_merchant_order_payment(
      (select value from checkout_test_state where key = 'order-main'),
      'provider-main',
      24000,
      'payment-main',
      'digest-payment-main'
    )
  ),
  'paid',
  'provider-confirmed exact payment moves the order to paid'
);

select is(
  (
    select count(*)::integer
    from public.get_merchant_orders('22222222-2222-4222-8222-222222222226'),
      lateral jsonb_array_elements(response_body -> 'orders')
  ),
  1,
  'paid order becomes visible to its merchant'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.merchant_mark_order_ready(
      '22222222-2222-4222-8222-222222222226',
      (select value from checkout_test_state where key = 'order-main'),
      'ready-before-accept',
      'digest-ready-before-accept'
    )
  ),
  'invalid_order_transition',
  'paid order cannot skip merchant acceptance'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.merchant_accept_order(
      '33333333-3333-4333-8333-333333333336',
      (select value from checkout_test_state where key = 'order-main'),
      'foreign-merchant-accept',
      'digest-foreign-merchant-accept'
    )
  ),
  'access_denied',
  'another merchant cannot accept the order'
);

select is(
  (
    select response_body ->> 'status'
    from public.merchant_accept_order(
      '22222222-2222-4222-8222-222222222226',
      (select value from checkout_test_state where key = 'order-main'),
      'merchant-accept-main',
      'digest-merchant-accept-main'
    )
  ),
  'merchant_accepted',
  'owning merchant accepts a paid order'
);

select is(
  (
    select response_body ->> 'status'
    from public.merchant_mark_order_ready(
      '22222222-2222-4222-8222-222222222226',
      (select value from checkout_test_state where key = 'order-main'),
      'merchant-ready-main',
      'digest-merchant-ready-main'
    )
  ),
  'ready',
  'accepted order becomes ready without dispatching a courier'
);

select is(
  (
    select response_status
    from public.customer_cancel_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'order-main'),
      'Customer changed plans after acceptance',
      'cancel-ready-main',
      'digest-cancel-ready-main'
    )
  ),
  202,
  'post-acceptance customer cancellation requires owner review'
);

select is(
  (
    select response_body ->> 'status'
    from public.customer_cancel_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'order-main'),
      'Customer changed plans after acceptance',
      'cancel-ready-main',
      'digest-cancel-ready-main'
    )
  ),
  'ready',
  'owner-review request does not silently cancel a ready order'
);

select is(
  (
    select response_body #>> '{refundDecision,eligibility}'
    from public.customer_cancel_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'order-main'),
      'Customer changed plans after acceptance',
      'cancel-ready-main',
      'digest-cancel-ready-main'
    )
  ),
  'owner_review_required',
  'post-acceptance refund eligibility is explicit'
);

insert into checkout_test_state (key, value)
select 'quote-pre-cancel', (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  '77777777-7777-4777-8777-777777777777',
  '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":1}]',
  12.6819, 78.6201,
  'quote-pre-cancel', 'digest-quote-pre-cancel'
);

insert into checkout_test_state (key, value)
select 'order-pre-cancel', (response_body ->> 'orderId')::uuid
from public.create_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  (select value from checkout_test_state where key = 'quote-pre-cancel'),
  'create-pre-cancel', 'digest-create-pre-cancel'
);

select is(
  (
    select response_body #>> '{refundDecision,eligibility}'
    from public.customer_cancel_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'order-pre-cancel'),
      'Changed mind before payment',
      'cancel-before-payment', 'digest-cancel-before-payment'
    )
  ),
  'no_payment',
  'prepayment cancellation creates no refund liability'
);

select is(
  (
    select response_body ->> 'paymentState'
    from public.customer_cancel_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'order-pre-cancel'),
      'Changed mind before payment',
      'cancel-before-payment', 'digest-cancel-before-payment'
    )
  ),
  'not_collected',
  'prepayment cancellation records that no money was collected'
);

insert into checkout_test_state (key, value)
select 'quote-paid-cancel', (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  '77777777-7777-4777-8777-777777777777',
  '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":1}]',
  12.6819, 78.6201,
  'quote-paid-cancel', 'digest-quote-paid-cancel'
);

insert into checkout_test_state (key, value)
select 'order-paid-cancel', (response_body ->> 'orderId')::uuid
from public.create_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  (select value from checkout_test_state where key = 'quote-paid-cancel'),
  'create-paid-cancel', 'digest-create-paid-cancel'
);

select is(
  (
    select response_status
    from public.confirm_merchant_order_payment(
      (select value from checkout_test_state where key = 'order-paid-cancel'),
      'provider-paid-cancel', 14000,
      'payment-paid-cancel', 'digest-payment-paid-cancel'
    )
  ),
  200,
  'provider confirms the order used by the paid-cancellation test'
);

select is(
  (
    select response_body #>> '{refundDecision,eligibility}'
    from public.customer_cancel_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'order-paid-cancel'),
      'Changed mind before merchant acceptance',
      'cancel-paid', 'digest-cancel-paid'
    )
  ),
  'full_refund',
  'paid cancellation before merchant acceptance is fully refundable'
);

select is(
  (
    select (response_body #>> '{refundDecision,deliveryFeeRefund,paise}')::integer
    from public.customer_cancel_order(
      '44444444-4444-4444-8444-444444444446',
      (select value from checkout_test_state where key = 'order-paid-cancel'),
      'Changed mind before merchant acceptance',
      'cancel-paid', 'digest-cancel-paid'
    )
  ),
  4000,
  'full refund includes the delivery fee before acceptance'
);

insert into checkout_test_state (key, value)
select 'quote-reject', (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  '77777777-7777-4777-8777-777777777777',
  '[{"productId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","quantity":1}]',
  12.6819, 78.6201,
  'quote-reject-order', 'digest-quote-reject-order'
);

insert into checkout_test_state (key, value)
select 'order-reject', (response_body ->> 'orderId')::uuid
from public.create_merchant_order(
  '44444444-4444-4444-8444-444444444446',
  (select value from checkout_test_state where key = 'quote-reject'),
  'create-reject-order', 'digest-create-reject-order'
);

select is(
  (
    select response_status
    from public.confirm_merchant_order_payment(
      (select value from checkout_test_state where key = 'order-reject'),
      'provider-reject-order', 14000,
      'payment-reject-order', 'digest-payment-reject-order'
    )
  ),
  200,
  'provider confirms the order used by the merchant-rejection test'
);

select is(
  (
    select response_body #>> '{refundDecision,eligibility}'
    from public.merchant_reject_order(
      '22222222-2222-4222-8222-222222222226',
      (select value from checkout_test_state where key = 'order-reject'),
      'Item cannot be fulfilled',
      'merchant-reject-order', 'digest-merchant-reject-order'
    )
  ),
  'merchant_fault_full_refund',
  'merchant rejection records merchant-fault full refund eligibility'
);

select is(
  has_table_privilege(
    'service_role',
    'private.merchant_order_refund_decisions',
    'UPDATE'
  ),
  false,
  'service role has no refund-decision rewrite grant'
);

select is(
  has_table_privilege('service_role', 'private.merchant_order_lines', 'UPDATE'),
  false,
  'service role has no order-price rewrite grant'
);

reset role;

select throws_ok(
  $$
    update private.merchant_order_refund_decisions
    set reason = 'changed'
  $$,
  'P0001',
  'merchant order financial ledger is append-only',
  'refund decisions cannot be rewritten'
);

select throws_ok(
  $$
    update private.merchant_order_lines
    set unit_price_paise = 1
  $$,
  'P0001',
  'merchant order financial ledger is append-only',
  'server price snapshots cannot be rewritten'
);

select is(
  (
    select count(*)::integer
    from audit.events
    where action = 'merchant_order_created'
      and actor_id = '44444444-4444-4444-8444-444444444446'
  ),
  4,
  'each created checkout order has an immutable audit event'
);

select is(
  (
    select count(*)::integer
    from audit.events
    where action = 'merchant_order_ready'
      and actor_id = '22222222-2222-4222-8222-222222222226'
  ),
  1,
  'merchant readiness is audited exactly once'
);

select * from finish();
rollback;
