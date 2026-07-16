begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(16);

select has_function('public', 'resolve_app_access', array['uuid', 'text']);

select is(
  (
    select p.prosecdef
    from pg_catalog.pg_proc p
    where p.oid = 'public.resolve_app_access(uuid,text)'::regprocedure
  ),
  false,
  'resolve_app_access is security invoker'
);

select is(
  (
    select exists (
      select 1
      from pg_catalog.unnest(p.proconfig) as config(value)
      where config.value in ('search_path=', 'search_path=""')
    )
    from pg_catalog.pg_proc p
    where p.oid = 'public.resolve_app_access(uuid,text)'::regprocedure
  ),
  true,
  'resolve_app_access pins an empty search_path'
);

select is(
  (
    select exists (
      select 1
      from pg_catalog.aclexplode(
        coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
      ) as privilege
      where privilege.grantee = 0
        and privilege.privilege_type = 'EXECUTE'
    )
    from pg_catalog.pg_proc p
    where p.oid = 'public.resolve_app_access(uuid,text)'::regprocedure
  ),
  false,
  'PUBLIC cannot execute resolve_app_access'
);
select is(has_function_privilege('anon', 'public.resolve_app_access(uuid,text)', 'EXECUTE'), false, 'anon cannot execute resolve_app_access');
select is(has_function_privilege('authenticated', 'public.resolve_app_access(uuid,text)', 'EXECUTE'), false, 'authenticated cannot execute resolve_app_access');
select is(has_function_privilege('service_role', 'public.resolve_app_access(uuid,text)', 'EXECUTE'), true, 'service_role can execute resolve_app_access');

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
) values (
  '33333333-3333-4333-8333-333333333333',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'access-dastak@example.test',
  '',
  now(),
  now(),
  now()
);

set local role service_role;

select is(
  (select route from public.resolve_app_access('44444444-4444-4444-8444-444444444444', 'customer')),
  'needs_profile',
  'an authenticated identity without a profile needs profile completion'
);

insert into public.accounts (id, display_name, phone_number)
values ('33333333-3333-4333-8333-333333333333', 'Access Test', '+14155552671');

insert into private.account_memberships (account_id, role)
values ('33333333-3333-4333-8333-333333333333', 'customer');

select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'customer')),
  'active',
  'customer membership enters Dastak customer'
);
select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'merchant')),
  'access_denied',
  'customer membership cannot enter Dastak Merchant'
);

insert into private.account_memberships (account_id, role)
values ('33333333-3333-4333-8333-333333333333', 'merchant');

select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'merchant')),
  'pending_approval',
  'unapproved merchant remains pending'
);

update private.account_memberships
set approved_at = now()
where account_id = '33333333-3333-4333-8333-333333333333'
  and role = 'merchant';

select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'merchant')),
  'active',
  'approved merchant enters Dastak Merchant'
);

update private.account_memberships
set suspended_until = now() + interval '1 hour'
where account_id = '33333333-3333-4333-8333-333333333333'
  and role = 'merchant';

select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'merchant')),
  'suspended',
  'suspended merchant cannot enter Dastak Merchant'
);

insert into private.account_memberships (account_id, role)
values ('33333333-3333-4333-8333-333333333333', 'owner');

select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'admin')),
  'pending_approval',
  'unapproved owner remains pending'
);

update private.account_memberships
set approved_at = now()
where account_id = '33333333-3333-4333-8333-333333333333'
  and role = 'owner';

select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'admin')),
  'active',
  'approved owner enters Dastak Admin'
);

select is(
  (select route from public.resolve_app_access('33333333-3333-4333-8333-333333333333', 'unsupported')),
  'access_denied',
  'unsupported application fails closed'
);

reset role;

select * from finish();

rollback;
