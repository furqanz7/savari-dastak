begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege(
    'authenticated', 'dastak_v1_api.order_json(uuid,uuid)', 'EXECUTE'
  ),
  true,
  'authenticated customers can execute the completed order projection'
);
select is(
  has_function_privilege(
    'anon', 'dastak_v1_api.order_json(uuid,uuid)', 'EXECUTE'
  ),
  false,
  'anonymous callers cannot inspect customer orders'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.order_json_pre_customer_orders_completion(uuid,uuid)',
    'EXECUTE'
  ),
  false,
  'the internal projection chain is not directly executable by customers'
);
select ok(
  coalesce((
    select function_config.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc function_config
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function_config.pronamespace
    where namespace.nspname = 'dastak_v1_api'
      and function_config.proname = 'order_json'
      and function_config.pronargs = 2
  ), false),
  'the security-definer projection has an empty search path'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    'ce000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-owner@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ce000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-outsider@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ce000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-rider@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  );

insert into public.accounts (id, display_name, phone_number) values
  ('ce000000-0000-4000-8000-000000000001', 'Orders Owner', '+919500000201'),
  ('ce000000-0000-4000-8000-000000000002', 'Orders Outsider', '+919500000202'),
  ('ce000000-0000-4000-8000-000000000003', 'Orders Rider', '+919500000203');
insert into private.account_memberships (account_id, role) values
  ('ce000000-0000-4000-8000-000000000001', 'customer'),
  ('ce000000-0000-4000-8000-000000000002', 'customer'),
  ('ce000000-0000-4000-8000-000000000003', 'dastak_partner');

insert into public.service_zones (id, name, boundary, coverage_radius_m)
values (
  'ce200000-0000-4000-8000-000000000001',
  'Customer Orders Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.5 12.5,78.8 12.5,78.8 12.8,78.5 12.8,78.5 12.5))',
    4326
  ),
  10000
);

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values (
  'ce210000-0000-4000-8000-000000000001',
  'Customer Orders Test Merchant', 'Customer Orders Merchant',
  'RETAIL', 'ACTIVE', 'ce000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id,
  address_snapshot, location, capacity_limit, status, created_by
) values (
  'ce220000-0000-4000-8000-000000000001',
  'ce210000-0000-4000-8000-000000000001',
  'Private Retail Branch', 'ce200000-0000-4000-8000-000000000001',
  '{"line1":"Private pickup address"}',
  extensions.st_setsrid(extensions.st_makepoint(78.621, 12.681), 4326),
  5, 'ACTIVE', 'ce000000-0000-4000-8000-000000000001'
);

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  status, reviewed_at, reviewed_by
) values (
  'ce230000-0000-4000-8000-000000000001',
  'ce000000-0000-4000-8000-000000000003', 'walking',
  'dastak-partner/ce000000-0000-4000-8000-000000000003/id.jpg',
  'approved', pg_catalog.now(), 'ce000000-0000-4000-8000-000000000001'
);
insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values (
  'ce000000-0000-4000-8000-000000000003',
  'ce230000-0000-4000-8000-000000000001', 'walking'
);
insert into private.delivery_partner_availability (
  account_id, status, location, service_zone_id, last_seen_at, available_until
) values (
  'ce000000-0000-4000-8000-000000000003', 'online',
  extensions.st_setsrid(extensions.st_makepoint(78.622, 12.682), 4326),
  'ce200000-0000-4000-8000-000000000001',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp() + interval '30 minutes'
);

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values
  (
    'ce240000-0000-4000-8000-000000000001',
    'settlement.rider_distance_payout', 'GLOBAL',
    '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}',
    'ce000000-0000-4000-8000-000000000001',
    'Customer Orders projection test configuration'
  ),
  (
    'ce240000-0000-4000-8000-000000000002',
    'merchant.reachability_stale_seconds', 'GLOBAL', '120',
    'ce000000-0000-4000-8000-000000000001',
    'Customer Orders projection test reachability'
  );
insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values (
  'ce220000-0000-4000-8000-000000000001', true, true,
  'ce000000-0000-4000-8000-000000000001'
);

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status, submitted_at
) values (
  'ce100000-0000-4000-8000-000000000001', 'DSK-ORDERS-0001',
  'ce000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'CREATED',
  '2026-08-24T06:00:00Z'
);
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values (
  'ce100000-0000-4000-8000-000000000001',
  '{"label":"Home","line1":"1 Test Road","city":"Vaniyambadi","state":"Tamil Nadu","postalCode":"635751","countryCode":"IN","latitude":12.6819,"longitude":78.6201,"instructions":"Ring once"}',
  '{"name":"Orders Owner","phoneNumber":"+919500000201"}',
  pg_catalog.decode(pg_catalog.repeat('00', 32), 'hex')
);
insert into dastak_v1.order_price_snapshots (
  order_id, snapshot_kind, subtotal_paise, total_paise
) values (
  'ce100000-0000-4000-8000-000000000001', 'SUBMITTED', 1000, 1000
);

select is(
  dastak_v1_api.order_json(
    'ce100000-0000-4000-8000-000000000001',
    'ce000000-0000-4000-8000-000000000001'
  ) #>> '{deliveryAddress,line1}',
  '1 Test Road',
  'the immutable delivery address remains available to its customer'
);
select is(
  dastak_v1_api.order_json(
    'ce100000-0000-4000-8000-000000000001',
    'ce000000-0000-4000-8000-000000000001'
  ) #>> '{recipient,name}',
  'Orders Owner',
  'the immutable recipient remains available to its customer'
);
select is(
  dastak_v1_api.order_json(
    'ce100000-0000-4000-8000-000000000001',
    'ce000000-0000-4000-8000-000000000002'
  ),
  null::jsonb,
  'another customer cannot project the order'
);
select ok(
  not (
    dastak_v1_api.order_json(
      'ce100000-0000-4000-8000-000000000001',
      'ce000000-0000-4000-8000-000000000001'
    ) ? 'merchant'
  ),
  'the projection does not add retail merchant identity'
);

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, fully_secured_at, paid_at
) values (
  'ce100000-0000-4000-8000-000000000002', 'DSK-ORDERS-0002',
  'ce000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'PREPARING',
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() - interval '25 minutes',
  pg_catalog.clock_timestamp() - interval '20 minutes'
);
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values (
  'ce100000-0000-4000-8000-000000000002',
  '{"label":"Home","line1":"2 Test Road","countryCode":"IN","latitude":12.68,"longitude":78.62}',
  '{"name":"Orders Owner","phoneNumber":"+919500000201"}',
  pg_catalog.decode(pg_catalog.repeat('01', 32), 'hex')
);
insert into dastak_v1.order_price_snapshots (
  order_id, snapshot_kind, subtotal_paise, total_paise
) values (
  'ce100000-0000-4000-8000-000000000002', 'PAID', 1000, 1000
);
insert into dastak_v1.matching_attempts (
  id, order_id, wave, status, started_at, expires_at
) values (
  'ce250000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000002', 'WAVE_1', 'OPEN',
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes'
);
insert into dastak_v1.merchant_opportunities (
  id, matching_attempt_id, order_id, organization_id, branch_id,
  status, started_at, expires_at, promised_prep_minutes,
  responded_by, responded_at
) values (
  'ce260000-0000-4000-8000-000000000001',
  'ce250000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000002',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001', 'SELECTED',
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes', 10,
  'ce000000-0000-4000-8000-000000000001',
  pg_catalog.clock_timestamp() - interval '25 minutes'
);
insert into dastak_v1.fulfilments (
  id, order_id, organization_id, branch_id, source_opportunity_id,
  fulfilment_type, status, promised_prep_minutes, committed_at,
  prep_started_at, estimated_ready_at
) values (
  'ce270000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000002',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001',
  'ce260000-0000-4000-8000-000000000001',
  'RETAIL', 'PREPARING', 10,
  pg_catalog.clock_timestamp() - interval '25 minutes',
  pg_catalog.clock_timestamp() - interval '20 minutes',
  pg_catalog.clock_timestamp() - interval '10 minutes'
);

select is(
  (
    dastak_v1_api.order_json(
      'ce100000-0000-4000-8000-000000000002',
      'ce000000-0000-4000-8000-000000000001'
    ) #>> '{fulfilmentProgress,estimatedReadyAt}'
  )::timestamptz,
  (
    select estimated_ready_at from dastak_v1.fulfilments
    where id = 'ce270000-0000-4000-8000-000000000001'
  ),
  'the customer preparation ETA comes from the authoritative fulfilment timestamp'
);
select is(
  dastak_v1_api.order_json(
    'ce100000-0000-4000-8000-000000000002',
    'ce000000-0000-4000-8000-000000000001'
  ) #>> '{fulfilmentProgress,runningLate}',
  'true',
  'an overdue Preparing fulfilment is projected as running late without becoming Ready'
);

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, fully_secured_at, paid_at
) values (
  'ce100000-0000-4000-8000-000000000003', 'DSK-ORDERS-0003',
  'ce000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'OUT_FOR_DELIVERY',
  pg_catalog.clock_timestamp() - interval '60 minutes',
  pg_catalog.clock_timestamp() - interval '55 minutes',
  pg_catalog.clock_timestamp() - interval '50 minutes'
);
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values (
  'ce100000-0000-4000-8000-000000000003',
  '{"label":"Home","line1":"3 Test Road","countryCode":"IN","latitude":12.68,"longitude":78.62}',
  '{"name":"Orders Owner","phoneNumber":"+919500000201"}',
  pg_catalog.decode(pg_catalog.repeat('02', 32), 'hex')
);
insert into dastak_v1.order_price_snapshots (
  order_id, snapshot_kind, subtotal_paise, total_paise
) values (
  'ce100000-0000-4000-8000-000000000003', 'PAID', 1000, 1000
);
insert into dastak_v1.matching_attempts (
  id, order_id, wave, status, started_at, expires_at
) values (
  'ce250000-0000-4000-8000-000000000002',
  'ce100000-0000-4000-8000-000000000003', 'WAVE_1', 'OPEN',
  pg_catalog.clock_timestamp() - interval '60 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes'
);
insert into dastak_v1.merchant_opportunities (
  id, matching_attempt_id, order_id, organization_id, branch_id,
  status, started_at, expires_at, promised_prep_minutes,
  responded_by, responded_at
) values (
  'ce260000-0000-4000-8000-000000000002',
  'ce250000-0000-4000-8000-000000000002',
  'ce100000-0000-4000-8000-000000000003',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001', 'SELECTED',
  pg_catalog.clock_timestamp() - interval '60 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes', 10,
  'ce000000-0000-4000-8000-000000000001',
  pg_catalog.clock_timestamp() - interval '55 minutes'
);
insert into dastak_v1.fulfilments (
  id, order_id, organization_id, branch_id, source_opportunity_id,
  fulfilment_type, status, promised_prep_minutes, committed_at,
  prep_started_at, estimated_ready_at, ready_at, actual_ready_at, package_count
) values (
  'ce270000-0000-4000-8000-000000000002',
  'ce100000-0000-4000-8000-000000000003',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001',
  'ce260000-0000-4000-8000-000000000002',
  'RETAIL', 'PICKED_UP', 10,
  pg_catalog.clock_timestamp() - interval '55 minutes',
  pg_catalog.clock_timestamp() - interval '50 minutes',
  pg_catalog.clock_timestamp() - interval '40 minutes',
  pg_catalog.statement_timestamp() - interval '42 minutes',
  pg_catalog.statement_timestamp() - interval '42 minutes', 1
);
insert into dastak_v1.delivery_missions (
  id, order_id, status, assigned_rider_id, assigned_transport_type,
  transport_snapshot, pickup_count, assigned_at,
  first_package_picked_up_at, all_packages_picked_up_at, out_for_delivery_at
) values (
  'ce280000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000003', 'OUT_FOR_DELIVERY',
  'ce000000-0000-4000-8000-000000000003', 'WALKING', '{}', 1,
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() - interval '20 minutes',
  pg_catalog.clock_timestamp() - interval '19 minutes',
  pg_catalog.clock_timestamp() - interval '18 minutes'
);
insert into dastak_v1.verification_handoffs (
  id, order_id, mission_id, fulfilment_id, handoff_type, status,
  code_digest, activated_at
) values (
  'ce290000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000003',
  'ce280000-0000-4000-8000-000000000001', null,
  'RIDER_TO_CUSTOMER', 'ACTIVE',
  pg_catalog.decode(pg_catalog.repeat('03', 32), 'hex'),
  pg_catalog.clock_timestamp() - interval '18 minutes'
);

select is(
  dastak_v1_api.order_json(
    'ce100000-0000-4000-8000-000000000003',
    'ce000000-0000-4000-8000-000000000001'
  ) #>> '{delivery,riderLocation,latitude}',
  '12.682',
  'the active customer order exposes the assigned rider latest latitude'
);
select is(
  dastak_v1_api.order_json(
    'ce100000-0000-4000-8000-000000000003',
    'ce000000-0000-4000-8000-000000000001'
  ) #>> '{delivery,riderLocation,longitude}',
  '78.622',
  'the active customer order exposes the assigned rider latest longitude'
);
select cmp_ok(
  (
    dastak_v1_api.order_json(
      'ce100000-0000-4000-8000-000000000003',
      'ce000000-0000-4000-8000-000000000001'
    ) #>> '{delivery,distanceToDestinationMeters}'
  )::bigint,
  '>', 0::bigint,
  'the live projection supplies customer-safe distance remaining'
);
select ok(
  not (
    dastak_v1_api.order_json(
      'ce100000-0000-4000-8000-000000000003',
      'ce000000-0000-4000-8000-000000000001'
    )::text ~* 'Private Retail Branch|Private pickup address'
  ),
  'live tracking still leaks no retail merchant identity or pickup address'
);

select * from finish();
rollback;
