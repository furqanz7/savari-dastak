begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('dastak_v1', 'wave2_provisional_holds', 'Wave 2 holds exist');
select has_table('dastak_v1', 'fulfilment_plans', 'fulfilment plans exist');
select has_table('dastak_v1', 'payments', 'V1 payments exist');
select has_table('dastak_v1', 'payment_provider_events', 'provider events exist');
select has_table(
  'dastak_v1', 'payment_reconciliation_cases', 'late-success reconciliation exists'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relname in (
        'wave2_provisional_holds', 'fulfilment_plans',
        'fulfilment_plan_merchants', 'fulfilment_plan_lines',
        'payments', 'payment_attempts', 'payment_provider_events',
        'payment_reconciliation_cases'
      )
      and not relation.relrowsecurity
  ),
  0::bigint,
  'all Step 2 domain tables have RLS enabled'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_accept_wave2_opportunity(uuid,text,bigint,integer)',
    'EXECUTE'
  ),
  false,
  'anonymous actors cannot accept Wave 2 opportunities'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_record_razorpay_event(text,text,text,text,text,bigint,timestamptz,text)',
    'EXECUTE'
  ),
  false,
  'authenticated clients cannot forge provider events'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
('98000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-customer@example.test', '', now(), now(), now()),
('98000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-owner@example.test', '', now(), now(), now()),
('98000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-merchant-a@example.test', '', now(), now(), now()),
('98000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-merchant-b@example.test', '', now(), now(), now()),
('98000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'step2-merchant-c@example.test', '', now(), now(), now());

insert into public.accounts (id, display_name, phone_number) values
('98000000-0000-4000-8000-000000000001', 'Step Two Customer', '+919800000001'),
('98000000-0000-4000-8000-000000000002', 'Step Two Owner', '+919800000002'),
('98000000-0000-4000-8000-000000000003', 'Step Two Merchant A', '+919800000003'),
('98000000-0000-4000-8000-000000000004', 'Step Two Merchant B', '+919800000004'),
('98000000-0000-4000-8000-000000000005', 'Step Two Merchant C', '+919800000005');

insert into private.account_memberships (account_id, role, approved_at) values
('98000000-0000-4000-8000-000000000001', 'customer', null),
('98000000-0000-4000-8000-000000000002', 'owner', now()),
('98000000-0000-4000-8000-000000000003', 'merchant', now()),
('98000000-0000-4000-8000-000000000004', 'merchant', now()),
('98000000-0000-4000-8000-000000000005', 'merchant', now());

insert into public.service_zones (id, name, boundary, active) values (
  '98000000-0000-4000-8000-000000000010',
  'Step Two Zone',
  extensions.st_geomfromtext('POLYGON((78 12,79 12,79 13,78 13,78 12))', 4326),
  true
);

insert into dastak_v1.categories (id, name, slug, status, created_by) values (
  '98000000-0000-4000-8000-000000000011',
  'Step Two Category', 'step-two-category', 'ACTIVE',
  '98000000-0000-4000-8000-000000000002'
);
insert into dastak_v1.subcategories (
  id, category_id, name, slug, status, created_by
) values (
  '98000000-0000-4000-8000-000000000012',
  '98000000-0000-4000-8000-000000000011',
  'Step Two Subcategory', 'step-two-subcategory', 'ACTIVE',
  '98000000-0000-4000-8000-000000000002'
);
insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, logistics_attributes,
  status, created_by
) values
(
  '98000000-0000-4000-8000-000000000013',
  '98000000-0000-4000-8000-000000000012',
  'Step Two Product A', 'step-two-product-a', '1 unit', 1200, 1000,
  '{"weightGrams":400,"lengthMillimetres":150,"widthMillimetres":100,"heightMillimetres":80,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}',
  'ACTIVE', '98000000-0000-4000-8000-000000000002'
),
(
  '98000000-0000-4000-8000-000000000014',
  '98000000-0000-4000-8000-000000000012',
  'Step Two Product B', 'step-two-product-b', '1 unit', 2200, 2000,
  '{"weightGrams":600,"lengthMillimetres":200,"widthMillimetres":100,"heightMillimetres":90,"temperatureClass":"AMBIENT","fragile":false,"bulky":false}',
  'ACTIVE', '98000000-0000-4000-8000-000000000002'
);

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values
('98000000-0000-4000-8000-000000000020', 'Step Two A Private Limited',
 'Step Two Merchant A', 'RETAIL', 'ACTIVE', '98000000-0000-4000-8000-000000000002'),
('98000000-0000-4000-8000-000000000030', 'Step Two B Private Limited',
 'Step Two Merchant B', 'RETAIL', 'ACTIVE', '98000000-0000-4000-8000-000000000002'),
('98000000-0000-4000-8000-000000000040', 'Step Two C Private Limited',
 'Step Two Merchant C', 'DASTAK_CONVENIENCE_STORE', 'ACTIVE',
 '98000000-0000-4000-8000-000000000002');

insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id, address_snapshot,
  location, capacity_limit, status, created_by
) values
('98000000-0000-4000-8000-000000000021', '98000000-0000-4000-8000-000000000020',
 'Step Two Branch A', '98000000-0000-4000-8000-000000000010', '{}',
 extensions.st_setsrid(extensions.st_makepoint(78.60, 12.68), 4326), 5, 'ACTIVE',
 '98000000-0000-4000-8000-000000000002'),
('98000000-0000-4000-8000-000000000031', '98000000-0000-4000-8000-000000000030',
 'Step Two Branch B', '98000000-0000-4000-8000-000000000010', '{}',
 extensions.st_setsrid(extensions.st_makepoint(78.61, 12.68), 4326), 5, 'ACTIVE',
 '98000000-0000-4000-8000-000000000002'),
('98000000-0000-4000-8000-000000000041', '98000000-0000-4000-8000-000000000040',
 'Step Two Branch C', '98000000-0000-4000-8000-000000000010', '{}',
 extensions.st_setsrid(extensions.st_makepoint(78.62, 12.68), 4326), 5, 'ACTIVE',
 '98000000-0000-4000-8000-000000000002');

insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values
('98000000-0000-4000-8000-000000000022', '98000000-0000-4000-8000-000000000020',
 '98000000-0000-4000-8000-000000000003', 'ACTIVE',
 '98000000-0000-4000-8000-000000000002'),
('98000000-0000-4000-8000-000000000032', '98000000-0000-4000-8000-000000000030',
 '98000000-0000-4000-8000-000000000004', 'ACTIVE',
 '98000000-0000-4000-8000-000000000002'),
('98000000-0000-4000-8000-000000000042', '98000000-0000-4000-8000-000000000040',
 '98000000-0000-4000-8000-000000000005', 'ACTIVE',
 '98000000-0000-4000-8000-000000000002');

insert into dastak_v1.merchant_permission_grants (
  id, merchant_user_id, organization_id, bundle_id, branch_id,
  granted_by, grant_reason
) values
('98000000-0000-4000-8000-000000000023', '98000000-0000-4000-8000-000000000022',
 '98000000-0000-4000-8000-000000000020', '10000000-0000-4000-8000-000000000002',
 '98000000-0000-4000-8000-000000000021', '98000000-0000-4000-8000-000000000002',
 'Step Two branch A test access.'),
('98000000-0000-4000-8000-000000000033', '98000000-0000-4000-8000-000000000032',
 '98000000-0000-4000-8000-000000000030', '10000000-0000-4000-8000-000000000002',
 '98000000-0000-4000-8000-000000000031', '98000000-0000-4000-8000-000000000002',
 'Step Two branch B test access.'),
('98000000-0000-4000-8000-000000000043', '98000000-0000-4000-8000-000000000042',
 '98000000-0000-4000-8000-000000000040', '10000000-0000-4000-8000-000000000002',
 '98000000-0000-4000-8000-000000000041', '98000000-0000-4000-8000-000000000002',
 'Step Two branch C test access.');

insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values
('98000000-0000-4000-8000-000000000021', true, true,
 '98000000-0000-4000-8000-000000000003'),
('98000000-0000-4000-8000-000000000031', true, true,
 '98000000-0000-4000-8000-000000000004'),
('98000000-0000-4000-8000-000000000041', true, true,
 '98000000-0000-4000-8000-000000000005');

insert into dastak_v1.merchant_sku_selections (
  branch_id, sku_id, state, selected_by
) values
('98000000-0000-4000-8000-000000000021', '98000000-0000-4000-8000-000000000013',
 'SELECTED', '98000000-0000-4000-8000-000000000003'),
('98000000-0000-4000-8000-000000000031', '98000000-0000-4000-8000-000000000014',
 'SELECTED', '98000000-0000-4000-8000-000000000004'),
('98000000-0000-4000-8000-000000000041', '98000000-0000-4000-8000-000000000013',
 'SELECTED', '98000000-0000-4000-8000-000000000005'),
('98000000-0000-4000-8000-000000000041', '98000000-0000-4000-8000-000000000014',
 'SELECTED', '98000000-0000-4000-8000-000000000005');

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values
('98000000-0000-4000-8000-000000000050', 'matching.retail_radius_meters', 'GLOBAL',
 '30000', '98000000-0000-4000-8000-000000000002', 'Step Two test radius.'),
('98000000-0000-4000-8000-000000000051', 'retail.prep_time_options_minutes', 'GLOBAL',
 '[10,15,20]', '98000000-0000-4000-8000-000000000002', 'Step Two prep choices.'),
('98000000-0000-4000-8000-000000000052', 'matching.wave2_timeout_seconds', 'GLOBAL',
 '120', '98000000-0000-4000-8000-000000000002', 'Step Two timeout.'),
('98000000-0000-4000-8000-000000000053', 'matching.wave2_hold_seconds', 'GLOBAL',
 '180', '98000000-0000-4000-8000-000000000002', 'Step Two hold.'),
('98000000-0000-4000-8000-000000000054', 'payment.reservation_seconds', 'GLOBAL',
 '300', '98000000-0000-4000-8000-000000000002', 'Step Two payment window.'),
('98000000-0000-4000-8000-000000000055', 'matching.wave2_max_pickup_route_meters',
 'GLOBAL', '50000', '98000000-0000-4000-8000-000000000002', 'Step Two route.'),
('98000000-0000-4000-8000-000000000056', 'matching.operational_reliability_bps',
 'GLOBAL', '9000', '98000000-0000-4000-8000-000000000002', 'Step Two reliability.'),
('98000000-0000-4000-8000-000000000057', 'delivery.transport_load_profiles', 'GLOBAL',
 '[{"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},{"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500},{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]',
 '98000000-0000-4000-8000-000000000002', 'Step Two transport.'),
('98000000-0000-4000-8000-000000000058', 'delivery.default_sku_logistics', 'GLOBAL',
 '{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}',
 '98000000-0000-4000-8000-000000000002', 'Step Two fallback logistics.'),
('98000000-0000-4000-8000-000000000059', 'merchant.reachability_stale_seconds', 'GLOBAL',
 '300', '98000000-0000-4000-8000-000000000002', 'Step Two merchant heartbeat threshold.');

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
create temp table tap_step2_order on commit drop as
select public.dastak_v1_submit_order(
  'step2-order-one',
  0,
  pg_catalog.jsonb_build_object(
    'deliveryAddress', pg_catalog.jsonb_build_object(
      'line1', '1 Step Two Road', 'countryCode', 'IN',
      'latitude', 12.68, 'longitude', 78.63
    ),
    'recipient', pg_catalog.jsonb_build_object(
      'name', 'Step Two Customer', 'phoneNumber', '+919800000001'
    ),
    'lines', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'lineType', 'RETAIL_SKU',
        'skuId', '98000000-0000-4000-8000-000000000013', 'quantity', 2
      ),
      pg_catalog.jsonb_build_object(
        'lineType', 'RETAIL_SKU',
        'skuId', '98000000-0000-4000-8000-000000000014', 'quantity', 3
      )
    )
  )
) body;
reset role;
grant select on tap_step2_order to service_role;

alter table dastak_v1.matching_attempts disable trigger matching_attempts_guard;
alter table dastak_v1.merchant_opportunities disable trigger merchant_opportunities_guard;
update dastak_v1.matching_attempts
set started_at = now() - interval '4 minutes',
    expires_at = now() - interval '1 second'
where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
  and wave = 'WAVE_1';
update dastak_v1.merchant_opportunities
set started_at = now() - interval '4 minutes',
    expires_at = now() - interval '1 second'
where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
  and wave = 'WAVE_1';
alter table dastak_v1.merchant_opportunities enable trigger merchant_opportunities_guard;
alter table dastak_v1.matching_attempts enable trigger matching_attempts_guard;

set local role service_role;
select ok(
  dastak_v1_api.expire_wave1_attempt((
    select id from dastak_v1.matching_attempts
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and wave = 'WAVE_1'
  )),
  'permanent Wave 1 expiry automatically starts Wave 2'
);
reset role;

select is(
  (
    select count(*)
    from dastak_v1.merchant_opportunities
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and wave = 'WAVE_2' and status = 'OFFERED'
  ),
  3::bigint,
  'Wave 2 offers exact branch-specific subsets'
);
select results_eq(
  $$
    select branch_id, count(*)::bigint
    from dastak_v1.merchant_opportunity_lines line
    join dastak_v1.merchant_opportunities opportunity
      on opportunity.id = line.opportunity_id
    where opportunity.order_id = (
      select (body ->> 'id')::uuid from tap_step2_order
    ) and opportunity.wave = 'WAVE_2'
    group by branch_id
    order by branch_id
  $$,
  $$ values
    ('98000000-0000-4000-8000-000000000021'::uuid, 1::bigint),
    ('98000000-0000-4000-8000-000000000031'::uuid, 1::bigint),
    ('98000000-0000-4000-8000-000000000041'::uuid, 2::bigint)
  $$,
  'merchants see only the exact subset Dastak asks them to confirm'
);

create temp table tap_step2_opportunities on commit drop as
select branch_id, id
from dastak_v1.merchant_opportunities
where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
  and wave = 'WAVE_2';
grant select on tap_step2_opportunities to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000003', true);
select public.dastak_v1_accept_wave2_opportunity(
  (select id from tap_step2_opportunities
   where branch_id = '98000000-0000-4000-8000-000000000021'),
  'step2-accept-a', 1, 10
);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000004', true);
select public.dastak_v1_accept_wave2_opportunity(
  (select id from tap_step2_opportunities
   where branch_id = '98000000-0000-4000-8000-000000000031'),
  'step2-accept-b', 1, 10
);
reset role;

select is(
  (
    select sum(held_quantity)
    from dastak_v1.wave2_provisional_holds
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and status = 'HELD'
  ),
  5::bigint,
  'Wave 2 acceptances physically hold every exact requested quantity'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_capacity_slots slot
    join dastak_v1.fulfilments fulfilment on fulfilment.id = slot.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_step2_order)
  ),
  0::bigint,
  'provisional holds consume no final preparation capacity'
);
select is(
  dastak_v1_api.order_json(
    (select (body ->> 'id')::uuid from tap_step2_order),
    '98000000-0000-4000-8000-000000000001'
  ) ->> 'customerState',
  'FINDING_ITEMS',
  'customer stays at FINDING_ITEMS through Wave 2'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000005', true);
select public.dastak_v1_accept_wave2_opportunity(
  (select id from tap_step2_opportunities
   where branch_id = '98000000-0000-4000-8000-000000000041'),
  'step2-accept-c', 1, 10
);
reset role;

select is(
  (
    select merchant_count
    from dastak_v1.fulfilment_plans
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and status = 'LOCKED'
  ),
  1,
  'the valid plan with the fewest merchants beats a complete two-merchant plan'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_line_allocations allocation
    join dastak_v1.order_lines line on line.id = allocation.order_line_id
    where line.order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and allocation.status = 'SELECTED'
      and allocation.allocated_quantity = line.quantity
  ),
  2::bigint,
  'every retail line is allocated once as a whole quantity'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_capacity_slots slot
    join dastak_v1.fulfilments fulfilment on fulfilment.id = slot.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and slot.status = 'HELD'
  ),
  1::bigint,
  'only the selected merchant consumes one capacity slot'
);
select is(
  (
    select count(*)
    from dastak_v1.wave2_provisional_holds
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and status = 'RELEASED'
  ),
  2::bigint,
  'non-selected provisional holds release immediately'
);
select is(
  (
    select status::text
    from dastak_v1.orders
    where id = (select (body ->> 'id')::uuid from tap_step2_order)
  ),
  'AWAITING_PAYMENT',
  'the coordinator opens payment only after complete security and feasibility'
);
select ok(
  dastak_v1_api.order_json(
    (select (body ->> 'id')::uuid from tap_step2_order),
    '98000000-0000-4000-8000-000000000001'
  )::text !~ '(WAVE_1|WAVE_2|Step Two Branch|Step Two Merchant)',
  'customer projection exposes no wave terminology or retail merchant identity'
);

set local role service_role;
create temp table tap_step2_attempt_one on commit drop as
select public.dastak_v1_prepare_razorpay_checkout(
  '98000000-0000-4000-8000-000000000001',
  (select (body ->> 'id')::uuid from tap_step2_order),
  'step2-payment-one'
) body;
create temp table tap_step2_attached_one on commit drop as
select public.dastak_v1_attach_razorpay_order(
  '98000000-0000-4000-8000-000000000001',
  (select (body ->> 'attemptId')::uuid from tap_step2_attempt_one),
  'order_step2one',
  8000,
  'INR'
) body;
reset role;
grant select on tap_step2_attempt_one to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select is(
  public.dastak_v1_report_payment_attempt_failed(
    (select (body ->> 'attemptId')::uuid from tap_step2_attempt_one),
    'CHECKOUT_CANCELLED'
  ) ->> 'status',
  'FAILED',
  'a failed payment attempt records failure without releasing the order'
);
reset role;

select is(
  (
    select status::text from dastak_v1.payments
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
  ),
  'RESERVED',
  'failed payment keeps reservations and capacity active for retry'
);
select is(
  (
    select count(*) from dastak_v1.matching_attempts
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
  ),
  2::bigint,
  'payment retry does not rematch'
);

set local role service_role;
create temp table tap_step2_attempt_two on commit drop as
select public.dastak_v1_prepare_razorpay_checkout(
  '98000000-0000-4000-8000-000000000001',
  (select (body ->> 'id')::uuid from tap_step2_order),
  'step2-payment-two'
) body;
select public.dastak_v1_attach_razorpay_order(
  '98000000-0000-4000-8000-000000000001',
  (select (body ->> 'attemptId')::uuid from tap_step2_attempt_two),
  'order_step2two',
  8000,
  'INR'
);
create temp table tap_step2_capture on commit drop as
select * from public.dastak_v1_record_razorpay_event(
  'event_step2_capture', 'payment_captured', 'order_step2two', 'pay_step2two',
  null, 8000, now(), repeat('a', 64)
);
reset role;

select is(
  (select response_status from tap_step2_capture),
  200,
  'authoritative provider capture succeeds within the active window'
);
select is(
  (
    select status::text from dastak_v1.orders
    where id = (select (body ->> 'id')::uuid from tap_step2_order)
  ),
  'PREPARING',
  'successful payment records Paid and atomically starts preparation'
);
select is(
  (
    select count(*) from dastak_v1.order_state_journal
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and to_status = 'PAID'
  ),
  1::bigint,
  'one logical paid transition is recorded'
);

set local role service_role;
select * from public.dastak_v1_record_razorpay_event(
  'event_step2_capture', 'payment_captured', 'order_step2two', 'pay_step2two',
  null, 8000, now(), repeat('a', 64)
);
select * from public.dastak_v1_record_razorpay_event(
  'event_step2_capture_retry', 'payment_captured', 'order_step2two', 'pay_step2two',
  null, 8000, now(), repeat('b', 64)
);
reset role;

select is(
  (
    select count(*) from dastak_v1.order_state_journal
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
      and to_status = 'PAID'
  ),
  1::bigint,
  'duplicate callbacks remain idempotent'
);
select is(
  (
    select count(*) from dastak_v1.payment_provider_events
    where order_id = (select (body ->> 'id')::uuid from tap_step2_order)
  ),
  2::bigint,
  'provider event retries are retained without duplicate business effects'
);

-- A second fully secured order exercises expiry and late-success handling.
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
create temp table tap_step2_expiry_order on commit drop as
select public.dastak_v1_submit_order(
  'step2-expiry-order', 0,
  '{"deliveryAddress":{"line1":"2 Step Two Road","countryCode":"IN","latitude":12.68,"longitude":78.63},"recipient":{"name":"Step Two Customer","phoneNumber":"+919800000001"},"lines":[{"lineType":"RETAIL_SKU","skuId":"98000000-0000-4000-8000-000000000013","quantity":1},{"lineType":"RETAIL_SKU","skuId":"98000000-0000-4000-8000-000000000014","quantity":1}]}'::jsonb
) body;
reset role;
grant select on tap_step2_expiry_order to service_role;
create temp table tap_step2_expiry_opportunity on commit drop as
select id
from dastak_v1.merchant_opportunities
where order_id = (select (body ->> 'id')::uuid from tap_step2_expiry_order)
  and branch_id = '98000000-0000-4000-8000-000000000041';
grant select on tap_step2_expiry_opportunity to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000005', true);
select public.dastak_v1_accept_wave1_opportunity(
  (select id from tap_step2_expiry_opportunity), 'step2-expiry-secure', 1, 10
);
reset role;

set local role service_role;
create temp table tap_step2_late_attempt on commit drop as
select public.dastak_v1_prepare_razorpay_checkout(
  '98000000-0000-4000-8000-000000000001',
  (select (body ->> 'id')::uuid from tap_step2_expiry_order),
  'step2-late-attempt'
) body;
select public.dastak_v1_attach_razorpay_order(
  '98000000-0000-4000-8000-000000000001',
  (select (body ->> 'attemptId')::uuid from tap_step2_late_attempt),
  'order_step2late', 3000, 'INR'
);
reset role;

alter table dastak_v1.payments disable trigger payments_guard;
update dastak_v1.payments
set reserved_at = now() - interval '4 minutes',
    expires_at = now() - interval '1 second'
where order_id = (select (body ->> 'id')::uuid from tap_step2_expiry_order);
alter table dastak_v1.payments enable trigger payments_guard;

set local role service_role;
select ok(
  dastak_v1_api.expire_payment_reservation(
    (select (body ->> 'id')::uuid from tap_step2_expiry_order)
  ),
  'payment-window expiry executes once'
);
create temp table tap_step2_late_capture on commit drop as
select * from public.dastak_v1_record_razorpay_event(
  'event_step2_late', 'payment_captured', 'order_step2late', 'pay_step2late',
  null, 3000, now(), repeat('c', 64)
);
reset role;

select is(
  (
    select status::text from dastak_v1.orders
    where id = (select (body ->> 'id')::uuid from tap_step2_expiry_order)
  ),
  'PAYMENT_EXPIRED',
  'a late provider success never resurrects an expired order'
);
select is(
  (select response_status from tap_step2_late_capture),
  202,
  'late success enters reconciliation rather than payment success'
);
select is(
  (
    select count(*) from dastak_v1.payment_reconciliation_cases
    where order_id = (select (body ->> 'id')::uuid from tap_step2_expiry_order)
      and reason = 'LATE_SUCCESS_AFTER_PAYMENT_EXPIRED'
  ),
  1::bigint,
  'late capture creates one refund/reversal reconciliation case'
);
select is(
  (
    select count(*)
    from dastak_v1.inventory_holds hold
    join dastak_v1.fulfilments fulfilment on fulfilment.id = hold.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_step2_expiry_order)
      and hold.status = 'HELD'
  ),
  0::bigint,
  'payment expiry releases every physical reservation exactly once'
);
select is(
  (
    select count(*)
    from dastak_v1.retail_capacity_slots slot
    join dastak_v1.fulfilments fulfilment on fulfilment.id = slot.fulfilment_id
    where fulfilment.order_id = (select (body ->> 'id')::uuid from tap_step2_expiry_order)
      and slot.status = 'HELD'
  ),
  0::bigint,
  'payment expiry releases capacity exactly once'
);

select * from finish();
rollback;
