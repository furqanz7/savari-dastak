begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_column('public', 'service_zones', 'center', 'city center is stored');
select has_column(
  'public',
  'service_zones',
  'coverage_radius_m',
  'city coverage radius is stored'
);
select has_column(
  'private',
  'merchant_order_rate_cards',
  'delivery_fee_per_started_km_paise',
  'customer per-kilometre rate is stored'
);
select has_column(
  'private',
  'merchant_order_rate_cards',
  'courier_payout_per_started_km_paise',
  'courier per-kilometre rate is stored'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.upsert_city_service_zone(uuid,uuid,text,double precision,double precision,integer,boolean,text,text)',
    'EXECUTE'
  ),
  false,
  'clients cannot configure cities directly'
);
select is(
  has_function_privilege(
    'service_role',
    'public.upsert_city_service_zone(uuid,uuid,text,double precision,double precision,integer,boolean,text,text)',
    'EXECUTE'
  ),
  true,
  'trusted server can configure cities'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '94000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'city-owner@example.test',
  '',
  pg_catalog.now(),
  pg_catalog.now(),
  pg_catalog.now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values (
  '94000000-0000-4000-8000-000000000001',
  'City Owner',
  '+919400000001'
);

insert into private.account_memberships (account_id, role, approved_at) values (
  '94000000-0000-4000-8000-000000000001',
  'owner',
  pg_catalog.now()
);

select is(
  (
    select response_status
    from public.upsert_city_service_zone(
      '94000000-0000-4000-8000-000000000001',
      '94000000-0000-4000-8000-000000000010',
      'Test City',
      12.6819,
      78.6202,
      9999,
      true,
      'invalid-radius',
      'invalid-radius-v1'
    )
  ),
  400,
  'coverage below 10 kilometres is rejected'
);

select is(
  (
    select response_status
    from public.upsert_city_service_zone(
      '94000000-0000-4000-8000-000000000001',
      '94000000-0000-4000-8000-000000000010',
      'Test City',
      12.6819,
      78.6202,
      10000,
      true,
      'city-create',
      'city-create-v1'
    )
  ),
  201,
  'owner creates a city with the default 10-kilometre radius'
);

select is(
  (
    select coverage_radius_m
    from public.service_zones
    where id = '94000000-0000-4000-8000-000000000010'
  ),
  10000,
  'configured city radius is persisted'
);

select is(
  (
    select response_status
    from public.upsert_merchant_order_distance_rate_card(
      '94000000-0000-4000-8000-000000000001',
      '94000000-0000-4000-8000-000000000010',
      3000,
      3500,
      800,
      3000,
      700,
      1000,
      true,
      'rate-create',
      'rate-create-v1'
    )
  ),
  201,
  'owner creates the approved merchant-order rate card'
);

select is(
  (
    select (
      private.calculate_merchant_order_distance_terms(rate, 3000)
        -> 'deliveryFee' ->> 'paise'
    )::bigint
    from private.merchant_order_rate_cards as rate
    where rate.service_zone_id = '94000000-0000-4000-8000-000000000010'
  ),
  3500::bigint,
  'three kilometres costs the base customer fee'
);

select is(
  (
    select (
      private.calculate_merchant_order_distance_terms(rate, 10000)
        -> 'deliveryFee' ->> 'paise'
    )::bigint
    from private.merchant_order_rate_cards as rate
    where rate.service_zone_id = '94000000-0000-4000-8000-000000000010'
  ),
  9100::bigint,
  'ten kilometres costs the base plus seven started kilometres'
);

select is(
  (
    select (
      private.calculate_merchant_order_distance_terms(rate, 10000)
        -> 'courierPayout' ->> 'paise'
    )::bigint
    from private.merchant_order_rate_cards as rate
    where rate.service_zone_id = '94000000-0000-4000-8000-000000000010'
  ),
  7900::bigint,
  'ten-kilometre courier payout follows the approved rate'
);

select * from finish();
rollback;
