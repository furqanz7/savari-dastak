begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '95000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'geo-owner@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
),
(
  '95000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'geo-customer@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
),
(
  '95000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'geo-near-merchant@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
),
(
  '95000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'geo-far-merchant@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
  ('95000000-0000-4000-8000-000000000001', 'Geo Owner', '+919500000001'),
  ('95000000-0000-4000-8000-000000000002', 'Geo Customer', '+919500000002'),
  ('95000000-0000-4000-8000-000000000003', 'Near Merchant', '+919500000003'),
  ('95000000-0000-4000-8000-000000000004', 'Far Merchant', '+919500000004');

insert into private.account_memberships (account_id, role, approved_at) values
  ('95000000-0000-4000-8000-000000000001', 'owner', pg_catalog.now()),
  ('95000000-0000-4000-8000-000000000002', 'customer', null),
  ('95000000-0000-4000-8000-000000000003', 'merchant', pg_catalog.now()),
  ('95000000-0000-4000-8000-000000000004', 'merchant', pg_catalog.now());

select is(
  (
    select response_status
    from public.upsert_city_service_zone(
      '95000000-0000-4000-8000-000000000001',
      '95000000-0000-4000-8000-000000000010',
      'Geographic Test City',
      12.6819,
      78.6202,
      30000,
      true,
      'geo-city-create',
      'geo-city-create-v1'
    )
  ),
  201,
  'owner creates a 30-kilometre test city'
);

select is(
  (
    select response_status
    from public.upsert_merchant_order_distance_rate_card(
      '95000000-0000-4000-8000-000000000001',
      '95000000-0000-4000-8000-000000000010',
      3000, 3500, 800, 3000, 700, 1000, true,
      'geo-rate-create',
      'geo-rate-create-v1'
    )
  ),
  201,
  'test city has an active checkout rate card'
);

insert into private.merchant_stores (
  id, merchant_account_id, service_zone_id, name, address, location,
  is_published, accepting_orders
) values
(
  '95000000-0000-4000-8000-000000000020',
  '95000000-0000-4000-8000-000000000003',
  '95000000-0000-4000-8000-000000000010',
  'Near Store',
  'Near Test Road',
  extensions.st_setsrid(extensions.st_makepoint(78.6650, 12.6819), 4326),
  true,
  true
),
(
  '95000000-0000-4000-8000-000000000021',
  '95000000-0000-4000-8000-000000000004',
  '95000000-0000-4000-8000-000000000010',
  'Far Store',
  'Far Test Road',
  extensions.st_setsrid(extensions.st_makepoint(78.8000, 12.6819), 4326),
  true,
  true
);

select is(
  (
    select pg_catalog.jsonb_array_length(response_body -> 'stores')
    from public.browse_catalogue(
      '95000000-0000-4000-8000-000000000002',
      12.6819,
      78.6202,
      10000
    )
  ),
  1,
  '10-kilometre discovery includes only the near store'
);

select is(
  (
    select pg_catalog.jsonb_array_length(response_body -> 'stores')
    from public.browse_catalogue(
      '95000000-0000-4000-8000-000000000002',
      12.6819,
      78.6202,
      30000
    )
  ),
  2,
  '30-kilometre discovery includes both stores'
);

select is(
  (
    select response_status
    from public.browse_catalogue(
      '95000000-0000-4000-8000-000000000002',
      12.6819,
      78.6202,
      9999
    )
  ),
  400,
  'discovery below 10 kilometres is rejected'
);

select is(
  (
    select response_status
    from public.browse_catalogue(
      '95000000-0000-4000-8000-000000000002',
      12.6819,
      79.0000,
      30000
    )
  ),
  422,
  'customers outside an active city are rejected'
);

select is(
  (
    select response_status
    from public.upsert_merchant_store(
      '95000000-0000-4000-8000-000000000003',
      'Near Store',
      'Outside Test Road',
      12.6819,
      79.0000,
      true,
      true,
      'geo-store-outside',
      'geo-store-outside-v1'
    )
  ),
  422,
  'a merchant cannot move its store outside an active city'
);

select is(
  (
    select response_status
    from public.quote_merchant_order(
      '95000000-0000-4000-8000-000000000002',
      '95000000-0000-4000-8000-000000000020',
      '[{"productId":"95000000-0000-4000-8000-000000000099","quantity":1}]'::jsonb,
      12.6819,
      79.0000,
      'geo-quote-outside',
      'geo-quote-outside-v1'
    )
  ),
  422,
  'checkout rejects a drop-off outside the store service zone'
);

select * from finish();
rollback;
