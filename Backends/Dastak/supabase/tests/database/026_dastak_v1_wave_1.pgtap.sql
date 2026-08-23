begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table('dastak_v1', 'matching_attempts', 'matching attempts exist');
select has_table('dastak_v1', 'merchant_opportunities', 'merchant opportunities exist');
select has_table('dastak_v1', 'inventory_holds', 'exact physical holds exist');
select has_table('dastak_v1', 'retail_capacity_slots', 'hard capacity slots exist');
select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relname in (
        'branch_operational_states',
        'matching_attempts',
        'matching_candidate_evaluations',
        'merchant_opportunities',
        'merchant_opportunity_lines',
        'fulfilments',
        'fulfilment_lines',
        'inventory_holds',
        'retail_capacity_slots'
      )
      and not relation.relrowsecurity
  ),
  0::bigint,
  'every Wave 1 table has row level security enabled'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_accept_wave1_opportunity(uuid,text,bigint,integer)',
    'EXECUTE'
  ),
  false,
  'anonymous clients cannot accept Wave 1 opportunities'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_accept_wave1_opportunity(uuid,text,bigint,integer)',
    'EXECUTE'
  ),
  true,
  'authenticated merchant actors can invoke the guarded Wave 1 command'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '97000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-customer@example.test', '',
  now(), now(), now()
),
(
  '97000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-owner@example.test', '',
  now(), now(), now()
),
(
  '97000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-merchant-a@example.test', '',
  now(), now(), now()
),
(
  '97000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'wave1-merchant-b@example.test', '',
  now(), now(), now()
);

insert into public.accounts (id, display_name, phone_number) values
  ('97000000-0000-4000-8000-000000000001', 'Wave One Customer', '+919700000001'),
  ('97000000-0000-4000-8000-000000000002', 'Wave One Owner', '+919700000002'),
  ('97000000-0000-4000-8000-000000000003', 'Wave One Merchant A', '+919700000003'),
  ('97000000-0000-4000-8000-000000000004', 'Wave One Merchant B', '+919700000004');

insert into private.account_memberships (account_id, role, approved_at) values
  ('97000000-0000-4000-8000-000000000001', 'customer', null),
  ('97000000-0000-4000-8000-000000000002', 'owner', now()),
  ('97000000-0000-4000-8000-000000000003', 'merchant', now()),
  ('97000000-0000-4000-8000-000000000004', 'merchant', now());

insert into public.service_zones (id, name, boundary, active) values (
  '97000000-0000-4000-8000-000000000010',
  'Wave One Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78 12,79 12,79 13,78 13,78 12))',
    4326
  ),
  true
);

insert into dastak_v1.categories (id, name, slug, status, created_by) values (
  '97000000-0000-4000-8000-000000000011',
  'Wave One Category',
  'wave-one-category',
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
);
insert into dastak_v1.subcategories (
  id, category_id, name, slug, status, created_by
) values (
  '97000000-0000-4000-8000-000000000012',
  '97000000-0000-4000-8000-000000000011',
  'Wave One Subcategory',
  'wave-one-subcategory',
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
);
insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, status, created_by
) values (
  '97000000-0000-4000-8000-000000000013',
  '97000000-0000-4000-8000-000000000012',
  'Wave One Product',
  'wave-one-product',
  '1 unit',
  1200,
  1000,
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
);

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values
(
  '97000000-0000-4000-8000-000000000020',
  'Wave One Merchant A Private Limited',
  'Wave One Merchant A',
  'RETAIL',
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
),
(
  '97000000-0000-4000-8000-000000000030',
  'Wave One Merchant B Private Limited',
  'Wave One Merchant B',
  'DASTAK_CONVENIENCE_STORE',
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
);

insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id, address_snapshot,
  location, capacity_limit, status, created_by
) values
(
  '97000000-0000-4000-8000-000000000021',
  '97000000-0000-4000-8000-000000000020',
  'Wave One Branch A',
  '97000000-0000-4000-8000-000000000010',
  '{"line1":"21 Wave One Road"}'::jsonb,
  extensions.st_setsrid(extensions.st_makepoint(78.60, 12.68), 4326),
  1,
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
),
(
  '97000000-0000-4000-8000-000000000031',
  '97000000-0000-4000-8000-000000000030',
  'Wave One Branch B',
  '97000000-0000-4000-8000-000000000010',
  '{"line1":"31 Wave One Road"}'::jsonb,
  extensions.st_setsrid(extensions.st_makepoint(78.61, 12.68), 4326),
  5,
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
);

insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values
(
  '97000000-0000-4000-8000-000000000022',
  '97000000-0000-4000-8000-000000000020',
  '97000000-0000-4000-8000-000000000003',
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
),
(
  '97000000-0000-4000-8000-000000000032',
  '97000000-0000-4000-8000-000000000030',
  '97000000-0000-4000-8000-000000000004',
  'ACTIVE',
  '97000000-0000-4000-8000-000000000002'
);

insert into dastak_v1.merchant_permission_grants (
  id, merchant_user_id, organization_id, bundle_id, branch_id,
  granted_by, grant_reason
) values
(
  '97000000-0000-4000-8000-000000000023',
  '97000000-0000-4000-8000-000000000022',
  '97000000-0000-4000-8000-000000000020',
  '10000000-0000-4000-8000-000000000002',
  '97000000-0000-4000-8000-000000000021',
  '97000000-0000-4000-8000-000000000002',
  'Wave One branch test access.'
),
(
  '97000000-0000-4000-8000-000000000033',
  '97000000-0000-4000-8000-000000000032',
  '97000000-0000-4000-8000-000000000030',
  '10000000-0000-4000-8000-000000000002',
  '97000000-0000-4000-8000-000000000031',
  '97000000-0000-4000-8000-000000000002',
  'Wave One branch test access.'
);

insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values
(
  '97000000-0000-4000-8000-000000000021',
  true,
  true,
  '97000000-0000-4000-8000-000000000003'
),
(
  '97000000-0000-4000-8000-000000000031',
  true,
  true,
  '97000000-0000-4000-8000-000000000004'
);

insert into dastak_v1.merchant_sku_selections (
  branch_id, sku_id, state, selected_by
) values
(
  '97000000-0000-4000-8000-000000000021',
  '97000000-0000-4000-8000-000000000013',
  'SELECTED',
  '97000000-0000-4000-8000-000000000003'
),
(
  '97000000-0000-4000-8000-000000000031',
  '97000000-0000-4000-8000-000000000013',
  'SELECTED',
  '97000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);
select throws_ok(
  $$
    select public.dastak_v1_submit_order(
      'wave1-missing-config',
      0,
      '{
        "deliveryAddress":{
          "line1":"Missing Config Road",
          "countryCode":"IN",
          "latitude":12.68,
          "longitude":78.62
        },
        "recipient":{"name":"Wave One Customer","phoneNumber":"+919700000001"},
        "lines":[{
          "lineType":"RETAIL_SKU",
          "skuId":"97000000-0000-4000-8000-000000000013",
          "quantity":1
        }]
      }'::jsonb
    )
  $$,
  '55000',
  'SYSTEM_CONFIGURATION_ERROR',
  'missing required matching configuration is a system/configuration error'
);
reset role;

select is(
  (select count(*) from dastak_v1.matching_attempts),
  0::bigint,
  'missing configuration never opens an unsuccessful matching attempt'
);

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values
(
  '97000000-0000-4000-8000-000000000040',
  'matching.retail_radius_meters',
  'GLOBAL',
  '30000'::jsonb,
  '97000000-0000-4000-8000-000000000002',
  'Wave One deterministic reachability test.'
),
(
  '97000000-0000-4000-8000-000000000041',
  'retail.prep_time_options_minutes',
  'GLOBAL',
  '[]'::jsonb,
  '97000000-0000-4000-8000-000000000002',
  'Wave One invalid preparation options test.'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);
select throws_ok(
  $$
    select public.dastak_v1_submit_order(
      'wave1-invalid-config',
      0,
      '{
        "deliveryAddress":{
          "line1":"Invalid Config Road",
          "countryCode":"IN",
          "latitude":12.68,
          "longitude":78.62
        },
        "recipient":{"name":"Wave One Customer","phoneNumber":"+919700000001"},
        "lines":[{
          "lineType":"RETAIL_SKU",
          "skuId":"97000000-0000-4000-8000-000000000013",
          "quantity":1
        }]
      }'::jsonb
    )
  $$,
  '55000',
  'SYSTEM_CONFIGURATION_ERROR',
  'invalid required matching configuration is a system/configuration error'
);
reset role;

select is(
  (select count(*) from dastak_v1.matching_attempts),
  0::bigint,
  'invalid configuration never opens an unsuccessful matching attempt'
);

update dastak_v1.platform_settings
set setting_value = '[10,15,20]'::jsonb,
    updated_by = '97000000-0000-4000-8000-000000000002',
    update_reason = 'Wave One deterministic preparation options test.',
    version = version + 1
where id = '97000000-0000-4000-8000-000000000041';

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values
(
  '97000000-0000-4000-8000-000000000042',
  'matching.wave2_timeout_seconds', 'GLOBAL', '120',
  '97000000-0000-4000-8000-000000000002', 'Wave 2 test timeout.'
),
(
  '97000000-0000-4000-8000-000000000043',
  'matching.wave2_hold_seconds', 'GLOBAL', '180',
  '97000000-0000-4000-8000-000000000002', 'Wave 2 test physical hold.'
),
(
  '97000000-0000-4000-8000-000000000044',
  'payment.reservation_seconds', 'GLOBAL', '300',
  '97000000-0000-4000-8000-000000000002', 'Payment reservation test window.'
),
(
  '97000000-0000-4000-8000-000000000045',
  'matching.wave2_max_pickup_route_meters', 'GLOBAL', '50000',
  '97000000-0000-4000-8000-000000000002', 'Wave 2 route test limit.'
),
(
  '97000000-0000-4000-8000-000000000046',
  'matching.operational_reliability_bps', 'GLOBAL', '9000',
  '97000000-0000-4000-8000-000000000002', 'Wave 2 reliability test score.'
),
(
  '97000000-0000-4000-8000-000000000047',
  'delivery.transport_load_profiles', 'GLOBAL',
  '[{"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},{"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500},{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]',
  '97000000-0000-4000-8000-000000000002', 'Wave 2 transport test profile.'
),
(
  '97000000-0000-4000-8000-000000000048',
  'delivery.default_sku_logistics', 'GLOBAL',
  '{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}',
  '97000000-0000-4000-8000-000000000002', 'Wave 2 explicit test logistics fallback.'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);

create temp table tap_wave1_order on commit drop as
select public.dastak_v1_submit_order(
  'wave1-submit-one',
  0,
  pg_catalog.jsonb_build_object(
    'deliveryAddress', pg_catalog.jsonb_build_object(
      'line1', '1 Wave One Customer Road',
      'city', 'Vaniyambadi',
      'countryCode', 'IN',
      'latitude', 12.68,
      'longitude', 78.62
    ),
    'recipient', pg_catalog.jsonb_build_object(
      'name', 'Wave One Customer',
      'phoneNumber', '+919700000001'
    ),
    'lines', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'lineType', 'RETAIL_SKU',
        'skuId', '97000000-0000-4000-8000-000000000013',
        'quantity', 3
      )
    )
  )
) as body;
reset role;

select is(
  (
    select count(*)
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.order_id = (
      select (body ->> 'id')::uuid from tap_wave1_order
    )
  ),
  2::bigint,
  'every eligible full-basket branch receives a Wave 1 opportunity'
);
select is(
  (
    select count(distinct (opportunity.started_at, opportunity.expires_at))
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.order_id = (
      select (body ->> 'id')::uuid from tap_wave1_order
    )
  ),
  1::bigint,
  'all Wave 1 candidates receive the identical authoritative window'
);
select is(
  (
    select extract(epoch from max(expires_at - started_at))::integer
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.order_id = (
      select (body ->> 'id')::uuid from tap_wave1_order
    )
  ),
  180,
  'Wave 1 has the locked 180-second server deadline'
);
select is(
  (
    select count(*)
    from dastak_v1.merchant_opportunity_lines opportunity_line
    join dastak_v1.merchant_opportunities opportunity
      on opportunity.id = opportunity_line.opportunity_id
    where opportunity.order_id = (
      select (body ->> 'id')::uuid from tap_wave1_order
    )
      and opportunity_line.requested_quantity = 3
  ),
  2::bigint,
  'each opportunity contains the complete exact basket quantity'
);
select is(
  (
    select count(*)
    from dastak_v1.domain_events_outbox event
    where event.event_type = 'MERCHANT_OPPORTUNITY_OFFERED'
      and event.aggregate_id in (
        select opportunity.id
        from dastak_v1.merchant_opportunities opportunity
        where opportunity.order_id = (
          select (body ->> 'id')::uuid from tap_wave1_order
        )
      )
      and event.status = 'PENDING'
  ),
  2::bigint,
  'opportunity state and asynchronous notification intent commit together'
);

create temp table tap_wave1_opportunity_ids on commit drop as
select opportunity.branch_id, opportunity.id as opportunity_id
from dastak_v1.merchant_opportunities opportunity
where opportunity.order_id = (
  select (body ->> 'id')::uuid from tap_wave1_order
);
grant select on tap_wave1_opportunity_ids to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000002',
  true
);
select is(
  pg_catalog.jsonb_array_length(
    public.dastak_v1_list_merchant_opportunities(50) -> 'opportunities'
  ),
  0,
  'a legacy platform owner cannot list merchant opportunities'
);
select throws_ok(
  pg_catalog.format(
    'select public.dastak_v1_get_merchant_opportunity(%L::uuid)',
    (
      select opportunity_id
      from tap_wave1_opportunity_ids
      where branch_id = '97000000-0000-4000-8000-000000000021'
    )
  ),
  'P0002',
  'opportunity not found',
  'a legacy platform owner cannot get a merchant opportunity'
);
select throws_ok(
  pg_catalog.format(
    'select public.dastak_v1_accept_wave1_opportunity(%L::uuid, %L, 1, 10)',
    (
      select opportunity_id
      from tap_wave1_opportunity_ids
      where branch_id = '97000000-0000-4000-8000-000000000021'
    ),
    'wave1-owner-accept-denied'
  ),
  '42501',
  'permission denied',
  'a legacy platform owner cannot accept for a merchant'
);
select throws_ok(
  pg_catalog.format(
    'select public.dastak_v1_decline_opportunity(%L::uuid, %L, 1)',
    (
      select opportunity_id
      from tap_wave1_opportunity_ids
      where branch_id = '97000000-0000-4000-8000-000000000021'
    ),
    'wave1-owner-decline-denied'
  ),
  '42501',
  'permission denied',
  'a legacy platform owner cannot decline for a merchant'
);
select throws_ok(
  $$
    select public.dastak_v1_set_branch_operational_state(
      '97000000-0000-4000-8000-000000000021',
      'wave1-owner-branch-denied',
      1,
      true,
      true
    )
  $$,
  '42501',
  'permission denied',
  'a legacy platform owner cannot operate a merchant branch'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000003',
  true
);
select is(
  pg_catalog.jsonb_array_length(
    public.dastak_v1_list_merchant_opportunities(50) -> 'opportunities'
  ),
  1,
  'Merchant A lists only its own opportunity'
);
select throws_ok(
  pg_catalog.format(
    'select public.dastak_v1_get_merchant_opportunity(%L::uuid)',
    (
      select opportunity_id
      from tap_wave1_opportunity_ids
      where branch_id = '97000000-0000-4000-8000-000000000031'
    )
  ),
  'P0002',
  'opportunity not found',
  'Merchant A cannot get Merchant B opportunity'
);
select throws_ok(
  pg_catalog.format(
    'select public.dastak_v1_accept_wave1_opportunity(%L::uuid, %L, 1, 10)',
    (
      select opportunity_id
      from tap_wave1_opportunity_ids
      where branch_id = '97000000-0000-4000-8000-000000000031'
    ),
    'wave1-cross-merchant-accept-denied'
  ),
  '42501',
  'permission denied',
  'Merchant A cannot accept Merchant B opportunity'
);
select throws_ok(
  pg_catalog.format(
    'select public.dastak_v1_decline_opportunity(%L::uuid, %L, 1)',
    (
      select opportunity_id
      from tap_wave1_opportunity_ids
      where branch_id = '97000000-0000-4000-8000-000000000031'
    ),
    'wave1-cross-merchant-decline-denied'
  ),
  '42501',
  'permission denied',
  'Merchant A cannot decline Merchant B opportunity'
);
select throws_ok(
  $$
    select public.dastak_v1_set_branch_operational_state(
      '97000000-0000-4000-8000-000000000031',
      'wave1-cross-merchant-branch-denied',
      1,
      true,
      true
    )
  $$,
  '42501',
  'permission denied',
  'Merchant A cannot operate Merchant B branch'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000003',
  true
);
create temp table tap_wave1_accept on commit drop as
select public.dastak_v1_accept_wave1_opportunity(
  (
    select opportunity_id
    from tap_wave1_opportunity_ids
    where branch_id = '97000000-0000-4000-8000-000000000021'
  ),
  'wave1-accept-a',
  1,
  10
) as body;
reset role;

select is(
  (
    select status::text
    from dastak_v1.orders
    where id = (select (body ->> 'id')::uuid from tap_wave1_order)
  ),
  'AWAITING_PAYMENT',
  'a complete Wave 1 reservation passes the authoritative coordinator'
);
select is(
  (
    select count(*)
    from dastak_v1.orders
    where id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and fully_secured_at is not null
      and payment_expires_at is not null
      and paid_at is null
      and version = 4
  ),
  1::bigint,
  'a Wave 1 winner becomes payment eligible only through full coordination'
);
select is(
  dastak_v1_api.order_json(
    (select (body ->> 'id')::uuid from tap_wave1_order),
    '97000000-0000-4000-8000-000000000001'
  ) -> 'fulfilmentProgress' ->> 'state',
  'ORDER_SECURED',
  'customer leaves FINDING_ITEMS only after complete coordination'
);
select is(
  (
    select count(*)
    from dastak_v1.merchant_opportunities
    where order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and status = 'SELECTED'
  ),
  1::bigint,
  'exactly one merchant opportunity is selected'
);
select is(
  (
    select count(*)
    from dastak_v1.merchant_opportunities
    where order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and status = 'LOST'
  ),
  1::bigint,
  'the competing Wave 1 opportunity is invalidated as a loser'
);
select is(
  (
    select sum(held_quantity)
    from dastak_v1.inventory_holds hold
    join dastak_v1.fulfilments fulfilment on fulfilment.id = hold.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and hold.status = 'HELD'
  ),
  3::bigint,
  'merchant acceptance is exact live physical stock confirmation'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_capacity_slots slot
    join dastak_v1.fulfilments fulfilment on fulfilment.id = slot.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and slot.status = 'HELD'
  ),
  1::bigint,
  'the winner consumes exactly one hard branch capacity slot'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_line_allocations allocation
    join dastak_v1.order_lines order_line on order_line.id = allocation.order_line_id
    where order_line.order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and allocation.allocated_quantity = order_line.quantity
      and allocation.status = 'SELECTED'
  ),
  1::bigint,
  'the retail line is allocated whole and never quantity-split'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);
create temp table tap_wave1_capacity_order on commit drop as
select public.dastak_v1_submit_order(
  'wave1-capacity-submit',
  0,
  '{
    "deliveryAddress":{
      "line1":"2 Wave One Customer Road",
      "countryCode":"IN",
      "latitude":12.68,
      "longitude":78.62
    },
    "recipient":{"name":"Wave One Customer","phoneNumber":"+919700000001"},
    "lines":[{
      "lineType":"RETAIL_SKU",
      "skuId":"97000000-0000-4000-8000-000000000013",
      "quantity":1
    }]
  }'::jsonb
) as body;
reset role;

select ok(
  exists (
    select 1
    from dastak_v1.matching_candidate_evaluations evaluation
    where evaluation.order_id = (
      select (body ->> 'id')::uuid from tap_wave1_capacity_order
    )
      and evaluation.branch_id = '97000000-0000-4000-8000-000000000021'
      and not evaluation.eligible
      and evaluation.exclusion_reasons @> array['AT_CAPACITY']
  ),
  'a branch at hard capacity is excluded from new matching'
);
select is(
  (
    select count(*)
    from dastak_v1.merchant_opportunities
    where order_id = (select (body ->> 'id')::uuid from tap_wave1_capacity_order)
      and status = 'OFFERED'
  ),
  1::bigint,
  'capacity exclusion does not affect another eligible branch'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);
select is(
  public.dastak_v1_cancel_prepayment_order(
    (select (body ->> 'id')::uuid from tap_wave1_capacity_order),
    'wave1-capacity-cancel',
    2
  ) ->> 'status',
  'CANCELLED_PREPAYMENT',
  'customer can cancel an active matching attempt'
);
select is(
  public.dastak_v1_cancel_prepayment_order(
    (select (body ->> 'id')::uuid from tap_wave1_order),
    'wave1-winner-cancel',
    4
  ) ->> 'status',
  'CANCELLED_PREPAYMENT',
  'customer can cancel after an unpaid Wave 1 winner'
);
reset role;

select is(
  (
    select count(*)
    from dastak_v1.inventory_holds hold
    join dastak_v1.fulfilments fulfilment on fulfilment.id = hold.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and hold.status = 'HELD'
  ),
  0::bigint,
  'cancellation after a winner releases every physical hold'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_capacity_slots slot
    join dastak_v1.fulfilments fulfilment on fulfilment.id = slot.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and slot.status = 'HELD'
  ),
  0::bigint,
  'cancellation after a winner releases capacity exactly once'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_line_allocations allocation
    join dastak_v1.order_lines order_line on order_line.id = allocation.order_line_id
    where order_line.order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and allocation.status <> 'RELEASED'
  ),
  0::bigint,
  'cancellation after a winner releases the final line allocation'
);
select is(
  (
    select count(*)
    from dastak_v1.fulfilments
    where order_id = (select (body ->> 'id')::uuid from tap_wave1_order)
      and status = 'RELEASED'
  ),
  1::bigint,
  'the unpaid winner fulfilment records its release'
);

-- A manually constructed past-deadline attempt avoids a three-minute sleep
-- while preserving the production authoritative-window guards.
insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, version
) values (
  '97000000-0000-4000-8000-000000000050',
  'DSK-WAVE1-EXPIRY',
  '97000000-0000-4000-8000-000000000001',
  'RETAIL_ONLY',
  'MATCHING',
  now() - interval '5 minutes',
  2
);
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values (
  '97000000-0000-4000-8000-000000000050',
  '{"line1":"Expiry Road","countryCode":"IN","latitude":12.68,"longitude":78.62}',
  '{"name":"Wave One Customer","phoneNumber":"+919700000001"}',
  pg_catalog.decode('00', 'hex')
);
insert into dastak_v1.order_lines (
  id, order_id, line_type, sku_id, product_name_snapshot, pack_size_snapshot,
  quantity, unit_price_paise, status
) values (
  '97000000-0000-4000-8000-000000000051',
  '97000000-0000-4000-8000-000000000050',
  'RETAIL_SKU',
  '97000000-0000-4000-8000-000000000013',
  'Wave One Product',
  '1 unit',
  1,
  1000,
  'ORDERED'
);
insert into dastak_v1.order_price_snapshots (
  order_id, snapshot_kind, subtotal_paise, total_paise
) values (
  '97000000-0000-4000-8000-000000000050',
  'SUBMITTED',
  1000,
  1000
);
insert into dastak_v1.matching_attempts (
  id, order_id, wave, status, started_at, expires_at
) values (
  '97000000-0000-4000-8000-000000000052',
  '97000000-0000-4000-8000-000000000050',
  'WAVE_1',
  'OPEN',
  now() - interval '4 minutes',
  now() - interval '1 minute'
);
insert into dastak_v1.merchant_opportunities (
  id, matching_attempt_id, order_id, organization_id, branch_id,
  status, started_at, expires_at
) values (
  '97000000-0000-4000-8000-000000000053',
  '97000000-0000-4000-8000-000000000052',
  '97000000-0000-4000-8000-000000000050',
  '97000000-0000-4000-8000-000000000030',
  '97000000-0000-4000-8000-000000000031',
  'OFFERED',
  now() - interval '4 minutes',
  now() - interval '1 minute'
);
insert into dastak_v1.merchant_opportunity_lines (
  opportunity_id, order_line_id, sku_id, product_name_snapshot,
  pack_size_snapshot, requested_quantity
) values (
  '97000000-0000-4000-8000-000000000053',
  '97000000-0000-4000-8000-000000000051',
  '97000000-0000-4000-8000-000000000013',
  'Wave One Product',
  '1 unit',
  1
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000004',
  true
);
select throws_ok(
  $$
    select public.dastak_v1_accept_wave1_opportunity(
      '97000000-0000-4000-8000-000000000053',
      'wave1-late-accept',
      1,
      10
    )
  $$,
  '55000',
  'matching opportunity has expired',
  'late merchant acceptance is rejected by the backend deadline'
);
reset role;

set local role service_role;
select ok(
  dastak_v1_api.expire_wave1_attempt(
    '97000000-0000-4000-8000-000000000052'
  ),
  'the expiry worker closes a due Wave 1 attempt'
);
reset role;

select is(
  (
    select status::text
    from dastak_v1.matching_attempts
    where id = '97000000-0000-4000-8000-000000000052'
  ),
  'EXPIRED',
  'the authoritative Wave 1 attempt remains permanently expired'
);
select is(
  (
    select count(*)
    from dastak_v1.matching_attempts
    where order_id = '97000000-0000-4000-8000-000000000050'
      and wave = 'WAVE_2'
      and status = 'OPEN'
  ),
  1::bigint,
  'Wave 1 expiry automatically starts Wave 2 without customer Retry'
);
select is(
  (
    select count(*)
    from dastak_v1.orders
    where id = '97000000-0000-4000-8000-000000000050'
      and status = 'MATCHING'
      and fully_secured_at is null
      and payment_expires_at is null
  ),
  1::bigint,
  'Wave 1 expiry does not create payment eligibility'
);
select is(
  (
    select count(*)
    from dastak_v1.domain_events_outbox
    where event_type in ('WAVE_1_EXPIRED', 'WAVE_2_STARTED')
      and payload ->> 'orderId' = '97000000-0000-4000-8000-000000000050'
      and status = 'PENDING'
  ),
  2::bigint,
  'expiry state and asynchronous Wave 2 notification intent commit together'
);

select ok(
  not (
    dastak_v1_api.order_json(
      (select (body ->> 'id')::uuid from tap_wave1_order),
      '97000000-0000-4000-8000-000000000001'
    )::text ~* '(merchant|branch|wave_1|wave_2)'
  ),
  'customer order projection exposes no retail merchant or Wave identity'
);

select * from finish();
rollback;
