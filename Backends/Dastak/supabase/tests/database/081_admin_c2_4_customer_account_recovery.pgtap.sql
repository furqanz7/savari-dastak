begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (select pg_catalog.array_agg(bundle.bundle_key order by bundle.bundle_key)
   from dastak_v1.permission_bundle_permissions permission
   join dastak_v1.permission_bundles bundle on bundle.id = permission.bundle_id
   where permission.permission_key = 'platform.accounts.recover'),
  array['executive_admin', 'platform_super_admin']::text[],
  'Customer recovery remains limited to Superadmin and Executive Admin'
);
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.assert_customer_recovery_admin(uuid)'::regprocedure),
  'platform\.accounts\.recover',
  'Customer recovery requires its dedicated permission'
);
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.assert_customer_recovery_admin(uuid)'::regprocedure),
  'admin_role_for_actor\(p_actor_id\)',
  'Customer recovery also requires an active Admin assignment'
);
select is(has_function_privilege('anon', 'public.dastak_v1_admin_customer_recovery_page(text,uuid,integer,timestamptz,uuid)', 'EXECUTE'), false, 'anonymous cannot execute Customer recovery');
select is(has_table_privilege('authenticated', 'private.revoked_account_sessions', 'INSERT'), false, 'clients cannot revoke session records directly');
select is(has_table_privilege('authenticated', 'private.account_phone_claims', 'UPDATE'), false, 'clients cannot move phone claims directly');
select matches(
  pg_catalog.pg_get_functiondef('dastak_v1_api.admin_correct_customer_phone(uuid,uuid,text,text,bigint,text,text)'::regprocedure),
  'least\(v_current, v_replacement\).*greatest\(v_current, v_replacement\)',
  'phone corrections deterministically order old/new phone advisory locks'
);
select matches(
  pg_catalog.pg_get_functiondef('public.dastak_custom_access_token(jsonb)'::regprocedure),
  'assert_dastak_session_active\(v_account_id, v_session_id\)',
  'Auth token issuance and refresh still enforce the shared Dastak session revocation boundary'
);
select is(
  has_function_privilege('service_role', 'public.revoke_account_session(uuid,uuid,uuid)', 'EXECUTE'),
  true,
  'existing customer self-service session revocation remains available through its privileged boundary'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c2400000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c24-super@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c24-executive@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c24-trace@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c24-recovery@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c24-finance@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c24-catalogue@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c24-inactive@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000008', '00000000-0000-0000-8000-000000000000', 'authenticated', 'authenticated', 'c24-customer@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2400000-0000-4000-8000-000000000009', '00000000-0000-0000-8000-000000000000', 'authenticated', 'authenticated', 'c24-other@example.test', '', now(), '{}', '{}', now(), now());

insert into public.accounts (id, display_name, phone_number, account_state) values
  ('c2400000-0000-4000-8000-000000000001', 'C24 Superadmin', '+919740000001', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000002', 'C24 Executive', '+919740000002', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000003', 'C24 Trace', '+919740000003', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000004', 'C24 Recovery', '+919740000004', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000005', 'C24 Finance', '+919740000005', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000006', 'C24 Catalogue', '+919740000006', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000007', 'C24 Inactive Admin', '+919740000007', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000008', 'C24 Customer', '+919740000008', 'ACTIVE'),
  ('c2400000-0000-4000-8000-000000000009', 'C24 Other Customer', '+919740000009', 'ACTIVE');

insert into private.account_memberships (account_id, role, approved_at) values
  ('c2400000-0000-4000-8000-000000000001', 'customer', null),
  ('c2400000-0000-4000-8000-000000000002', 'customer', null),
  ('c2400000-0000-4000-8000-000000000003', 'customer', null),
  ('c2400000-0000-4000-8000-000000000004', 'customer', null),
  ('c2400000-0000-4000-8000-000000000005', 'customer', null),
  ('c2400000-0000-4000-8000-000000000006', 'customer', null),
  ('c2400000-0000-4000-8000-000000000007', 'owner', now()),
  ('c2400000-0000-4000-8000-000000000008', 'customer', null),
  ('c2400000-0000-4000-8000-000000000009', 'customer', null);

insert into private.account_personas (account_id, persona) values
  ('c2400000-0000-4000-8000-000000000008', 'CUSTOMER'),
  ('c2400000-0000-4000-8000-000000000009', 'CUSTOMER')
on conflict (account_id, persona) do nothing;
insert into private.account_phone_claims (
  phone_number, account_id, claim_state, verification_source, version
) values
  ('+919740000008', 'c2400000-0000-4000-8000-000000000008', 'ACTIVE', 'PROFILE_ENTRY', 1),
  ('+919740000009', 'c2400000-0000-4000-8000-000000000009', 'ACTIVE', 'PROFILE_ENTRY', 1);

insert into dastak_v1.permission_bundles (id, bundle_key, display_name, scope, description) values
  ('c2410000-0000-4000-8000-000000000001', 'c24_trace_only', 'C2.4 trace only', 'PLATFORM', 'Rollback-only trace fixture');
insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key) values
  ('c2410000-0000-4000-8000-000000000001', 'platform.orders.trace');

select lives_ok($$select dastak_v1_api.bootstrap_superadmin('c2400000-0000-4000-8000-000000000001')$$, 'rollback fixture establishes Superadmin');
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_set_executive_admin(1::smallint, 'c24-executive@example.test', 1::bigint, 'Bind Customer recovery test seat.')$$, 'rollback fixture establishes Executive Admin');
reset role;

insert into dastak_v1.platform_permission_grants (account_id, bundle_id, granted_by, grant_reason)
select fixture.account_id, bundle.id, 'c2400000-0000-4000-8000-000000000001', 'C2.4 negative authorization fixture'
from (values
  ('c2400000-0000-4000-8000-000000000003'::uuid, 'c24_trace_only'),
  ('c2400000-0000-4000-8000-000000000004'::uuid, 'recovery_operations'),
  ('c2400000-0000-4000-8000-000000000005'::uuid, 'finance_operations'),
  ('c2400000-0000-4000-8000-000000000006'::uuid, 'catalogue_admin'),
  ('c2400000-0000-4000-8000-000000000007'::uuid, 'executive_admin')
) fixture(account_id, bundle_key)
join dastak_v1.permission_bundles bundle on bundle.bundle_key = fixture.bundle_key;

insert into auth.sessions (id, user_id, created_at, updated_at, refreshed_at, user_agent) values
  ('c2420000-0000-4000-8000-000000000001', 'c2400000-0000-4000-8000-000000000008', now() - interval '2 days', now() - interval '1 minute', (now() - interval '1 minute')::timestamp, 'secret browser details'),
  ('c2420000-0000-4000-8000-000000000002', 'c2400000-0000-4000-8000-000000000008', now() - interval '1 day', now() - interval '2 minutes', (now() - interval '2 minutes')::timestamp, 'secret device details');
insert into private.account_sessions (session_id, account_id, device_name, platform, app_name, user_agent, created_at, last_seen_at) values
  ('c2420000-0000-4000-8000-000000000001', 'c2400000-0000-4000-8000-000000000008', 'Reviewed iPhone', 'ios', 'Dastak', 'must never project', now() - interval '2 days', now() - interval '1 minute'),
  ('c2420000-0000-4000-8000-000000000002', 'c2400000-0000-4000-8000-000000000008', 'Reviewed Safari', 'web', 'Dastak Customer Web', 'must never project', now() - interval '1 day', now() - interval '2 minutes');

select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,50,null,null)$$, 'Superadmin can read Customer recovery');
select is(
  public.dastak_v1_admin_customer_recovery_page(null,'c2400000-0000-4000-8000-000000000008',10,null,null) #>> '{customers,0,activeSessionCount}',
  '2', 'projection includes every authoritative active session'
);
select is(
  (public.dastak_v1_admin_customer_recovery_page(null,'c2400000-0000-4000-8000-000000000008',10,null,null) #> '{customers,0,sessions,0}') ? 'userAgent',
  false, 'projection excludes raw user-agent/Auth metadata'
);
create temporary table c24_single as
select public.dastak_v1_admin_revoke_customer_sessions(
  'c2400000-0000-4000-8000-000000000008', 'SINGLE',
  'c2420000-0000-4000-8000-000000000001',
  'Customer-reported lost device', 'c24-single-revoke'
) body;
select is((select body #>> '{revokedSessionCount}' from c24_single), '1', 'single-session revocation revokes exactly one reviewed session');
select is((select body #>> '{activeSessionCount}' from c24_single), '1', 'single-session revocation preserves the other session');
select is((select body from c24_single), public.dastak_v1_admin_revoke_customer_sessions(
  'c2400000-0000-4000-8000-000000000008', 'SINGLE',
  'c2420000-0000-4000-8000-000000000001',
  'Customer-reported lost device', 'c24-single-revoke'
), 'identical session-revocation replay is idempotent');
reset role;
select is(
  (select pg_catalog.count(*) from private.revoked_account_sessions where account_id='c2400000-0000-4000-8000-000000000008'),
  1::bigint, 'single-session revocation does not affect another reviewed session'
);
select is(
  (select pg_catalog.count(*) from private.customer_active_session_projection('c2400000-0000-4000-8000-000000000008')),
  1::bigint, 'authoritative session projection retains the unreviewed session'
);
select throws_ok(
  $$select private.assert_dastak_session_active('c2400000-0000-4000-8000-000000000008','c2420000-0000-4000-8000-000000000001')$$,
  '28000', 'This Dastak session has been revoked.',
  'a revoked reviewed session cannot receive another Dastak token on refresh'
);
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000001', true);
set local role authenticated;
create temporary table c24_all as
select public.dastak_v1_admin_revoke_customer_sessions(
  'c2400000-0000-4000-8000-000000000008', 'ALL', null,
  'Suspected account compromise', 'c24-all-revoke'
) body;
select is((select body #>> '{revokedSessionCount}' from c24_all), '1', 'revoke-all monotonically revokes all sessions active at execution time');
select is((select body #>> '{activeSessionCount}' from c24_all), '0', 'revoke-all leaves no authoritative active session');
select throws_ok(
  $$select public.dastak_v1_admin_correct_customer_phone('c2400000-0000-4000-8000-000000000008','+919740000008','+919740000010',99,'Customer request','c24-stale-phone')$$,
  '40001', 'stale Customer phone claim version', 'stale phone-claim versions fail safely'
);
select throws_ok(
  $$select public.dastak_v1_admin_correct_customer_phone('c2400000-0000-4000-8000-000000000008','+919740000008','+919740000009',1,'Customer request','c24-duplicate-phone')$$,
  '23505', 'PHONE_NUMBER_ALREADY_CLAIMED', 'a phone claimed by another Dastak identity is rejected'
);
create temporary table c24_phone as
select public.dastak_v1_admin_correct_customer_phone(
  'c2400000-0000-4000-8000-000000000008','+919740000008','+919740000010',1,
  'Customer request — reviewed correction','c24-phone-correction'
) body;
select is((select body #>> '{phoneClaimVersion}' from c24_phone), '2', 'phone correction advances the phone-claim version');
select is((select body from c24_phone), public.dastak_v1_admin_correct_customer_phone(
  'c2400000-0000-4000-8000-000000000008','+919740000008','+919740000010',1,
  'Customer request — reviewed correction','c24-phone-correction'
), 'identical phone-correction replay is idempotent');
reset role;

select is((select phone_number from public.accounts where id='c2400000-0000-4000-8000-000000000008'), '+919740000010', 'phone correction updates Dastak contact data');
select is((select version from private.account_phone_claims where account_id='c2400000-0000-4000-8000-000000000008'), 2::bigint, 'phone claim advances atomically');
select is((select email from auth.users where id='c2400000-0000-4000-8000-000000000008'), 'c24-customer@example.test', 'OAuth/email identity remains unchanged');
select is((select phone from auth.users where id='c2400000-0000-4000-8000-000000000008'), null, 'Admin contact correction does not create an Auth phone identity');
select is((select pg_catalog.count(*) from dastak_v1.audit_events where action='ADMIN_ACCOUNT_SESSIONS_REVOKED' and resource_id='c2400000-0000-4000-8000-000000000008'), 2::bigint, 'session operations create one audit event per logical operation');
select is((select pg_catalog.count(*) from dastak_v1.audit_events where action='ADMIN_ACCOUNT_PHONE_CORRECTED' and resource_id='c2400000-0000-4000-8000-000000000008'), 1::bigint, 'phone correction creates one audit event');
select is(
  (select metadata ->> 'fromStatus' from dastak_v1.audit_events where action='ADMIN_ACCOUNT_PHONE_CORRECTED' and resource_id='c2400000-0000-4000-8000-000000000008'),
  '••••••••• 0008', 'phone audit stores only a masked prior phone'
);
select is(
  (select metadata ->> 'toStatus' from dastak_v1.audit_events where action='ADMIN_ACCOUNT_PHONE_CORRECTED' and resource_id='c2400000-0000-4000-8000-000000000008'),
  '••••••••• 0010', 'phone audit stores only a masked replacement phone'
);
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  public.dastak_v1_admin_audit_history_page(
    null,null,null,'ADMIN_ACCOUNT_PHONE_CORRECTED',null,null,null,null,
    'c2400000-0000-4000-8000-000000000008',null,10,null,null
  ) #>> '{events,0,summary,toStatus}',
  '••••••••• 0010',
  'Customer recovery audit is immediately visible through the governed Audit History projection'
);
select is(
  pg_catalog.strpos(
    public.dastak_v1_admin_audit_history_page(
      null,null,null,'ADMIN_ACCOUNT_PHONE_CORRECTED',null,null,null,null,
      'c2400000-0000-4000-8000-000000000008',null,10,null,null
    )::text,
    '+919740000010'
  ),
  0,
  'Audit History never exposes the full corrected phone number'
);
reset role;

select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, 'Executive Admin can read Customer recovery');
reset role;

select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, '42501', 'platform permission required', 'trace-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, '42501', 'platform permission required', 'recovery-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000005', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, '42501', 'platform permission required', 'finance-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000006', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, '42501', 'platform permission required', 'catalogue-only actor is denied');
reset role;
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000007', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, '42501', 'active Admin assignment required', 'inactive Admin assignment is denied despite permission grant');
reset role;
select set_config('request.jwt.claim.sub', 'c2400000-0000-4000-8000-000000000008', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, '42501', 'platform permission required', 'Customer and ordinary authenticated actors are denied');
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_customer_recovery_page(null,null,10,null,null)$$, '42501', 'authentication required', 'authenticated role without a subject is denied');
reset role;

select * from finish();
rollback;
