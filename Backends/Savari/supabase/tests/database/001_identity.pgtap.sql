begin;

select plan(26);

select has_schema('private');
select has_table('public', 'accounts');
select has_table('private', 'account_memberships');
select has_column('public', 'accounts', 'phone_number');
select has_column('public', 'accounts', 'phone_verification_state');
select has_table('private', 'request_deduplication');
select has_function(
  'public',
  'bootstrap_account',
  array['uuid', 'text', 'text', 'text', 'text']
);

select is(
  (
    select p.prosecdef
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'bootstrap_account'
      and p.oid::regprocedure::text = 'bootstrap_account(uuid,text,text,text,text)'
  ),
  false,
  'public.bootstrap_account is security invoker'
);

select is(
  (
    select exists (
      select 1
      from pg_catalog.unnest(p.proconfig) as config(value)
      where config.value in ('search_path=', 'search_path=""')
    )
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'bootstrap_account'
      and p.oid::regprocedure::text = 'bootstrap_account(uuid,text,text,text,text)'
  ),
  true,
  'public.bootstrap_account pins an empty search_path'
);

select is(has_schema_privilege('anon', 'private', 'USAGE'), false, 'anon cannot use private schema');
select is(has_schema_privilege('authenticated', 'private', 'USAGE'), false, 'authenticated cannot use private schema');
select is(has_schema_privilege('service_role', 'private', 'USAGE'), true, 'service_role can use private schema');
select is(has_table_privilege('anon', 'public.accounts', 'SELECT'), false, 'anon cannot select accounts');
select is(has_table_privilege('authenticated', 'public.accounts', 'SELECT'), true, 'authenticated can select accounts');
select is(has_table_privilege('authenticated', 'public.accounts', 'INSERT'), false, 'authenticated cannot insert accounts');
select is(has_table_privilege('service_role', 'public.accounts', 'INSERT'), true, 'service_role can insert accounts');
select is(has_table_privilege('authenticated', 'private.account_memberships', 'SELECT'), false, 'authenticated cannot select private memberships');
select is(has_table_privilege('authenticated', 'private.request_deduplication', 'SELECT'), false, 'authenticated cannot select private dedupe rows');
select is(
  (
    select exists (
      select 1
      from pg_catalog.aclexplode(
        pg_catalog.coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
      ) as privilege
      where privilege.grantee = 0
        and privilege.privilege_type = 'EXECUTE'
    )
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'bootstrap_account'
      and p.oid::regprocedure::text = 'bootstrap_account(uuid,text,text,text,text)'
  ),
  false,
  'PUBLIC cannot execute bootstrap_account'
);
select is(has_function_privilege('anon', 'public.bootstrap_account(uuid,text,text,text,text)', 'EXECUTE'), false, 'anon cannot execute bootstrap_account');
select is(has_function_privilege('authenticated', 'public.bootstrap_account(uuid,text,text,text,text)', 'EXECUTE'), false, 'authenticated cannot execute bootstrap_account');
select is(has_function_privilege('service_role', 'public.bootstrap_account(uuid,text,text,text,text)', 'EXECUTE'), true, 'service_role can execute bootstrap_account');

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
  '11111111-1111-4111-8111-111111111111',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'bootstrap-savari@example.test',
  '',
  now(),
  now(),
  now()
);

set local role service_role;

select is(
  (
    select response_body ->> 'accountId'
    from public.bootstrap_account(
      '11111111-1111-4111-8111-111111111111',
      'Test Rider',
      '+14155552671',
      'bootstrap-key-1',
      'digest-1'
    )
  ),
  '11111111-1111-4111-8111-111111111111',
  'bootstrap returns the created account id'
);

select is(
  (
    select response_body ->> 'accountId'
    from public.bootstrap_account(
      '11111111-1111-4111-8111-111111111111',
      'Test Rider',
      '+14155552671',
      'bootstrap-key-1',
      'digest-1'
    )
  ),
  '11111111-1111-4111-8111-111111111111',
  'identical idempotency replay returns the stored response'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.bootstrap_account(
      '11111111-1111-4111-8111-111111111111',
      'Changed Rider',
      '+14155552671',
      'bootstrap-key-1',
      'digest-2'
    )
  ),
  'idempotency_conflict',
  'changed request with the same idempotency key is rejected'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.bootstrap_account(
      '11111111-1111-4111-8111-111111111111',
      'Test Rider',
      '+14155552671',
      'bootstrap-key-2',
      'digest-1'
    )
  ),
  'account_already_exists',
  'fresh key after account creation is rejected'
);

reset role;

select * from finish();

rollback;
