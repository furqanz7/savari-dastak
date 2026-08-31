begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table(
  'dastak_v1', 'admin_role_assignments',
  'Admin assignments have a private fixed-slot authority'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.admin_role_assignments', 'SELECT'),
  false,
  'browser clients cannot read raw Admin assignments'
);
select is(
  has_function_privilege('authenticated', 'public.dastak_admin_access_snapshot()', 'EXECUTE'),
  true,
  'authenticated Admins can request their safe access snapshot'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_set_executive_admin(smallint,text,bigint,text)',
    'EXECUTE'
  ),
  true,
  'authenticated callers can reach the Superadmin-guarded assignment command'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    'aa000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'superadmin@example.com', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'aa000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'executive@example.com', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'aa000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'outside@example.com', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  );

insert into public.accounts (
  id, display_name, phone_number, account_state
) values
  ('aa000000-0000-4000-8000-000000000001', 'Superadmin', '+919100000001', 'ACTIVE'),
  ('aa000000-0000-4000-8000-000000000002', 'Executive', '+919100000002', 'ACTIVE'),
  ('aa000000-0000-4000-8000-000000000003', 'Outside', '+919100000003', 'ACTIVE');

insert into private.account_memberships (account_id, role) values
  ('aa000000-0000-4000-8000-000000000001', 'customer'),
  ('aa000000-0000-4000-8000-000000000002', 'customer'),
  ('aa000000-0000-4000-8000-000000000003', 'customer');

select lives_ok(
  $$select dastak_v1_api.bootstrap_superadmin(
    'aa000000-0000-4000-8000-000000000001'
  )$$,
  'the first verified account can be established as immutable Superadmin'
);
select is(
  (select count(*) from dastak_v1.admin_role_assignments where role = 'SUPERADMIN'),
  1::bigint,
  'exactly one Superadmin slot exists'
);
select is(
  (select count(*) from dastak_v1.admin_role_assignments where role = 'EXECUTIVE_ADMIN'),
  2::bigint,
  'exactly two Executive Admin slots exist'
);
select is(
  (select route from public.resolve_app_access(
    'aa000000-0000-4000-8000-000000000001', 'admin'
  )),
  'active',
  'the assigned Superadmin can enter Dastak Admin'
);
select is(
  (select route from public.resolve_app_access(
    'aa000000-0000-4000-8000-000000000003', 'admin'
  )),
  'access_denied',
  'an ordinary signed-in account cannot enter Dastak Admin'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'aa000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    1::smallint,
    'executive@example.com',
    1::bigint,
    'Assign first Executive Admin'
  )$$,
  'only the Superadmin can assign an Executive Admin by email'
);
reset role;

select is(
  (select route from public.resolve_app_access(
    'aa000000-0000-4000-8000-000000000002', 'admin'
  )),
  'active',
  'a bound Executive Admin can enter Dastak Admin'
);
select is(
  dastak_v1_api.actor_has_platform_permission(
    'aa000000-0000-4000-8000-000000000002', 'platform.orders.trace'
  ),
  true,
  'Executive Admin has normal Admin operating powers'
);
select is(
  dastak_v1_api.actor_has_platform_permission(
    'aa000000-0000-4000-8000-000000000002', 'platform.permissions.manage'
  ),
  false,
  'Executive Admin cannot assign Admin roles'
);
select is(
  dastak_v1_api.actor_has_platform_permission(
    'aa000000-0000-4000-8000-000000000001', 'platform.permissions.manage'
  ),
  true,
  'Superadmin alone retains Admin role management power'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'aa000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select throws_ok(
  $$select public.dastak_set_executive_admin(
    2::smallint,
    'forbidden@example.com',
    1::bigint,
    'Executive cannot assign another Admin'
  )$$,
  '42501',
  'Superadmin access required.',
  'an Executive Admin cannot change Admin assignments'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'aa000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    2::smallint,
    'future@example.com',
    1::bigint,
    'Reserve second Executive Admin slot'
  )$$,
  'the Superadmin can reserve an Executive slot for a verified email'
);
reset role;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values (
  'aa000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'future@example.com', '',
  pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
  pg_catalog.now(), pg_catalog.now()
);
insert into public.accounts (
  id, display_name, phone_number, account_state
) values (
  'aa000000-0000-4000-8000-000000000004',
  'Future Executive', '+919100000004', 'ACTIVE'
);
insert into private.account_memberships (account_id, role)
values ('aa000000-0000-4000-8000-000000000004', 'customer');

select is(
  (select route from public.resolve_app_access(
    'aa000000-0000-4000-8000-000000000004', 'admin'
  )),
  'active',
  'a pending email assignment binds only to the matching verified account'
);

select throws_ok(
  $$update dastak_v1.admin_role_assignments
    set email_normalized = 'changed@example.com', version = version + 1
    where slot = 0$$,
  '42501',
  'The Superadmin assignment is immutable.',
  'the Superadmin slot cannot be changed'
);
select throws_ok(
  $$delete from dastak_v1.admin_role_assignments where slot = 0$$,
  '42501',
  'Admin assignment slots cannot be deleted.',
  'the Superadmin slot cannot be deleted'
);
select throws_ok(
  $$update auth.users
    set email = 'changed-superadmin@example.com'
    where id = 'aa000000-0000-4000-8000-000000000001'$$,
  '42501',
  'The Superadmin email cannot be changed.',
  'the Superadmin Auth email cannot be changed'
);
select throws_ok(
  $$update public.accounts
    set account_state = 'DELETION_PENDING'
    where id = 'aa000000-0000-4000-8000-000000000001'$$,
  '42501',
  'The Superadmin account cannot be deleted or disabled.',
  'the Superadmin account cannot be disabled'
);
select throws_ok(
  $$delete from private.account_memberships
    where account_id = 'aa000000-0000-4000-8000-000000000001'
      and role = 'owner'$$,
  '42501',
  'The Superadmin membership is immutable.',
  'the Superadmin membership cannot be removed'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'aa000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    1::smallint,
    null,
    2::bigint,
    'Clear first Executive Admin slot'
  )$$,
  'the Superadmin can replace or clear an Executive Admin'
);
reset role;
select is(
  (select route from public.resolve_app_access(
    'aa000000-0000-4000-8000-000000000002', 'admin'
  )),
  'access_denied',
  'a cleared Executive Admin immediately loses Admin access'
);
select is(
  (select count(*) from private.account_memberships
   where account_id = 'aa000000-0000-4000-8000-000000000002'
     and role = 'owner'),
  0::bigint,
  'clearing an Executive slot removes its internal Admin membership'
);

select * from finish();
rollback;
