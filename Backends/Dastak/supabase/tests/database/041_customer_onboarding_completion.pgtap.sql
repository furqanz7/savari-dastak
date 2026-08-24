begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_column(
  'private', 'customer_account_deletions', 'available_at',
  'customer Auth deletion is a durable retryable job'
);
select has_column(
  'public', 'dastak_device_tokens', 'provider_identity',
  'Web Push subscriptions have a stable provider identity'
);
select is(
  has_function_privilege(
    'authenticated', 'public.claim_customer_account_deletions(text,integer)', 'EXECUTE'
  ),
  false,
  'customers cannot claim privileged credential deletion jobs'
);
select is(
  has_function_privilege(
    'service_role', 'public.claim_customer_account_deletions(text,integer)', 'EXECUTE'
  ),
  true,
  'only the internal worker can claim credential deletion jobs'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    'cb000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'onboarding-retry@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'cb000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'web-push@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  );

set local role service_role;
select is(
  (
    select response_status
    from public.bootstrap_account(
      'cb000000-0000-4000-8000-000000000001',
      'Retry Customer', '+14155552671', 'bootstrap-retry-first', 'digest-exact'
    )
  ),
  200,
  'first customer profile bootstrap succeeds'
);
select is(
  (
    select response_status
    from public.bootstrap_account(
      'cb000000-0000-4000-8000-000000000001',
      'Retry Customer', '+14155552671', 'bootstrap-retry-after-reload', 'digest-exact'
    )
  ),
  200,
  'same committed profile reconciles after client request-key loss'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.bootstrap_account(
      'cb000000-0000-4000-8000-000000000001',
      'Different Customer', '+14155552671', 'bootstrap-different', 'digest-different'
    )
  ),
  'account_already_exists',
  'reconciliation never overwrites a different existing profile'
);

insert into public.accounts (id, display_name, phone_number)
values ('cb000000-0000-4000-8000-000000000002', 'Push Customer', '+14155552672');
insert into private.account_memberships (account_id, role)
values ('cb000000-0000-4000-8000-000000000002', 'customer');

select is(
  public.prepare_customer_account_deletion(
    'cb000000-0000-4000-8000-000000000001', 'delete-request-one'
  ) ->> 'deletionQueued',
  'true',
  'account deletion immediately enters the durable queue'
);
select is(
  public.prepare_customer_account_deletion(
    'cb000000-0000-4000-8000-000000000001', 'delete-request-retry'
  ) ->> 'prepared',
  'true',
  'a retried deletion request cannot strand an already pending account'
);
select is(
  (
    select request_count
    from private.customer_account_deletions
    where account_id = 'cb000000-0000-4000-8000-000000000001'
  ),
  2,
  'every accepted deletion request remains auditable'
);

create temp table tap_deletion_claim on commit drop as
select value as job
from pg_catalog.jsonb_array_elements(
  public.claim_customer_account_deletions('customer-deletion-worker-a', 10)
);
select is(
  (select pg_catalog.count(*) from tap_deletion_claim),
  1::bigint,
  'one worker exclusively claims the pending credential deletion'
);
select is(
  pg_catalog.jsonb_array_length(
    public.claim_customer_account_deletions('customer-deletion-worker-b', 10)
  ),
  0,
  'a competing worker cannot claim the same deletion'
);
select is(
  public.complete_customer_account_deletion(
    'cb000000-0000-4000-8000-000000000001',
    'customer-deletion-worker-a', false, 'transient Auth outage'
  ) ->> 'deleted',
  'false',
  'an Auth outage preserves a retryable fail-closed account state'
);
update private.customer_account_deletions
set available_at = pg_catalog.clock_timestamp()
where account_id = 'cb000000-0000-4000-8000-000000000001';
select is(
  pg_catalog.jsonb_array_length(
    public.claim_customer_account_deletions('customer-deletion-worker-retry', 10)
  ),
  1,
  'the same account becomes claimable after durable retry backoff'
);
reset role;
delete from auth.users where id = 'cb000000-0000-4000-8000-000000000001';
set local role service_role;
select is(
  public.complete_customer_account_deletion(
    'cb000000-0000-4000-8000-000000000001',
    'customer-deletion-worker-retry', true, null
  ) ->> 'deleted',
  'true',
  'credential removal finalises the retained history-safe tombstone'
);
select is(
  (
    select account_state::text
    from public.accounts
    where id = 'cb000000-0000-4000-8000-000000000001'
  ),
  'DELETED',
  'completed deletion cannot restore product access'
);

select lives_ok(
  $$select public.dastak_v1_register_device_token(
    'cb000000-0000-4000-8000-000000000002',
    '{"endpoint":"https://push.example.test/customer-two","expirationTime":null,"keys":{"auth":"auth-one","p256dh":"key-one"}}',
    'web'
  )$$,
  'an authenticated canonical Web Push subscription can be registered'
);
select lives_ok(
  $$select public.dastak_v1_register_device_token(
    'cb000000-0000-4000-8000-000000000002',
    '{"endpoint":"https://push.example.test/customer-two","expirationTime":null,"keys":{"auth":"auth-two","p256dh":"key-two"}}',
    'web'
  )$$,
  'rotated browser keys update the same endpoint identity'
);
select is(
  (
    select pg_catalog.count(*)
    from public.dastak_device_tokens
    where account_id = 'cb000000-0000-4000-8000-000000000002'
      and platform = 'web'
  ),
  1::bigint,
  'one browser endpoint cannot produce duplicate active subscriptions'
);
select throws_ok(
  $$select public.dastak_v1_register_device_token(
    'cb000000-0000-4000-8000-000000000002',
    '{"endpoint":"http://insecure.example.test","keys":{"auth":"a","p256dh":"b"}}',
    'web'
  )$$,
  '22023',
  'invalid web push subscription',
  'insecure Web Push endpoints are rejected server-side'
);

reset role;
select * from finish();
rollback;
