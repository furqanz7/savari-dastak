begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (select pg_catalog.array_agg(bundle.bundle_key order by bundle.bundle_key)
   from dastak_v1.permission_bundle_permissions permission
   join dastak_v1.permission_bundles bundle on bundle.id = permission.bundle_id
   where permission.permission_key = 'platform.merchants.manage'),
  array['executive_admin', 'platform_super_admin']::text[],
  'Merchant governance belongs only to Superadmin and Executive Admin'
);

select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.assert_merchant_governance_admin(uuid)'::regprocedure),
  'platform\.merchants\.manage',
  'the governance projection requires the dedicated permission'
);
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.assert_merchant_governance_admin(uuid)'::regprocedure),
  'admin_role_for_actor\(p_actor_id\)',
  'the governance projection independently requires an active Admin assignment'
);
select is(has_function_privilege('anon', 'public.dastak_v1_admin_merchant_governance_page(text,uuid,uuid,integer,timestamptz,uuid)', 'EXECUTE'), false, 'anonymous actors cannot execute the governance projection');
select is(has_function_privilege('authenticated', 'public.dastak_v1_admin_merchant_governance_page(text,uuid,uuid,integer,timestamptz,uuid)', 'EXECUTE'), true, 'authenticated callers reach the caller-bound authorization check');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c2200000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-super@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-executive@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-trace@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-recovery@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000005', '00000000-0000-0000-8000-000000000000', 'authenticated', 'authenticated', 'c22-finance@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-catalogue@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-inactive@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000008', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-merchant@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000009', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-rider@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000010', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-customer@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2200000-0000-4000-8000-000000000011', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c22-user@example.test', '', now(), '{}', '{}', now(), now());

insert into public.accounts (id, display_name, phone_number, account_state)
select id, display_name, phone_number, 'ACTIVE'
from (values
  ('c2200000-0000-4000-8000-000000000001'::uuid, 'C22 Superadmin', '+919710000001'),
  ('c2200000-0000-4000-8000-000000000002'::uuid, 'C22 Executive', '+919710000002'),
  ('c2200000-0000-4000-8000-000000000003'::uuid, 'C22 Trace', '+919710000003'),
  ('c2200000-0000-4000-8000-000000000004'::uuid, 'C22 Recovery', '+919710000004'),
  ('c2200000-0000-4000-8000-000000000005'::uuid, 'C22 Finance', '+919710000005'),
  ('c2200000-0000-4000-8000-000000000006'::uuid, 'C22 Catalogue', '+919710000006'),
  ('c2200000-0000-4000-8000-000000000007'::uuid, 'C22 Inactive Admin', '+919710000007'),
  ('c2200000-0000-4000-8000-000000000008'::uuid, 'C22 Merchant', '+919710000008'),
  ('c2200000-0000-4000-8000-000000000009'::uuid, 'C22 Rider', '+919710000009'),
  ('c2200000-0000-4000-8000-000000000010'::uuid, 'C22 Customer', '+919710000010'),
  ('c2200000-0000-4000-8000-000000000011'::uuid, 'C22 User', '+919710000011')
) fixture(id, display_name, phone_number);

insert into private.account_memberships (account_id, role)
select id, role::private.membership_role from (values
  ('c2200000-0000-4000-8000-000000000001'::uuid, 'customer'),
  ('c2200000-0000-4000-8000-000000000002'::uuid, 'customer'),
  ('c2200000-0000-4000-8000-000000000003'::uuid, 'customer'),
  ('c2200000-0000-4000-8000-000000000004'::uuid, 'customer'),
  ('c2200000-0000-4000-8000-000000000005'::uuid, 'customer'),
  ('c2200000-0000-4000-8000-000000000006'::uuid, 'customer'),
  ('c2200000-0000-4000-8000-000000000007'::uuid, 'owner'),
  ('c2200000-0000-4000-8000-000000000008'::uuid, 'merchant'),
  ('c2200000-0000-4000-8000-000000000009'::uuid, 'dastak_partner'),
  ('c2200000-0000-4000-8000-000000000010'::uuid, 'customer'),
  ('c2200000-0000-4000-8000-000000000011'::uuid, 'customer')
) fixture(id, role);
update private.account_memberships set approved_at = now(), suspended_until = null
where account_id = 'c2200000-0000-4000-8000-000000000007' and role = 'owner';

insert into dastak_v1.permission_bundles (id, bundle_key, display_name, scope, description) values
  ('c2210000-0000-4000-8000-000000000001', 'c22_trace_only', 'C2.2 trace only', 'PLATFORM', 'Rollback-only trace fixture');
insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key) values
  ('c2210000-0000-4000-8000-000000000001', 'platform.orders.trace');

select lives_ok($$select dastak_v1_api.bootstrap_superadmin('c2200000-0000-4000-8000-000000000001')$$, 'rollback fixture establishes Superadmin');
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_set_executive_admin(1::smallint, 'c22-executive@example.test', 1::bigint, 'Bind Merchant governance test seat.')$$, 'rollback fixture establishes Executive Admin');
reset role;

insert into dastak_v1.platform_permission_grants (account_id, bundle_id, granted_by, grant_reason)
select fixture.account_id, bundle.id, 'c2200000-0000-4000-8000-000000000001', 'C2.2 negative authorization fixture'
from (values
  ('c2200000-0000-4000-8000-000000000003'::uuid, 'c22_trace_only'),
  ('c2200000-0000-4000-8000-000000000004'::uuid, 'recovery_operations'),
  ('c2200000-0000-4000-8000-000000000005'::uuid, 'finance_operations'),
  ('c2200000-0000-4000-8000-000000000006'::uuid, 'catalogue_admin'),
  ('c2200000-0000-4000-8000-000000000007'::uuid, 'executive_admin')
) fixture(account_id, bundle_key)
join dastak_v1.permission_bundles bundle on bundle.bundle_key = fixture.bundle_key;

insert into public.service_zones (id, name, boundary, center, coverage_radius_m) values (
  'c2220000-0000-4000-8000-000000000001', 'C2.2 Test Zone',
  extensions.st_geomfromtext('POLYGON((78 12,79 12,79 13,78 13,78 12))', 4326),
  extensions.st_setsrid(extensions.st_makepoint(78.5, 12.5), 4326), 30000
);
insert into dastak_v1.merchant_organizations (id, legal_name, display_name, merchant_type, status, created_by) values
  ('c2230000-0000-4000-8000-000000000001', 'Active Work Foods Pvt Ltd', 'Active Work Foods', 'RESTAURANT_CAFE', 'ACTIVE', 'c2200000-0000-4000-8000-000000000008'),
  ('c2230000-0000-4000-8000-000000000002', 'Governed Retail Pvt Ltd', 'Governed Retail', 'RETAIL', 'ACTIVE', 'c2200000-0000-4000-8000-000000000008'),
  ('c2230000-0000-4000-8000-000000000003', 'Executive Cafe Pvt Ltd', 'Executive Cafe', 'RESTAURANT_CAFE', 'ACTIVE', 'c2200000-0000-4000-8000-000000000008');
insert into dastak_v1.merchant_branches (id, organization_id, display_name, service_zone_id, address_snapshot, location, capacity_limit, status, created_by) values
  ('c2240000-0000-4000-8000-000000000001', 'c2230000-0000-4000-8000-000000000001', 'Active Work Branch', 'c2220000-0000-4000-8000-000000000001', '{"line1":"10 Old Street","city":"Vaniyambadi","state":"Tamil Nadu","postalCode":"635751","countryCode":"IN","onboardingMarker":"preserve"}', extensions.st_setsrid(extensions.st_makepoint(78.5,12.5),4326), 5, 'ACTIVE', 'c2200000-0000-4000-8000-000000000008'),
  ('c2240000-0000-4000-8000-000000000002', 'c2230000-0000-4000-8000-000000000002', 'Governed Branch', 'c2220000-0000-4000-8000-000000000001', '{"line1":"20 Market Road","city":"Vaniyambadi","state":"Tamil Nadu","postalCode":"635751","countryCode":"IN"}', extensions.st_setsrid(extensions.st_makepoint(78.55,12.55),4326), 8, 'ACTIVE', 'c2200000-0000-4000-8000-000000000008'),
  ('c2240000-0000-4000-8000-000000000003', 'c2230000-0000-4000-8000-000000000003', 'Executive Branch', 'c2220000-0000-4000-8000-000000000001', '{"line1":"30 Cafe Road","city":"Vaniyambadi","state":"Tamil Nadu","postalCode":"635751","countryCode":"IN"}', extensions.st_setsrid(extensions.st_makepoint(78.6,12.6),4326), 6, 'ACTIVE', 'c2200000-0000-4000-8000-000000000008');
insert into dastak_v1.branch_operational_states (branch_id, is_open, accepting_orders, updated_by) values
  ('c2240000-0000-4000-8000-000000000001', true, true, 'c2200000-0000-4000-8000-000000000008'),
  ('c2240000-0000-4000-8000-000000000002', false, false, 'c2200000-0000-4000-8000-000000000008'),
  ('c2240000-0000-4000-8000-000000000003', true, false, 'c2200000-0000-4000-8000-000000000008');
insert into private.merchant_applications (
  id, account_id, business_name, business_address, evidence_object_path, status,
  reviewed_at, reviewed_by, review_reason, merchant_type, legal_name, location,
  service_zone_id, provisioned_organization_id, provisioned_branch_id
) values (
  'c2250000-0000-4000-8000-000000000001', 'c2200000-0000-4000-8000-000000000008',
  'Active Work Foods', '10 Old Street', 'merchant/test/evidence.jpg', 'approved', now(),
  'c2200000-0000-4000-8000-000000000001', 'Approved before governance action',
  'RESTAURANT_CAFE', 'Active Work Foods Pvt Ltd', extensions.st_setsrid(extensions.st_makepoint(78.5,12.5),4326),
  'c2220000-0000-4000-8000-000000000001', 'c2230000-0000-4000-8000-000000000001', 'c2240000-0000-4000-8000-000000000001'
);
create temporary table onboarding_before as select * from private.merchant_applications where id = 'c2250000-0000-4000-8000-000000000001';

set local session_replication_role = replica;
insert into dastak_v1.orders (id, display_order_number, customer_id, order_type, status, submitted_at) values
  ('c2260000-0000-4000-8000-000000000001', 'DSK-C22-0001', 'c2200000-0000-4000-8000-000000000010', 'RETAIL_ONLY', 'MATCHING', now());
insert into dastak_v1.matching_attempts (id, order_id, wave, status, started_at, expires_at) values
  ('c2270000-0000-4000-8000-000000000001', 'c2260000-0000-4000-8000-000000000001', 'WAVE_1', 'OPEN', now(), now() + interval '15 minutes');
insert into dastak_v1.merchant_opportunities (id, matching_attempt_id, order_id, organization_id, branch_id, status, started_at, expires_at, promised_prep_minutes, responded_by, responded_at, wave) values
  ('c2280000-0000-4000-8000-000000000001', 'c2270000-0000-4000-8000-000000000001', 'c2260000-0000-4000-8000-000000000001', 'c2230000-0000-4000-8000-000000000001', 'c2240000-0000-4000-8000-000000000001', 'SELECTED', now(), now() + interval '15 minutes', 10, 'c2200000-0000-4000-8000-000000000008', now(), 'WAVE_1');
insert into dastak_v1.fulfilments (id, order_id, organization_id, branch_id, source_opportunity_id, fulfilment_type, status, promised_prep_minutes, committed_at, prep_started_at) values
  ('c2290000-0000-4000-8000-000000000001', 'c2260000-0000-4000-8000-000000000001', 'c2230000-0000-4000-8000-000000000001', 'c2240000-0000-4000-8000-000000000001', 'c2280000-0000-4000-8000-000000000001', 'RETAIL', 'PREPARING', 10, now(), now());
insert into dastak_v1.delivery_missions (id, order_id, status, transport_snapshot, pickup_count, delivery_distance_meters, rider_payout_quote_paise, rider_payout_quote_snapshot) values
  ('c22a0000-0000-4000-8000-000000000001', 'c2260000-0000-4000-8000-000000000001', 'SEARCHING_RIDER', '{}', 1, 0, 0, '{}');
insert into dastak_v1.delivery_stops (id, mission_id, order_id, fulfilment_id, branch_id, stop_sequence, status) values
  ('c22b0000-0000-4000-8000-000000000001', 'c22a0000-0000-4000-8000-000000000001', 'c2260000-0000-4000-8000-000000000001', 'c2290000-0000-4000-8000-000000000001', 'c2240000-0000-4000-8000-000000000001', 1, 'PENDING');
insert into dastak_v1.customer_issues (
  id, order_id, customer_id, category, status, description
) values (
  'c22c0000-0000-4000-8000-000000000001',
  'c2260000-0000-4000-8000-000000000001',
  'c2200000-0000-4000-8000-000000000010',
  'DELIVERY_PROBLEM', 'UNDER_REVIEW', 'Rollback-only return route fixture'
);
insert into dastak_v1.returns (
  id, order_id, source, customer_issue_id, status,
  physical_return_required, reason, requested_by
) values (
  'c22d0000-0000-4000-8000-000000000001',
  'c2260000-0000-4000-8000-000000000001', 'CUSTOMER_ISSUE',
  'c22c0000-0000-4000-8000-000000000001', 'RETURN_REQUIRED', true,
  'Rollback-only return route fixture',
  'c2200000-0000-4000-8000-000000000010'
);
insert into dastak_v1.return_packages (
  id, return_id, order_id, package_number, destination_branch_id,
  status, current_custody_owner_type, current_custody_owner_id, created_by
) values (
  'c22e0000-0000-4000-8000-000000000001',
  'c22d0000-0000-4000-8000-000000000001',
  'c2260000-0000-4000-8000-000000000001', 1,
  'c2240000-0000-4000-8000-000000000003',
  'CUSTOMER_READY', 'CUSTOMER', 'c2200000-0000-4000-8000-000000000010',
  'c2200000-0000-4000-8000-000000000001'
);
insert into dastak_v1.return_missions (id, return_id, order_id, status) values (
  'c22f0000-0000-4000-8000-000000000001',
  'c22d0000-0000-4000-8000-000000000001',
  'c2260000-0000-4000-8000-000000000001', 'RIDER_SEARCH'
);
insert into dastak_v1.return_stops (
  id, return_mission_id, return_id, branch_id, stop_sequence, status, package_count
) values (
  'c2300000-0000-4000-8000-000000000001',
  'c22f0000-0000-4000-8000-000000000001',
  'c22d0000-0000-4000-8000-000000000001',
  'c2240000-0000-4000-8000-000000000003', 1, 'PENDING', 1
);
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, 'Superadmin can read Merchant governance');
create temporary table governance_page as select public.dastak_v1_admin_merchant_governance_page('Governed Retail',null,null,50,null,null) body;
select is((select body #>> '{merchants,0,organization,merchantType}' from governance_page), 'RETAIL', 'projection returns merchant type');
select is((select body #>> '{merchants,0,branch,normalizedAddress,line1}' from governance_page), '20 Market Road', 'projection returns normalized pickup address');
select is((select body #>> '{merchants,0,branch,activeNonTerminalFulfilmentCount}' from governance_page), '0', 'projection returns branch fulfilment count');
select is((select body #>> '{serviceZones,0,name}' from governance_page), 'C2.2 Test Zone', 'projection returns governed active service-zone choices');
select throws_ok(
  $$select public.dastak_v1_admin_set_merchant_organization_status('c2230000-0000-4000-8000-000000000001','SUSPENDED',1,'Resolve active work first','active-block')$$,
  '55000', 'ACTIVE_FULFILMENTS_REQUIRE_RESOLUTION', 'active fulfilment/custody blocks organization suspension'
);
select throws_ok(
  $$select public.dastak_v1_admin_correct_merchant_branch_details('c2240000-0000-4000-8000-000000000001','{"latitude":12.51,"longitude":78.51}',1,'Verified route correction','route-block')$$,
  '55000', 'ACTIVE_PICKUP_OR_RETURN_WORK', 'active pickup work blocks route-critical branch correction'
);
select throws_ok(
  $$select public.dastak_v1_admin_correct_merchant_branch_details('c2240000-0000-4000-8000-000000000003','{"latitude":12.61,"longitude":78.61}',1,'Verified return route correction','return-route-block')$$,
  '55000', 'ACTIVE_PICKUP_OR_RETURN_WORK', 'active return work blocks route-critical branch correction'
);
select throws_ok(
  $$select public.dastak_v1_admin_set_merchant_organization_status('c2230000-0000-4000-8000-000000000002','SUSPENDED',99,'Stale reviewed value','stale-org')$$,
  '40001', 'stale merchant organization version', 'stale expected organization version fails safely'
);

create temporary table org_suspended as select public.dastak_v1_admin_set_merchant_organization_status('c2230000-0000-4000-8000-000000000002','SUSPENDED',1,'Compliance intervention','org-suspend') body;
select is((select body ->> 'status' from org_suspended), 'SUSPENDED', 'Superadmin suspends an eligible organization');
select is((select body from org_suspended), public.dastak_v1_admin_set_merchant_organization_status('c2230000-0000-4000-8000-000000000002','SUSPENDED',1,'Compliance intervention','org-suspend'), 'identical organization command replay returns the authoritative response');
reset role;
select is((select count(*) from dastak_v1.audit_events where action = 'MERCHANT_ORGANIZATION_SUSPENDED' and resource_id = 'c2230000-0000-4000-8000-000000000002'), 1::bigint, 'idempotent replay writes one organization audit event');
select is((select is_open::text || ':' || accepting_orders::text from dastak_v1.branch_operational_states where branch_id = 'c2240000-0000-4000-8000-000000000002'), 'false:false', 'organization suspension preserves merchant-controlled open/closed state');
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_set_merchant_organization_status('c2230000-0000-4000-8000-000000000002','ACTIVE',2,'Compliance cleared','org-reactivate')$$, 'organization reactivation restores eligibility');
reset role;
select is((select is_open::text || ':' || accepting_orders::text from dastak_v1.branch_operational_states where branch_id = 'c2240000-0000-4000-8000-000000000002'), 'false:false', 'reactivation does not silently open the branch');

select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000001', true);
set local role authenticated;
create temporary table branch_suspended as select public.dastak_v1_admin_set_merchant_branch_status('c2240000-0000-4000-8000-000000000002','SUSPENDED',1,'Safety intervention','branch-suspend') body;
select is((select body ->> 'status' from branch_suspended), 'SUSPENDED', 'Superadmin suspends an eligible branch');
select is((select body from branch_suspended), public.dastak_v1_admin_set_merchant_branch_status('c2240000-0000-4000-8000-000000000002','SUSPENDED',1,'Safety intervention','branch-suspend'), 'identical branch command replay is idempotent');
select lives_ok($$select public.dastak_v1_admin_set_merchant_branch_status('c2240000-0000-4000-8000-000000000002','ACTIVE',2,'Safety cleared','branch-reactivate')$$, 'branch reactivation restores governance eligibility');
select lives_ok(
  $$select public.dastak_v1_admin_correct_merchant_branch_details('c2240000-0000-4000-8000-000000000002','{"displayName":"Governed Central","capacityLimit":12}',3,'Verified branch record','branch-correction')$$,
  'Superadmin applies a reviewed non-route correction'
);
reset role;
select is((select merchant_type::text from dastak_v1.merchant_organizations where id = 'c2230000-0000-4000-8000-000000000002'), 'RETAIL', 'branch correction cannot mutate immutable merchant type');
select is((select capacity_limit from dastak_v1.merchant_branches where id = 'c2240000-0000-4000-8000-000000000002'), 12, 'reviewed capacity correction is applied');
select is((select address_snapshot ->> 'line1' from dastak_v1.merchant_branches where id = 'c2240000-0000-4000-8000-000000000002'), '20 Market Road', 'non-route correction preserves pickup address');

select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.dastak_v1_set_operational_pause('MERCHANT_BRANCH','c2240000-0000-4000-8000-000000000002',true,'Temporary operational pause',0,'pause-existing-command')$$,
  'existing MERCHANT_BRANCH operational pause command still works'
);
reset role;
select is((select active from dastak_v1.operational_pause_controls where branch_id = 'c2240000-0000-4000-8000-000000000002'), true, 'operational pause remains distinct and active');

select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,'c2240000-0000-4000-8000-000000000003',50,null,null)$$, 'Executive Admin can read the governance projection');
select lives_ok($$select public.dastak_v1_admin_set_merchant_branch_status('c2240000-0000-4000-8000-000000000003','SUSPENDED',1,'Executive compliance intervention','exec-branch-suspend')$$, 'Executive Admin can perform a governed branch action');
reset role;

-- Resolve fixture work through normal terminal states, then prove suspension
-- leaves the append-only onboarding record and branch operations untouched.
set local session_replication_role = replica;
update dastak_v1.delivery_stops set status = 'COMPLETED', arrived_at = now(), completed_at = now(), version = version + 1 where id = 'c22b0000-0000-4000-8000-000000000001';
update dastak_v1.fulfilments set status = 'RELEASED', released_at = now(), release_reason = 'Rollback fixture resolved', version = version + 1 where id = 'c2290000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_set_merchant_organization_status('c2230000-0000-4000-8000-000000000001','SUSPENDED',1,'Active work resolved','historical-org-suspend')$$, 'organization can suspend after active work resolves');
reset role;
select is((select to_jsonb(before) from onboarding_before before), (select to_jsonb(application) from private.merchant_applications application where application.id = 'c2250000-0000-4000-8000-000000000001'), 'governance suspension does not mutate historical onboarding');
select is((select status::text from dastak_v1.orders where id = 'c2260000-0000-4000-8000-000000000001'), 'MATCHING', 'governance actions do not mutate order state');
select is((select is_open::text || ':' || accepting_orders::text from dastak_v1.branch_operational_states where branch_id = 'c2240000-0000-4000-8000-000000000001'), 'true:true', 'organization suspension does not mutate merchant operational state');

-- Existing active work may finish under suspension, but a new commitment is
-- rejected by the serialized governance guard.
set local session_replication_role = replica;
insert into dastak_v1.orders (id, display_order_number, customer_id, order_type, status, submitted_at) values ('c2260000-0000-4000-8000-000000000002', 'DSK-C22-0002', 'c2200000-0000-4000-8000-000000000010', 'RETAIL_ONLY', 'MATCHING', now());
insert into dastak_v1.matching_attempts (id, order_id, wave, status, started_at, expires_at) values ('c2270000-0000-4000-8000-000000000002', 'c2260000-0000-4000-8000-000000000002', 'WAVE_1', 'OPEN', now(), now() + interval '15 minutes');
insert into dastak_v1.merchant_opportunities (id, matching_attempt_id, order_id, organization_id, branch_id, status, started_at, expires_at, promised_prep_minutes, responded_by, responded_at, wave) values ('c2280000-0000-4000-8000-000000000002', 'c2270000-0000-4000-8000-000000000002', 'c2260000-0000-4000-8000-000000000002', 'c2230000-0000-4000-8000-000000000001', 'c2240000-0000-4000-8000-000000000001', 'SELECTED', now(), now() + interval '15 minutes', 10, 'c2200000-0000-4000-8000-000000000008', now(), 'WAVE_1');
set local session_replication_role = origin;
select throws_ok(
  $$insert into dastak_v1.fulfilments (id, order_id, organization_id, branch_id, source_opportunity_id, fulfilment_type, status, promised_prep_minutes, committed_at, prep_started_at) values ('c2290000-0000-4000-8000-000000000002','c2260000-0000-4000-8000-000000000002','c2230000-0000-4000-8000-000000000001','c2240000-0000-4000-8000-000000000001','c2280000-0000-4000-8000-000000000002','RETAIL','PREPARING',10,now(),now())$$,
  '55000', 'merchant governance status does not permit new fulfilments', 'suspended organization cannot acquire new fulfilment work'
);

-- Exact negative authorization matrix.
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000003', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'platform permission required', 'trace-only actor is denied'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000004', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'platform permission required', 'recovery-only actor is denied'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000005', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'platform permission required', 'finance-only actor is denied'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000006', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'platform permission required', 'catalogue-only actor is denied'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000007', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'active Admin assignment required', 'inactive Admin assignment is denied despite permission'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000008', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_set_merchant_branch_status('c2240000-0000-4000-8000-000000000002','SUSPENDED',4,'Merchant self escalation','merchant-denied')$$, '42501', 'platform permission required', 'Merchant actor cannot govern itself'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000009', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'platform permission required', 'rider actor is denied'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000010', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'platform permission required', 'customer actor is denied'); reset role;
select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000011', true); set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'platform permission required', 'ordinary authenticated actor is denied');
select throws_ok($$select dastak_v1_api.admin_merchant_governance_page('c2200000-0000-4000-8000-000000000001',null,null,null,50,null,null)$$, '42501', 'authentication required', 'caller cannot spoof a privileged actor through the internal projection'); reset role;
select set_config('request.jwt.claim.sub', '', true); set local role anon;
select throws_ok($$select public.dastak_v1_admin_merchant_governance_page(null,null,null,50,null,null)$$, '42501', 'permission denied for function dastak_v1_admin_merchant_governance_page', 'unauthenticated actor is denied at function boundary'); reset role;

select set_config('request.jwt.claim.sub', 'c2200000-0000-4000-8000-000000000001', true); set local role authenticated;
create temporary table correction_history as
select public.dastak_v1_admin_audit_history_page(null,null,null,'MERCHANT_BRANCH_DETAILS_CORRECTED',null,null,null,null,null,null,20,null,null) body;
reset role;
select is(
  (select body #>> '{events,0,summary,outcome}' from correction_history),
  'Changed: displayName, capacityLimit',
  'branch correction is immediately represented with reviewed changed fields in Audit History'
);
select is(
  (select count(distinct action) from dastak_v1.audit_events where action = any(array['MERCHANT_ORGANIZATION_SUSPENDED','MERCHANT_ORGANIZATION_REACTIVATED','MERCHANT_BRANCH_SUSPENDED','MERCHANT_BRANCH_REACTIVATED','MERCHANT_BRANCH_DETAILS_CORRECTED'])),
  5::bigint,
  'all five governed Merchant action names are append-only audited'
);

select * from finish();
rollback;
