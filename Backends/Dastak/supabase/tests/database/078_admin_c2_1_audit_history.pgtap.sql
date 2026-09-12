begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (select pg_catalog.array_agg(definition.permission_key order by definition.permission_key)
   from dastak_v1.permission_definitions definition
   where definition.permission_key = any (array[
     'platform.merchants.manage', 'platform.delivery_partners.manage',
     'platform.accounts.recover', 'platform.audit.read',
     'platform.catalogue.assets.manage'
   ]::text[])),
  array[
    'platform.accounts.recover', 'platform.audit.read',
    'platform.catalogue.assets.manage', 'platform.delivery_partners.manage',
    'platform.merchants.manage'
  ]::text[],
  'all five dedicated C2 governance permissions exist'
);

select is(
  (select pg_catalog.array_agg(bundle.bundle_key order by bundle.bundle_key)
   from dastak_v1.permission_bundle_permissions grant_row
   join dastak_v1.permission_bundles bundle on bundle.id = grant_row.bundle_id
   where grant_row.permission_key = 'platform.audit.read'),
  array['executive_admin', 'platform_super_admin']::text[],
  'Audit History is granted only to Superadmin and Executive Admin'
);

select is(
  (select pg_catalog.array_agg(bundle.bundle_key order by bundle.bundle_key)
   from dastak_v1.permission_bundle_permissions grant_row
   join dastak_v1.permission_bundles bundle on bundle.id = grant_row.bundle_id
   where grant_row.permission_key = 'platform.catalogue.assets.manage'),
  array['catalogue_admin', 'executive_admin', 'platform_super_admin']::text[],
  'catalogue asset governance additionally belongs to catalogue_admin'
);

select ok(
  not exists (
    select 1
    from dastak_v1.permission_bundle_permissions grant_row
    join dastak_v1.permission_bundles bundle on bundle.id = grant_row.bundle_id
    where grant_row.permission_key = any (array[
      'platform.merchants.manage', 'platform.delivery_partners.manage',
      'platform.accounts.recover', 'platform.audit.read'
    ]::text[])
      and bundle.bundle_key not in ('platform_super_admin', 'executive_admin')
  ),
  'governance and audit permissions do not leak to operational bundles'
);

select is(has_function_privilege(
  'anon',
  'public.dastak_v1_admin_audit_history_page(timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text)',
  'EXECUTE'
), false, 'anonymous actors cannot execute Audit History');

select is(has_function_privilege(
  'authenticated',
  'public.dastak_v1_admin_audit_history_page(timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text)',
  'EXECUTE'
), true, 'authenticated callers can reach the caller-bound permission check');

select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.admin_audit_history_page(uuid,timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text)'::regprocedure
  ),
  'platform\.audit\.read',
  'the installed projection requires platform.audit.read'
);

select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.admin_audit_history_page(uuid,timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text)'::regprocedure
  ),
  'admin_role_for_actor\(p_actor_id\)',
  'the installed projection independently requires an active Admin assignment'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c2100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-super@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('c2100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-executive@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('c2100000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-trace@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('c2100000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-recovery@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('c2100000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-finance@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('c2100000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-catalogue@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('c2100000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-inactive@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('c2100000-0000-4000-8000-000000000008', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c21-user@example.test', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb, pg_catalog.now(), pg_catalog.now());

insert into public.accounts (id, display_name, phone_number, account_state) values
  ('c2100000-0000-4000-8000-000000000001', 'C21 Superadmin', '+919700000001', 'ACTIVE'),
  ('c2100000-0000-4000-8000-000000000002', 'C21 Executive', '+919700000002', 'ACTIVE'),
  ('c2100000-0000-4000-8000-000000000003', 'C21 Trace', '+919700000003', 'ACTIVE'),
  ('c2100000-0000-4000-8000-000000000004', 'C21 Recovery', '+919700000004', 'ACTIVE'),
  ('c2100000-0000-4000-8000-000000000005', 'C21 Finance', '+919700000005', 'ACTIVE'),
  ('c2100000-0000-4000-8000-000000000006', 'C21 Catalogue', '+919700000006', 'ACTIVE'),
  ('c2100000-0000-4000-8000-000000000007', 'C21 Inactive Admin', '+919700000007', 'ACTIVE'),
  ('c2100000-0000-4000-8000-000000000008', 'C21 User', '+919700000008', 'ACTIVE');

insert into private.account_memberships (account_id, role) values
  ('c2100000-0000-4000-8000-000000000001', 'customer'),
  ('c2100000-0000-4000-8000-000000000002', 'customer'),
  ('c2100000-0000-4000-8000-000000000003', 'customer'),
  ('c2100000-0000-4000-8000-000000000004', 'customer'),
  ('c2100000-0000-4000-8000-000000000005', 'customer'),
  ('c2100000-0000-4000-8000-000000000006', 'customer'),
  ('c2100000-0000-4000-8000-000000000007', 'owner'),
  ('c2100000-0000-4000-8000-000000000008', 'customer');

update private.account_memberships
set approved_at = pg_catalog.now(), suspended_until = null
where account_id = 'c2100000-0000-4000-8000-000000000007'
  and role = 'owner';

insert into dastak_v1.permission_bundles (id, bundle_key, display_name, scope, description) values
  ('c2110000-0000-4000-8000-000000000001', 'c21_trace_only', 'C2.1 trace only', 'PLATFORM', 'Rollback-only order tracing fixture');
insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key) values
  ('c2110000-0000-4000-8000-000000000001', 'platform.orders.trace');

select lives_ok(
  $$select dastak_v1_api.bootstrap_superadmin('c2100000-0000-4000-8000-000000000001')$$,
  'the rollback fixture establishes a Superadmin'
);
select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(1::smallint, 'c21-executive@example.test', 1::bigint, 'Bind the Audit History authorization fixture.')$$,
  'the rollback fixture establishes an Executive Admin'
);
reset role;

insert into dastak_v1.platform_permission_grants (account_id, bundle_id, granted_by, grant_reason)
select fixture.account_id, bundle.id, 'c2100000-0000-4000-8000-000000000001', 'C2.1 negative authorization fixture'
from (values
  ('c2100000-0000-4000-8000-000000000003'::uuid, 'c21_trace_only'),
  ('c2100000-0000-4000-8000-000000000004'::uuid, 'recovery_operations'),
  ('c2100000-0000-4000-8000-000000000005'::uuid, 'finance_operations'),
  ('c2100000-0000-4000-8000-000000000006'::uuid, 'catalogue_admin'),
  ('c2100000-0000-4000-8000-000000000007'::uuid, 'executive_admin')
) fixture(account_id, bundle_key)
join dastak_v1.permission_bundles bundle on bundle.bundle_key = fixture.bundle_key;

insert into audit.events (id, actor_id, action, entity_type, entity_id, reason, before_state, after_state, created_at) values
  ('c2200000-0000-4000-8000-000000000001', 'c2100000-0000-4000-8000-000000000001', 'legacy.order.reviewed', 'order', 'c2300000-0000-4000-8000-000000000001', 'Reviewed customer request', '{"status":"pending","token":"never"}', '{"status":"approved","secretEvidencePath":"never"}', '2026-09-12T10:00:00Z');
insert into dastak_v1.audit_events (actor_id, action, resource_type, resource_id, metadata, occurred_at) values
  ('c2100000-0000-4000-8000-000000000002', 'order.cancelled', 'order', 'c2300000-0000-4000-8000-000000000002', '{"reason":"Customer confirmed cancellation","fromStatus":"PREPARING","toStatus":"CANCELLED","accessToken":"never","internalSql":"never","evidencePath":"never"}', '2026-09-12T11:00:00Z'),
  (null, 'system.reconciled', 'branch', 'c2400000-0000-4000-8000-000000000001', '{"outcome":"repaired","accountId":"c2100000-0000-4000-8000-000000000008"}', '2026-09-12T12:00:00Z');

select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$,
  'Superadmin can read Audit History'
);
create temporary table audit_first_page as
select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,2,null,null) body;
select is((select pg_catalog.jsonb_array_length(body -> 'events') from audit_first_page), 2, 'Audit History uses a bounded first page');
select is((select body ->> 'hasMore' from audit_first_page), 'true', 'a bounded Audit History page reports additional events truthfully');
select ok((select body -> 'nextCursor' is not null from audit_first_page), 'Audit History emits an opaque cursor');
select ok(
  (select body::text not like '%accessToken%' and body::text not like '%internalSql%' and body::text not like '%evidencePath%' and body::text not like '%"token"%' from audit_first_page),
  'reviewed Audit History never exposes arbitrary secret-bearing metadata'
);
select is(
  (select body #>> '{events,0,action}' from (select public.dastak_v1_admin_audit_history_page(null,null,null,'order.cancelled',null,null,null,null,null,null,20,null,null) body) filtered),
  'order.cancelled',
  'exact action filtering returns the intended event'
);
select is(
  (select body #>> '{events,0,resource,id}' from (select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,'c2300000-0000-4000-8000-000000000001',null,null,null,20,null,null) body) filtered),
  'c2300000-0000-4000-8000-000000000001',
  'order-ID filtering spans the legacy audit store'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$select public.dastak_v1_admin_audit_history_page(null,null,'C21 Superadmin',null,null,null,null,null,null,null,20,null,null)$$,
  'an active Executive Admin can search Audit History by safe actor identity'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$, '42501', 'platform permission required', 'trace-only actor is denied');
reset role;
select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$, '42501', 'platform permission required', 'recovery-only actor is denied');
reset role;
select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000005', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$, '42501', 'platform permission required', 'finance-only actor is denied');
reset role;
select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000006', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$, '42501', 'platform permission required', 'catalogue-only actor is denied');
reset role;
select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000007', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$, '42501', 'active Admin assignment required', 'an inactive Admin assignment is denied despite holding the permission bundle');
reset role;
select pg_catalog.set_config('request.jwt.claim.sub', 'c2100000-0000-4000-8000-000000000008', true);
set local role authenticated;
select throws_ok($$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$, '42501', 'platform permission required', 'authenticated non-Admin is denied');
select throws_ok(
  $$select dastak_v1_api.admin_audit_history_page('c2100000-0000-4000-8000-000000000001',null,null,null,null,null,null,null,null,null,null,20,null,null)$$,
  '42501', 'authentication required', 'an authenticated non-Admin cannot spoof a privileged actor through the internal projection'
);
reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  $$select public.dastak_v1_admin_audit_history_page(null,null,null,null,null,null,null,null,null,null,20,null,null)$$,
  '42501', 'permission denied for function dastak_v1_admin_audit_history_page', 'unauthenticated actor is denied at the function boundary'
);
reset role;

select * from finish();
rollback;
