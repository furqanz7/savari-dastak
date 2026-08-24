begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table(
  'private', 'revoked_account_sessions',
  'customer-removed device sessions have a durable denylist'
);
select ok(
  (select relation.relrowsecurity
   from pg_catalog.pg_class relation
   join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'private'
     and relation.relname = 'revoked_account_sessions'),
  'the session denylist enforces RLS'
);
select is(
  has_table_privilege('authenticated', 'private.revoked_account_sessions', 'SELECT'),
  false,
  'customers cannot inspect session revocation records directly'
);
select is(
  has_function_privilege(
    'authenticated', 'public.revoke_account_session(uuid,uuid,uuid)', 'EXECUTE'
  ),
  false,
  'customers cannot forge the privileged session command directly'
);
select is(
  has_function_privilege(
    'service_role', 'public.revoke_account_session(uuid,uuid,uuid)', 'EXECUTE'
  ),
  true,
  'the authenticated account Edge Function may revoke a device'
);
select is(
  has_function_privilege(
    'authenticated', 'public.export_customer_account_data(uuid)', 'EXECUTE'
  ),
  false,
  'customers cannot export another account through direct RPC'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    'cd000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'account-completion@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'cd000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'account-outsider@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  );

insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, created_at, updated_at
) values
  (
    'cd100000-0000-4000-8000-000000000001',
    'google-account-completion',
    'cd000000-0000-4000-8000-000000000001',
    '{"email":"account-completion@example.test"}', 'google',
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'cd100000-0000-4000-8000-000000000002',
    'apple-account-outsider',
    'cd000000-0000-4000-8000-000000000002',
    '{"email":"account-outsider@example.test"}', 'apple',
    pg_catalog.now(), pg_catalog.now()
  );

insert into public.accounts (id, display_name, phone_number) values
  ('cd000000-0000-4000-8000-000000000001', 'Account Customer', '+919500000101'),
  ('cd000000-0000-4000-8000-000000000002', 'Account Outsider', '+919500000102');
insert into private.account_memberships (account_id, role) values
  ('cd000000-0000-4000-8000-000000000001', 'customer'),
  ('cd000000-0000-4000-8000-000000000002', 'customer');

select lives_ok(
  $$select public.dastak_custom_access_token(
    '{"user_id":"cd000000-0000-4000-8000-000000000001","authentication_method":"oauth","claims":{"app_metadata":{"provider":"google"}}}'::jsonb
  )$$,
  'the proven Google identity is registered before session management'
);

insert into private.account_sessions (
  session_id, account_id, device_name, platform, app_name, user_agent
) values
  (
    'cd200000-0000-4000-8000-000000000001',
    'cd000000-0000-4000-8000-000000000001',
    'Current iPhone', 'ios', 'Customer', 'private-current-agent'
  ),
  (
    'cd200000-0000-4000-8000-000000000002',
    'cd000000-0000-4000-8000-000000000001',
    'Old browser', 'web', 'Customer', 'private-old-agent'
  ),
  (
    'cd200000-0000-4000-8000-000000000003',
    'cd000000-0000-4000-8000-000000000002',
    'Other customer', 'web', 'Customer', 'private-outsider-agent'
  ),
  (
    'cd200000-0000-4000-8000-000000000004',
    'cd000000-0000-4000-8000-000000000001',
    'Tablet browser', 'web', 'Customer', 'private-tablet-agent'
  );

set local role service_role;
select is(
  (
    select response_status from public.revoke_account_session(
      'cd000000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000002'
    )
  ),
  200,
  'a customer may remove one other signed-in device'
);
select is(
  public.is_account_session_revoked(
    'cd000000-0000-4000-8000-000000000001',
    'cd200000-0000-4000-8000-000000000002'
  ),
  true,
  'the removed session is denied immediately at the server boundary'
);
select is(
  (
    select ended_at is not null from private.account_sessions
    where session_id = 'cd200000-0000-4000-8000-000000000002'
  ),
  true,
  'the removed device is no longer listed as active'
);
select is(
  (
    select response_status from public.revoke_account_session(
      'cd000000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000002'
    )
  ),
  200,
  'repeating the same removal is idempotent'
);
select is(
  (
    select pg_catalog.count(*) from private.revoked_account_sessions
    where session_id = 'cd200000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'a retry cannot duplicate the revocation record'
);
select is(
  (
    select response_status from public.revoke_account_session(
      'cd000000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000001'
    )
  ),
  409,
  'the current device uses the explicit sign-out path'
);
select is(
  (
    select response_status from public.revoke_account_session(
      'cd000000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000003'
    )
  ),
  404,
  'one customer cannot revoke another customer session'
);
select is(
  (
    select response_status from public.end_other_account_sessions(
      'cd000000-0000-4000-8000-000000000001',
      'cd200000-0000-4000-8000-000000000001'
    )
  ),
  200,
  'sign out all other devices completes through the existing command'
);
select is(
  public.is_account_session_revoked(
    'cd000000-0000-4000-8000-000000000001',
    'cd200000-0000-4000-8000-000000000004'
  ),
  true,
  'sign out all other devices also enters every session into the denylist'
);

select is(
  (public.export_customer_account_data('cd000000-0000-4000-8000-000000000001') ->> 'formatVersion')::integer,
  1,
  'the account export has a versioned portable format'
);
select is(
  public.export_customer_account_data('cd000000-0000-4000-8000-000000000001') #>> '{profile,accountId}',
  'cd000000-0000-4000-8000-000000000001',
  'the export belongs to the authenticated customer account'
);
select is(
  pg_catalog.strpos(
    public.export_customer_account_data('cd000000-0000-4000-8000-000000000001')::text,
    'private-old-agent'
  ),
  0,
  'the account export never includes stored user-agent details'
);
select is(
  pg_catalog.strpos(
    public.export_customer_account_data('cd000000-0000-4000-8000-000000000001')::text,
    'provider_subject_digest'
  ),
  0,
  'the account export never includes provider subject digests'
);
reset role;

select throws_ok(
  $$select public.dastak_custom_access_token(
    '{"user_id":"cd000000-0000-4000-8000-000000000001","authentication_method":"token_refresh","claims":{"session_id":"cd200000-0000-4000-8000-000000000002","app_metadata":{"provider":"google"}}}'::jsonb
  )$$,
  '28000',
  'This Dastak session has been revoked.',
  'a removed device cannot refresh into another valid Dastak token'
);

set local role service_role;
select is(
  public.prepare_customer_account_deletion(
    'cd000000-0000-4000-8000-000000000002',
    'account-completion-delete-1'
  ) ->> 'prepared',
  'true',
  'history-safe account deletion begins normally'
);
select is(
  public.is_account_session_revoked(
    'cd000000-0000-4000-8000-000000000002',
    'cd200000-0000-4000-8000-000000000003'
  ),
  true,
  'account deletion immediately denies every already-issued device session'
);
reset role;

select is(
  (
    select pg_catalog.count(*) from dastak_v1.audit_events
    where actor_id = 'cd000000-0000-4000-8000-000000000001'
      and action = 'ACCOUNT_SESSION_REVOKED'
  ),
  1::bigint,
  'session removal is audited exactly once'
);

select * from finish();
rollback;
