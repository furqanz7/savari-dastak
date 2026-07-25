begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_column(
  'private',
  'merchant_order_quotes',
  'delivery_distance_m',
  'checkout quotes snapshot delivery distance'
);
select has_column(
  'private',
  'merchant_orders',
  'delivery_distance_m',
  'merchant orders retain delivery distance'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '95000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'distance-merchant@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
),
(
  '95000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'distance-customer@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
(
  '95000000-0000-4000-8000-000000000001',
  'Distance Merchant',
  '+919500000001'
),
(
  '95000000-0000-4000-8000-000000000002',
  'Distance Customer',
  '+919500000002'
);

insert into private.account_memberships (account_id, role, approved_at) values
(
  '95000000-0000-4000-8000-000000000001',
  'merchant',
  pg_catalog.now()
),
(
  '95000000-0000-4000-8000-000000000002',
  'customer',
  null
);

insert into public.service_zones (id, name, boundary, active) values (
  '95000000-0000-4000-8000-000000000010',
  'Distance Pricing Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.59 12.64,78.70 12.64,78.70 12.72,78.59 12.72,78.59 12.64))',
    4326
  ),
  true
);

insert into private.merchant_stores (
  id, merchant_account_id, service_zone_id, name, address, location,
  is_published, accepting_orders
) values (
  '95000000-0000-4000-8000-000000000020',
  '95000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000010',
  'Distance Store',
  '1 Test Road',
  extensions.st_setsrid(extensions.st_makepoint(78.6201, 12.6819), 4326),
  true,
  true
);

insert into private.catalogue_categories (
  id, store_id, name, display_order, is_active
) values (
  '95000000-0000-4000-8000-000000000030',
  '95000000-0000-4000-8000-000000000020',
  'Essentials',
  1,
  true
);

insert into private.catalogue_products (
  id, store_id, category_id, name, unit_label, price_paise,
  availability, catalogue_kind, restricted_approval_state, is_active
) values (
  '95000000-0000-4000-8000-000000000040',
  '95000000-0000-4000-8000-000000000020',
  '95000000-0000-4000-8000-000000000030',
  'Test Bread',
  '400 g',
  4500,
  'in_stock',
  'general',
  'not_applicable',
  true
);

insert into private.merchant_order_rate_cards (
  id, service_zone_id, delivery_fee_paise, merchant_commission_bps,
  courier_payout_paise, included_distance_m, base_delivery_fee_paise,
  delivery_fee_per_started_km_paise, base_courier_payout_paise,
  courier_payout_per_started_km_paise, active
) values (
  '95000000-0000-4000-8000-000000000050',
  '95000000-0000-4000-8000-000000000010',
  3500,
  1000,
  3000,
  3000,
  3500,
  800,
  3000,
  700,
  true
);

create temporary table distance_quote_state (
  key text primary key,
  value uuid not null
);

insert into distance_quote_state (key, value)
select 'near', (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '95000000-0000-4000-8000-000000000002',
  '95000000-0000-4000-8000-000000000020',
  '[{"productId":"95000000-0000-4000-8000-000000000040","quantity":1}]',
  12.6819,
  78.6201,
  'distance-near',
  'distance-near-v1'
);

select is(
  (
    select (response_body -> 'deliveryFee' ->> 'paise')::integer
    from public.quote_merchant_order(
      '95000000-0000-4000-8000-000000000002',
      '95000000-0000-4000-8000-000000000020',
      '[{"productId":"95000000-0000-4000-8000-000000000040","quantity":1}]',
      12.6819,
      78.6201,
      'distance-near',
      'distance-near-v1'
    )
  ),
  3500,
  'delivery within three kilometres uses the base fee'
);

insert into distance_quote_state (key, value)
select 'far', (response_body ->> 'quoteId')::uuid
from public.quote_merchant_order(
  '95000000-0000-4000-8000-000000000002',
  '95000000-0000-4000-8000-000000000020',
  '[{"productId":"95000000-0000-4000-8000-000000000040","quantity":1}]',
  12.6819,
  78.6521,
  'distance-far',
  'distance-far-v1'
);

select ok(
  (
    select delivery_distance_m between 3001 and 4000
    from private.merchant_order_quotes
    where id = (select value from distance_quote_state where key = 'far')
  ),
  'server measures the store-to-dropoff distance'
);

select is(
  (
    select delivery_fee_paise
    from private.merchant_order_quotes
    where id = (select value from distance_quote_state where key = 'far')
  ),
  4300,
  'one additional started kilometre adds eight rupees'
);

select is(
  (
    select courier_payout_paise
    from private.merchant_order_quotes
    where id = (select value from distance_quote_state where key = 'far')
  ),
  3700,
  'courier payout uses the same distance snapshot'
);

insert into distance_quote_state (key, value)
select 'order', (response_body ->> 'orderId')::uuid
from public.create_merchant_order(
  '95000000-0000-4000-8000-000000000002',
  (select value from distance_quote_state where key = 'far'),
  'distance-order',
  'distance-order-v1'
);

select is(
  (
    select merchant_order.delivery_distance_m
    from private.merchant_orders as merchant_order
    where merchant_order.id = (
      select value from distance_quote_state where key = 'order'
    )
  ),
  (
    select quote.delivery_distance_m
    from private.merchant_order_quotes as quote
    where quote.id = (select value from distance_quote_state where key = 'far')
  ),
  'the order retains the quoted delivery distance'
);

select * from finish();
rollback;
