begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (
    select definition.sensitivity::text
    from dastak_v1.permission_definitions definition
    where definition.permission_key = 'platform.network.read'
  ),
  'HIGHLY_SENSITIVE',
  'the identity directory has a dedicated highly-sensitive permission'
);

select is(
  (
    select pg_catalog.array_agg(bundle.bundle_key order by bundle.bundle_key)
    from dastak_v1.permission_bundle_permissions bundle_permission
    join dastak_v1.permission_bundles bundle
      on bundle.id = bundle_permission.bundle_id
    where bundle_permission.permission_key = 'platform.network.read'
  ),
  array['executive_admin', 'platform_super_admin']::text[],
  'only the two assigned Admin bundles receive identity-directory access'
);

select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_admin_network_page(text,text,text,integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  false,
  'anonymous sessions cannot execute the public identity-directory projection'
);

select is(
  has_function_privilege(
    'anon',
    'dastak_v1_api.admin_network_page(uuid,text,text,text,integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  false,
  'anonymous sessions cannot execute the internal identity-directory projection'
);

select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.admin_network_page(uuid,text,text,text,integer,timestamptz,uuid)'::regprocedure
  ),
  'platform\.network\.read',
  'the installed identity directory requires the dedicated permission'
);

select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.admin_network_page(uuid,text,text,text,integer,timestamptz,uuid)'::regprocedure
  ),
  'admin_role_for_actor\(p_actor_id\)',
  'the installed identity directory also requires an active Admin assignment'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'dastak_v1_api.admin_network_page(uuid,text,text,text,integer,timestamptz,uuid)'::regprocedure
    ),
    'platform.orders.trace'
  ) = 0,
  'order tracing no longer authorizes the installed identity directory'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'dastak_v1_api')
      and procedure.prokind = 'f'
      and pg_catalog.pg_get_functiondef(procedure.oid) like '%lastSignInAt%'
      and pg_catalog.pg_get_functiondef(procedure.oid) like '%phoneNumber%'
      and pg_catalog.pg_get_functiondef(procedure.oid) like '%platform.orders.trace%'
  ),
  0::bigint,
  'no installed alternative identity projection remains authorized by order tracing'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    'a1000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a1-superadmin@example.test', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'a1000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a1-executive@example.test', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'a1000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a1-trace@example.test', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'a1000000-0000-4000-8000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a1-recovery@example.test', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'a1000000-0000-4000-8000-000000000005',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a1-finance@example.test', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'a1000000-0000-4000-8000-000000000006',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a1-non-admin@example.test', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  );

insert into public.accounts (
  id, display_name, phone_number, account_state
) values
  ('a1000000-0000-4000-8000-000000000001', 'A1 Superadmin', '+919600000001', 'ACTIVE'),
  ('a1000000-0000-4000-8000-000000000002', 'A1 Executive', '+919600000002', 'ACTIVE'),
  ('a1000000-0000-4000-8000-000000000003', 'A1 Trace', '+919600000003', 'ACTIVE'),
  ('a1000000-0000-4000-8000-000000000004', 'A1 Recovery', '+919600000004', 'ACTIVE'),
  ('a1000000-0000-4000-8000-000000000005', 'A1 Finance', '+919600000005', 'ACTIVE'),
  ('a1000000-0000-4000-8000-000000000006', 'A1 Non Admin', '+919600000006', 'ACTIVE');

insert into private.account_memberships (account_id, role) values
  ('a1000000-0000-4000-8000-000000000001', 'customer'),
  ('a1000000-0000-4000-8000-000000000002', 'customer'),
  ('a1000000-0000-4000-8000-000000000003', 'customer'),
  ('a1000000-0000-4000-8000-000000000004', 'customer'),
  ('a1000000-0000-4000-8000-000000000005', 'customer'),
  ('a1000000-0000-4000-8000-000000000006', 'customer');

insert into dastak_v1.permission_bundles (
  id, bundle_key, display_name, scope, description
) values (
  'a1100000-0000-4000-8000-000000000001',
  'a1_trace_only',
  'A1 trace only',
  'PLATFORM',
  'Rollback-only fixture containing only the order tracing permission.'
);

insert into dastak_v1.permission_bundle_permissions (
  bundle_id, permission_key
) values (
  'a1100000-0000-4000-8000-000000000001',
  'platform.orders.trace'
);

select lives_ok(
  $$select dastak_v1_api.bootstrap_superadmin(
    'a1000000-0000-4000-8000-000000000001'
  )$$,
  'the rollback-only fixture establishes a Superadmin'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    1::smallint,
    'a1-executive@example.test',
    1::bigint,
    'Bind the intended Admin for network authorization testing.'
  )$$,
  'the intended Executive Admin assignment is established'
);
select lives_ok(
  $$select public.dastak_v1_admin_network_page(
    'a1-executive@example.test', 'ADMIN', 'ACTIVE', 20, null, null
  )$$,
  'Superadmin retains identity-directory access'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_v1_admin_network_page(
    'a1-superadmin@example.test', 'ADMIN', 'ACTIVE', 20, null, null
  )$$,
  'an intended active Executive Admin can read the identity directory'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    2::smallint,
    'a1-trace@example.test',
    1::bigint,
    'Bind the trace-only authorization fixture.'
  )$$,
  'the trace-only actor receives an active Admin assignment for the denial test'
);
reset role;

update dastak_v1.platform_permission_grants grant_row
set revoked_by = 'a1000000-0000-4000-8000-000000000001',
    revoke_reason = 'Replace broad Admin fixture with trace-only access',
    revoked_at = pg_catalog.clock_timestamp(),
    version = grant_row.version + 1
where grant_row.account_id = 'a1000000-0000-4000-8000-000000000003'
  and grant_row.revoked_at is null;
insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
) values (
  'a1000000-0000-4000-8000-000000000003',
  'a1100000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'Trace-only identity-directory denial fixture.'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select throws_ok(
  $$select public.dastak_v1_admin_network_page(null, null, null, 20, null, null)$$,
  '42501',
  'platform permission required',
  'an active Admin holding only order tracing cannot read the identity directory'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    2::smallint,
    'a1-recovery@example.test',
    2::bigint,
    'Bind the recovery-only authorization fixture.'
  )$$,
  'the recovery-only actor receives an active Admin assignment for the denial test'
);
reset role;

update dastak_v1.platform_permission_grants grant_row
set revoked_by = 'a1000000-0000-4000-8000-000000000001',
    revoke_reason = 'Replace broad Admin fixture with recovery-only access',
    revoked_at = pg_catalog.clock_timestamp(),
    version = grant_row.version + 1
where grant_row.account_id = 'a1000000-0000-4000-8000-000000000004'
  and grant_row.revoked_at is null;
insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
)
select
  'a1000000-0000-4000-8000-000000000004',
  bundle.id,
  'a1000000-0000-4000-8000-000000000001',
  'Recovery-only identity-directory denial fixture.'
from dastak_v1.permission_bundles bundle
where bundle.bundle_key = 'recovery_operations';

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select throws_ok(
  $$select public.dastak_v1_admin_network_page(null, null, null, 20, null, null)$$,
  '42501',
  'platform permission required',
  'an active Admin holding only recovery operations cannot read the identity directory'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    2::smallint,
    'a1-finance@example.test',
    3::bigint,
    'Bind the finance-only authorization fixture.'
  )$$,
  'the finance-only actor receives an active Admin assignment for the denial test'
);
reset role;

update dastak_v1.platform_permission_grants grant_row
set revoked_by = 'a1000000-0000-4000-8000-000000000001',
    revoke_reason = 'Replace broad Admin fixture with finance-only access',
    revoked_at = pg_catalog.clock_timestamp(),
    version = grant_row.version + 1
where grant_row.account_id = 'a1000000-0000-4000-8000-000000000005'
  and grant_row.revoked_at is null;
insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
)
select
  'a1000000-0000-4000-8000-000000000005',
  bundle.id,
  'a1000000-0000-4000-8000-000000000001',
  'Finance-only identity-directory denial fixture.'
from dastak_v1.permission_bundles bundle
where bundle.bundle_key = 'finance_operations';

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select throws_ok(
  $$select public.dastak_v1_admin_network_page(null, null, null, 20, null, null)$$,
  '42501',
  'platform permission required',
  'an active Admin holding only finance operations cannot read the identity directory'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select throws_ok(
  $$select public.dastak_v1_admin_network_page(null, null, null, 20, null, null)$$,
  '42501',
  'platform permission required',
  'an authenticated non-Admin cannot read the identity directory'
);
select throws_ok(
  $$select dastak_v1_api.admin_network_page(
    'a1000000-0000-4000-8000-000000000001',
    null, null, null, 20, null, null
  )$$,
  '42501',
  'authentication required',
  'an authenticated caller cannot spoof an Admin through the internal projection'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  $$select public.dastak_v1_admin_network_page(null, null, null, 20, null, null)$$,
  '42501',
  'permission denied for function dastak_v1_admin_network_page',
  'an unauthenticated caller cannot execute the identity directory'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role service_role;
select throws_ok(
  $$select dastak_v1_api.admin_network_page(
    'a1000000-0000-4000-8000-000000000001',
    null, null, null, 20, null, null
  )$$,
  '42501',
  'authentication required',
  'a broad service execution grant cannot bypass caller-bound authorization'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    1::smallint,
    null,
    2::bigint,
    'Remove the Executive Admin assignment for authorization testing.'
  )$$,
  'the Executive Admin assignment is removed through the audited command'
);
reset role;

insert into private.account_memberships (
  account_id, role, approved_at, suspended_until
) values (
  'a1000000-0000-4000-8000-000000000002',
  'owner',
  pg_catalog.clock_timestamp(),
  null
)
on conflict (account_id, role) do update
set approved_at = excluded.approved_at,
    suspended_until = null;

insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
)
select
  'a1000000-0000-4000-8000-000000000002',
  bundle.id,
  'a1000000-0000-4000-8000-000000000001',
  'Prove an active Admin assignment is independently required.'
from dastak_v1.permission_bundles bundle
where bundle.bundle_key = 'executive_admin';

select is(
  dastak_v1_api.actor_has_platform_permission(
    'a1000000-0000-4000-8000-000000000002',
    'platform.network.read'
  ),
  true,
  'the removed Admin fixture still holds the dedicated permission for the independent assignment test'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select throws_ok(
  $$select public.dastak_v1_admin_network_page(null, null, null, 20, null, null)$$,
  '42501',
  'active Admin assignment required',
  'removing the Admin assignment removes directory access even if a permission grant remains'
);
reset role;

select * from finish();
rollback;
