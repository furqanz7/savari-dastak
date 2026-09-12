begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (select pg_catalog.array_agg(bundle.bundle_key order by bundle.bundle_key)
   from dastak_v1.permission_bundle_permissions permission
   join dastak_v1.permission_bundles bundle on bundle.id = permission.bundle_id
   where permission.permission_key = 'platform.delivery_partners.manage'),
  array['executive_admin', 'platform_super_admin']::text[],
  'Delivery Partner governance belongs only to Superadmin and Executive Admin'
);
select has_column('private', 'delivery_partner_profiles', 'governance_version', 'rider governance has an independent concurrency version');
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.assert_delivery_partner_governance_admin(uuid)'::regprocedure),
  'platform\.delivery_partners\.manage',
  'the governance projection requires the dedicated permission'
);
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.assert_delivery_partner_governance_admin(uuid)'::regprocedure),
  'admin_role_for_actor\(p_actor_id\)',
  'the governance projection also requires an active Admin assignment'
);
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.set_delivery_partner_governance_status(uuid,uuid,text,bigint,text,text)'::regprocedure),
  'lock_delivery_partner_active_work\(p_rider_id\)',
  'governance mutation acquires the existing rider-scoped lock'
);
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.set_delivery_partner_governance_status(uuid,uuid,text,bigint,text,text)'::regprocedure),
  'delivery_partner_active_work\(p_rider_id\)',
  'suspension evaluates the existing global active-work predicate'
);
select matches(
  pg_catalog.pg_get_functiondef('private.delivery_partner_active_work(uuid,text,uuid,uuid)'::regprocedure),
  'DASTAK_V1.*RETURN.*LEGACY_COURIER.*PARCEL',
  'the reused predicate covers V1, return, legacy courier and parcel work'
);
select is(has_function_privilege('anon', 'public.dastak_v1_admin_delivery_partner_governance_page(text,uuid,text,integer,timestamptz,uuid)', 'EXECUTE'), false, 'anonymous cannot execute rider governance');
select is(has_function_privilege('authenticated', 'dastak_v1_api.set_delivery_partner_governance_status(uuid,uuid,text,bigint,text,text)', 'EXECUTE'), true, 'authenticated Edge callers reach the internal authorization boundary');
select is(has_table_privilege('authenticated', 'private.delivery_partner_profiles', 'UPDATE'), false, 'clients cannot mutate rider governance directly');
select matches(
  pg_catalog.pg_get_functiondef('private.enforce_delivery_partner_governance_availability()'::regprocedure),
  'pg_try_advisory_xact_lock.*dastak:delivery-partner-active-work:',
  'online availability fails closed on the same rider lock without a row-lock deadlock'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c2300000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-super@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-executive@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-trace@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-recovery@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-finance@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-catalogue@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-inactive@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000008', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-rider@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000009', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-customer@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2300000-0000-4000-8000-000000000010', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c23-active-rider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.accounts (id, display_name, phone_number, account_state) values
  ('c2300000-0000-4000-8000-000000000001', 'C23 Superadmin', '+919730000001', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000002', 'C23 Executive', '+919730000002', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000003', 'C23 Trace', '+919730000003', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000004', 'C23 Recovery', '+919730000004', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000005', 'C23 Finance', '+919730000005', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000006', 'C23 Catalogue', '+919730000006', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000007', 'C23 Inactive Admin', '+919730000007', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000008', 'C23 Governed Rider', '+919730000008', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000009', 'C23 Customer', '+919730000009', 'ACTIVE'),
  ('c2300000-0000-4000-8000-000000000010', 'C23 Active Rider', '+919730000010', 'ACTIVE');

insert into private.account_memberships (account_id, role, approved_at) values
  ('c2300000-0000-4000-8000-000000000001', 'customer', null),
  ('c2300000-0000-4000-8000-000000000002', 'customer', null),
  ('c2300000-0000-4000-8000-000000000003', 'customer', null),
  ('c2300000-0000-4000-8000-000000000004', 'customer', null),
  ('c2300000-0000-4000-8000-000000000005', 'customer', null),
  ('c2300000-0000-4000-8000-000000000006', 'customer', null),
  ('c2300000-0000-4000-8000-000000000007', 'owner', now()),
  ('c2300000-0000-4000-8000-000000000008', 'dastak_partner', now()),
  ('c2300000-0000-4000-8000-000000000009', 'customer', null),
  ('c2300000-0000-4000-8000-000000000010', 'dastak_partner', now());

insert into dastak_v1.permission_bundles (id, bundle_key, display_name, scope, description) values
  ('c2310000-0000-4000-8000-000000000001', 'c23_trace_only', 'C2.3 trace only', 'PLATFORM', 'Rollback-only trace fixture');
insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key) values
  ('c2310000-0000-4000-8000-000000000001', 'platform.orders.trace');

select lives_ok($$select dastak_v1_api.bootstrap_superadmin('c2300000-0000-4000-8000-000000000001')$$, 'rollback fixture establishes Superadmin');
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_set_executive_admin(1::smallint, 'c23-executive@example.test', 1::bigint, 'Bind rider governance test seat.')$$, 'rollback fixture establishes Executive Admin');
reset role;

insert into dastak_v1.platform_permission_grants (account_id, bundle_id, granted_by, grant_reason)
select fixture.account_id, bundle.id, 'c2300000-0000-4000-8000-000000000001', 'C2.3 negative authorization fixture'
from (values
  ('c2300000-0000-4000-8000-000000000003'::uuid, 'c23_trace_only'),
  ('c2300000-0000-4000-8000-000000000004'::uuid, 'recovery_operations'),
  ('c2300000-0000-4000-8000-000000000005'::uuid, 'finance_operations'),
  ('c2300000-0000-4000-8000-000000000006'::uuid, 'catalogue_admin'),
  ('c2300000-0000-4000-8000-000000000007'::uuid, 'executive_admin')
) fixture(account_id, bundle_key)
join dastak_v1.permission_bundles bundle on bundle.bundle_key = fixture.bundle_key;

insert into public.service_zones (id, name, boundary, active) values (
  'c2320000-0000-4000-8000-000000000001', 'C2.3 Test Zone',
  extensions.st_geomfromtext('POLYGON((78 12,79 12,79 13,78 13,78 12))', 4326), true
);
insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  status, reviewed_at, reviewed_by, review_reason
) values
  ('c2330000-0000-4000-8000-000000000001', 'c2300000-0000-4000-8000-000000000008', 'bicycle', 'dastak-partner/c2300000-0000-4000-8000-000000000008/identity.pdf', 'approved', now(), 'c2300000-0000-4000-8000-000000000001', 'Verified rollback fixture'),
  ('c2330000-0000-4000-8000-000000000002', 'c2300000-0000-4000-8000-000000000010', 'bicycle', 'dastak-partner/c2300000-0000-4000-8000-000000000010/identity.pdf', 'approved', now(), 'c2300000-0000-4000-8000-000000000001', 'Verified active-work fixture');
insert into private.delivery_partner_profiles (account_id, approved_application_id, delivery_method) values
  ('c2300000-0000-4000-8000-000000000008', 'c2330000-0000-4000-8000-000000000001', 'bicycle'),
  ('c2300000-0000-4000-8000-000000000010', 'c2330000-0000-4000-8000-000000000002', 'bicycle');
insert into private.delivery_partner_availability (account_id, status, location, service_zone_id, last_seen_at, available_until) values
  ('c2300000-0000-4000-8000-000000000008', 'online', extensions.st_setsrid(extensions.st_makepoint(78.5,12.5),4326), 'c2320000-0000-4000-8000-000000000001', now(), now() + interval '15 minutes'),
  ('c2300000-0000-4000-8000-000000000010', 'online', extensions.st_setsrid(extensions.st_makepoint(78.5,12.5),4326), 'c2320000-0000-4000-8000-000000000001', now(), now() + interval '15 minutes');

-- One real V1 assignment proves the command consults active custody at runtime.
set local session_replication_role = replica;
insert into dastak_v1.orders (id, display_order_number, customer_id, order_type, status, submitted_at) values
  ('c2340000-0000-4000-8000-000000000001', 'DSK-C23-0001', 'c2300000-0000-4000-8000-000000000009', 'RETAIL_ONLY', 'MATCHING', now());
insert into dastak_v1.delivery_missions (
  id, order_id, status, assigned_rider_id, assigned_transport_type, assigned_at,
  transport_snapshot, pickup_count, delivery_distance_meters,
  rider_payout_quote_paise, rider_payout_quote_snapshot
) values (
  'c2350000-0000-4000-8000-000000000001', 'c2340000-0000-4000-8000-000000000001',
  'ASSIGNED', 'c2300000-0000-4000-8000-000000000010', 'BICYCLE', now(), '{}', 1, 100, 1000, '{}'
);
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,50,null,null)$$, 'Superadmin can read Delivery Partner governance');
select is(
  public.dastak_v1_admin_delivery_partner_governance_page(null,'c2300000-0000-4000-8000-000000000010',null,50,null,null) #>> '{deliveryPartners,0,activeWork,domain}',
  'DASTAK_V1', 'the governance projection exposes the safe active-work domain'
);
select throws_ok(
  $$select public.dastak_v1_admin_set_delivery_partner_status('c2300000-0000-4000-8000-000000000010','SUSPENDED',1,'Safety review','active-work-block')$$,
  '55000', 'RIDER_ACTIVE_WORK_REQUIRES_RELEASE', 'V1 active work blocks suspension'
);
select throws_ok(
  $$select public.dastak_v1_admin_set_delivery_partner_status('c2300000-0000-4000-8000-000000000008','SUSPENDED',99,'Stale review','stale-rider')$$,
  '40001', 'stale Delivery Partner governance version', 'stale governance version fails safely'
);
create temporary table c23_suspended as
select public.dastak_v1_admin_set_delivery_partner_status(
  'c2300000-0000-4000-8000-000000000008','SUSPENDED',1,
  'Safety review — verified incident','c23-suspend'
) body;
select is((select body ->> 'status' from c23_suspended), 'SUSPENDED', 'Superadmin suspends an eligible rider');
select is((select body from c23_suspended), public.dastak_v1_admin_set_delivery_partner_status(
  'c2300000-0000-4000-8000-000000000008','SUSPENDED',1,
  'Safety review — verified incident','c23-suspend'
), 'identical suspension replay is idempotent');
reset role;

select is((select status from private.delivery_partner_availability where account_id='c2300000-0000-4000-8000-000000000008'), 'offline', 'suspension forces availability offline');
select is((select available_until is null from private.delivery_partner_availability where account_id='c2300000-0000-4000-8000-000000000008'), true, 'suspension clears availability expiry');
select is((select status from private.delivery_partner_applications where id='c2330000-0000-4000-8000-000000000001'), 'approved', 'suspension preserves the approved application and evidence record');

select throws_ok(
  $$update private.delivery_partner_availability set status='online', available_until=now() + interval '15 minutes' where account_id='c2300000-0000-4000-8000-000000000008'$$,
  'P0001', 'RIDER_GOVERNANCE_SUSPENDED', 'a suspended rider cannot become available'
);

select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
create temporary table c23_reactivated as
select public.dastak_v1_admin_set_delivery_partner_status(
  'c2300000-0000-4000-8000-000000000008','ACTIVE',2,
  'Safety review — cleared','c23-reactivate'
) body;
select is((select body ->> 'status' from c23_reactivated), 'ACTIVE', 'Superadmin reactivates a rider');
reset role;
select is((select status from private.delivery_partner_availability where account_id='c2300000-0000-4000-8000-000000000008'), 'offline', 'reactivation does not silently make the rider online');
select is((select pg_catalog.count(*) from dastak_v1.audit_events where action='DELIVERY_PARTNER_SUSPENDED' and resource_id='c2300000-0000-4000-8000-000000000008'), 1::bigint, 'suspension creates one reviewed audit event');
select is((select pg_catalog.count(*) from dastak_v1.audit_events where action='DELIVERY_PARTNER_REACTIVATED' and resource_id='c2300000-0000-4000-8000-000000000008'), 1::bigint, 'reactivation creates one reviewed audit event');
select is(
  (select (metadata ->> 'transportMethod') || ':' || (metadata ->> 'fromStatus') || ':' || (metadata ->> 'toStatus')
     || ':' || (metadata ->> 'fromVersion') || ':' || (metadata ->> 'version') || ':' || (metadata ->> 'reason')
   from dastak_v1.audit_events
   where action='DELIVERY_PARTNER_SUSPENDED' and resource_id='c2300000-0000-4000-8000-000000000008'),
  'bicycle:ACTIVE:SUSPENDED:1:2:Safety review — verified incident',
  'the append-only audit record retains transport, status/version transition and operator reason'
);
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  public.dastak_v1_admin_audit_history_page(
    null, null, null, 'DELIVERY_PARTNER_SUSPENDED', null,
    'c2300000-0000-4000-8000-000000000008', null, null,
    'c2300000-0000-4000-8000-000000000008', null, 10, null, null
  ) #>> '{events,0,summary,outcome}',
  'governance version 1 -> 2',
  'the existing safe Audit History projection immediately exposes the governance version transition'
);
reset role;

select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, 'Executive Admin can read rider governance');
reset role;

-- Dedicated permission alone or unrelated bundles never confer an active Admin assignment.
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, '42501', 'platform permission required', 'trace-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, '42501', 'platform permission required', 'recovery-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000005', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, '42501', 'platform permission required', 'finance-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000006', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, '42501', 'platform permission required', 'catalogue-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000007', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, '42501', 'active Admin assignment required', 'inactive Admin assignment is denied despite permission grant');
reset role;
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000008', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, '42501', 'platform permission required', 'Delivery Partner actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000009', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_delivery_partner_governance_page(null,null,null,10,null,null)$$, '42501', 'platform permission required', 'customer actor is denied');
reset role;

-- Defence-in-depth is installed on every acquisition domain and uses one guard.
select is((select count(*) from pg_catalog.pg_trigger where not tgisinternal and tgfoid='private.enforce_delivery_partner_governance_assignment()'::regprocedure and tgname in (
  'aaa_delivery_missions_rider_governance','aaa_return_missions_rider_governance',
  'aaa_legacy_assignments_rider_governance','aaa_parcel_assignments_rider_governance'
)), 4::bigint, 'all four assignment domains share the governance acquisition guard');
select matches(pg_catalog.pg_get_functiondef('private.enforce_delivery_partner_governance_assignment()'::regprocedure), 'return_missions.*delivery_assignment_attempts.*parcel_assignment_attempts', 'return, legacy and parcel acquisition branches are guarded');
select is((select count(*) from dastak_v1.delivery_missions where id='c2350000-0000-4000-8000-000000000001'), 1::bigint, 'failed governance suspension preserves the active historical mission');

select * from finish();
rollback;
