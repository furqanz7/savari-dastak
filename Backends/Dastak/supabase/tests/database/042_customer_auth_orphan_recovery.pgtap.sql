begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege(
    'supabase_auth_admin',
    'private.reconcile_orphaned_customer_oauth_identity(text,bytea,uuid)',
    'EXECUTE'
  ),
  true,
  'Supabase Auth can invoke the narrowly scoped orphan recovery command'
);
select is(
  has_function_privilege(
    'authenticated',
    'private.reconcile_orphaned_customer_oauth_identity(text,bytea,uuid)',
    'EXECUTE'
  ),
  false,
  'customers cannot invoke privileged OAuth orphan recovery'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'cc000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'orphan-old@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
);
insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, created_at, updated_at
) values (
  'cc100000-0000-4000-8000-000000000001',
  'google-orphan-subject',
  'cc000000-0000-4000-8000-000000000001',
  '{"email":"orphan-old@example.test"}', 'google',
  pg_catalog.now(), pg_catalog.now()
);
insert into public.accounts (id, display_name, phone_number) values (
  'cc000000-0000-4000-8000-000000000001',
  'OAuth Orphan Customer', '+919500000091'
);
insert into private.account_memberships (account_id, role) values (
  'cc000000-0000-4000-8000-000000000001', 'customer'
);

select lives_ok(
  $$select public.dastak_custom_access_token('{"user_id":"cc000000-0000-4000-8000-000000000001","authentication_method":"oauth","claims":{"app_metadata":{"provider":"google"}}}'::jsonb)$$,
  'the original Google identity is registered normally'
);

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status, submitted_at
) values (
  'cc200000-0000-4000-8000-000000000001',
  'DASTAK-OAUTH-ORPHAN-HISTORY',
  'cc000000-0000-4000-8000-000000000001',
  'RETAIL_ONLY', 'PAYMENT_EXPIRED', pg_catalog.now()
);
insert into dastak_v1.audit_events (
  actor_id, action, resource_type, resource_id
) values (
  'cc000000-0000-4000-8000-000000000001',
  'OAUTH_ORPHAN_TEST_HISTORY', 'customer_account',
  'cc000000-0000-4000-8000-000000000001'
);

-- Reproduce the production defect: Auth is deleted directly while the Dastak
-- account and immutable history remain.
delete from auth.users
where id = 'cc000000-0000-4000-8000-000000000001';

select is(
  (
    select account_state::text from public.accounts
    where id = 'cc000000-0000-4000-8000-000000000001'
  ),
  'DELETED',
  'direct Auth deletion immediately tombstones the customer business account'
);
select is(
  (
    select pg_catalog.count(*) from private.customer_auth_identities
    where account_id = 'cc000000-0000-4000-8000-000000000001'
      and revoked_at is not null
  ),
  1::bigint,
  'direct Auth deletion immediately revokes the historical OAuth link'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'cc000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'orphan-new@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
);
insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, created_at, updated_at
) values (
  'cc100000-0000-4000-8000-000000000002',
  'google-orphan-subject',
  'cc000000-0000-4000-8000-000000000002',
  '{"email":"orphan-new@example.test"}', 'google',
  pg_catalog.now(), pg_catalog.now()
);

select lives_ok(
  $$select public.dastak_custom_access_token('{"user_id":"cc000000-0000-4000-8000-000000000002","authentication_method":"oauth","claims":{"app_metadata":{"provider":"google"}}}'::jsonb)$$,
  'the same proven Google subject recovers after its old Auth credential was removed'
);
select lives_ok(
  $$select public.dastak_custom_access_token('{"user_id":"cc000000-0000-4000-8000-000000000002","authentication_method":"oauth","claims":{"app_metadata":{"provider":"google"}}}'::jsonb)$$,
  'duplicate token issuance reuses the one active provider registration'
);
select is(
  (
    select account_state::text from public.accounts
    where id = 'cc000000-0000-4000-8000-000000000001'
  ),
  'DELETED',
  'the orphaned business account becomes an anonymised tombstone'
);
select is(
  (
    select display_name from public.accounts
    where id = 'cc000000-0000-4000-8000-000000000001'
  ),
  'Deleted customer',
  'orphan recovery removes eligible customer PII'
);
select is(
  (
    select pg_catalog.count(*) from private.customer_auth_identities
    where account_id = 'cc000000-0000-4000-8000-000000000001'
      and revoked_at is not null
  ),
  1::bigint,
  'the historical OAuth link is revoked rather than deleted'
);
select is(
  (
    select pg_catalog.count(*) from private.customer_auth_identities
    where account_id = 'cc000000-0000-4000-8000-000000000002'
      and provider = 'google' and link_kind = 'ORIGIN' and revoked_at is null
  ),
  1::bigint,
  'the replacement credential receives one active origin link'
);
select is(
  (
    select pg_catalog.count(*) from dastak_v1.orders
    where id = 'cc200000-0000-4000-8000-000000000001'
      and customer_id = 'cc000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'OAuth recovery preserves historical orders under the tombstone account'
);
select is(
  (
    select pg_catalog.count(*) from dastak_v1.audit_events
    where resource_id = 'cc000000-0000-4000-8000-000000000001'
      and action = 'CUSTOMER_ACCOUNT_DELETED'
  ),
  1::bigint,
  'direct credential deletion is recorded in immutable account history'
);

set local role service_role;
select is(
  (
    select response_status from public.bootstrap_account(
      'cc000000-0000-4000-8000-000000000002',
      'Replacement Customer', '+919500000092',
      'bootstrap-after-orphan-recovery', 'orphan-recovery-digest'
    )
  ),
  200,
  'the recovered Google login can complete fresh customer onboarding'
);
reset role;

-- Reproduce an orphan created before this fix existed. Its old Auth user is
-- already absent, so the next proven Apple login must reconcile it in-hook.
insert into public.accounts (id, display_name, phone_number) values (
  'cc000000-0000-4000-8000-000000000011',
  'Existing OAuth Orphan', '+919500000093'
);
insert into private.account_memberships (account_id, role) values (
  'cc000000-0000-4000-8000-000000000011', 'customer'
);
insert into private.customer_auth_identities (
  account_id, provider, provider_subject_digest, link_kind
) values (
  'cc000000-0000-4000-8000-000000000011', 'apple',
  extensions.digest('apple-existing-orphan-subject', 'sha256'), 'ORIGIN'
);
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'cc000000-0000-4000-8000-000000000012',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'existing-orphan-new@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
);
insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, created_at, updated_at
) values (
  'cc100000-0000-4000-8000-000000000012',
  'apple-existing-orphan-subject',
  'cc000000-0000-4000-8000-000000000012',
  '{"email":"existing-orphan-new@example.test"}', 'apple',
  pg_catalog.now(), pg_catalog.now()
);
select lives_ok(
  $$select public.dastak_custom_access_token('{"user_id":"cc000000-0000-4000-8000-000000000012","authentication_method":"oauth","claims":{"app_metadata":{"provider":"apple"}}}'::jsonb)$$,
  'a pre-existing OAuth orphan is repaired during the next proven provider login'
);
select is(
  (
    select account_state::text from public.accounts
    where id = 'cc000000-0000-4000-8000-000000000011'
  ),
  'DELETED',
  'pre-existing orphan recovery preserves an anonymised business tombstone'
);
select is(
  (
    select pg_catalog.count(*) from dastak_v1.audit_events
    where resource_id = 'cc000000-0000-4000-8000-000000000011'
      and action = 'CUSTOMER_AUTH_ORPHAN_RECONCILED'
  ),
  1::bigint,
  'pre-existing orphan repair is explicitly audited'
);

select throws_ok(
  $$insert into private.customer_auth_identities (
      account_id, provider, provider_subject_digest, link_kind
    ) values (
      'cc000000-0000-4000-8000-000000000003', 'google',
      extensions.digest('google-orphan-subject', 'sha256'), 'ORIGIN'
    )$$,
  '23505',
  null,
  'only one active account can own a provider subject'
);

select * from finish();
rollback;
