begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(36);

select has_table(
  'private',
  'merchant_applications',
  'private.merchant_applications exists'
);
select has_function(
  'public',
  'submit_merchant_application',
  array['uuid', 'text', 'text', 'text', 'text', 'text']
);
select has_function('public', 'list_merchant_applications', array['uuid']);
select has_function(
  'public',
  'review_merchant_application',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text']
);
select is(
  has_table_privilege('authenticated', 'private.merchant_applications', 'SELECT'),
  false,
  'authenticated cannot read private merchant applications'
);
select is(
  has_function_privilege('anon', 'public.submit_merchant_application(uuid,text,text,text,text,text)', 'EXECUTE'),
  false,
  'anon cannot submit through the server-only RPC'
);
select is(
  has_function_privilege('authenticated', 'public.submit_merchant_application(uuid,text,text,text,text,text)', 'EXECUTE'),
  false,
  'authenticated cannot call the submit RPC directly'
);
select is(
  has_function_privilege('service_role', 'public.submit_merchant_application(uuid,text,text,text,text,text)', 'EXECUTE'),
  true,
  'service_role can submit a verified application'
);
select is(
  has_function_privilege('service_role', 'public.list_merchant_applications(uuid)', 'EXECUTE'),
  true,
  'service_role can list through the owner gate'
);
select is(
  has_function_privilege('service_role', 'public.review_merchant_application(uuid,uuid,text,text,text,text)', 'EXECUTE'),
  true,
  'service_role can review through the owner gate'
);

select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_merchant_evidence_insert_own'
  ),
  true,
  'merchant evidence has a self-owned insert policy'
);
select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_merchant_evidence_select_own'
  ),
  true,
  'merchant evidence has a self-owned select policy'
);
select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_merchant_evidence_update_own'
  ),
  false,
  'submitted merchant evidence cannot be replaced by the applicant'
);
select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_merchant_evidence_delete_own'
  ),
  false,
  'merchant evidence cannot be deleted by the applicant'
);

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
) values
(
  '77777777-7777-4777-8777-777777777777',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'merchant-applicant@example.test',
  '',
  now(),
  now(),
  now()
),
(
  '88888888-8888-4888-8888-888888888888',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'merchant-owner@example.test',
  '',
  now(),
  now(),
  now()
),
(
  '99999999-9999-4999-8999-999999999999',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'rejected-merchant@example.test',
  '',
  now(),
  now(),
  now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number)
values
  ('77777777-7777-4777-8777-777777777777', 'Merchant Applicant', '+14155552671'),
  ('88888888-8888-4888-8888-888888888888', 'Marketplace Owner', '+14155552672'),
  ('99999999-9999-4999-8999-999999999999', 'Rejected Merchant', '+14155552673');

insert into private.account_memberships (account_id, role, approved_at)
values
  ('77777777-7777-4777-8777-777777777777', 'customer', null),
  ('88888888-8888-4888-8888-888888888888', 'owner', now()),
  ('99999999-9999-4999-8999-999999999999', 'customer', null);

select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_merchant_application(
      '77777777-7777-4777-8777-777777777777',
      'Corner Store',
      '12 Main Road',
      'merchant/88888888-8888-4888-8888-888888888888/registration.pdf',
      'invalid-path-key',
      'invalid-path-digest'
    )
  ),
  'validation_failed',
  'another account evidence path is rejected in the database'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_merchant_application(
      '77777777-7777-4777-8777-777777777777',
      'Corner Store',
      '12 Main Road',
      'merchant/77777777-7777-4777-8777-777777777777/registration.pdf',
      'missing-evidence-key',
      'missing-evidence-digest'
    )
  ),
  'evidence_not_found',
  'submission requires an uploaded evidence object'
);

insert into storage.objects (bucket_id, name, owner_id)
values (
  'dastak-evidence',
  'merchant/77777777-7777-4777-8777-777777777777/registration.pdf',
  '77777777-7777-4777-8777-777777777777'
);

select is(
  (
    select response_body ->> 'status'
    from public.submit_merchant_application(
      '77777777-7777-4777-8777-777777777777',
      'Corner Store',
      '12 Main Road',
      'merchant/77777777-7777-4777-8777-777777777777/registration.pdf',
      'merchant-submit-key',
      'merchant-submit-digest'
    )
  ),
  'pending',
  'valid merchant application becomes pending'
);

select is(
  (
    select response_body ->> 'applicationId'
    from public.submit_merchant_application(
      '77777777-7777-4777-8777-777777777777',
      'Corner Store',
      '12 Main Road',
      'merchant/77777777-7777-4777-8777-777777777777/registration.pdf',
      'merchant-submit-key',
      'merchant-submit-digest'
    )
  ),
  (select id::text from private.merchant_applications where account_id = '77777777-7777-4777-8777-777777777777'),
  'identical merchant submission replays the original response'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_merchant_application(
      '77777777-7777-4777-8777-777777777777',
      'Changed Store',
      '12 Main Road',
      'merchant/77777777-7777-4777-8777-777777777777/registration.pdf',
      'merchant-submit-key',
      'changed-digest'
    )
  ),
  'idempotency_conflict',
  'changed merchant submission cannot reuse an idempotency key'
);

select is(
  (select status from private.merchant_applications where account_id = '77777777-7777-4777-8777-777777777777'),
  'pending',
  'application is stored privately as pending'
);
select is(
  (select route from public.resolve_app_access('77777777-7777-4777-8777-777777777777', 'merchant')),
  'pending_approval',
  'pending application returns the pending route'
);
select is(
  (select count(*)::integer from public.list_merchant_applications('77777777-7777-4777-8777-777777777777')),
  0,
  'non-owner cannot list merchant applications'
);
select is(
  (
    select application_id::text
    from public.list_merchant_applications('88888888-8888-4888-8888-888888888888')
  ),
  (select id::text from private.merchant_applications where account_id = '77777777-7777-4777-8777-777777777777'),
  'active owner can list the pending application'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.review_merchant_application(
      '77777777-7777-4777-8777-777777777777',
      (select id from private.merchant_applications where account_id = '77777777-7777-4777-8777-777777777777'),
      'approve',
      null,
      'non-owner-review-key',
      'non-owner-review-digest'
    )
  ),
  'access_denied',
  'non-owner cannot review a merchant application'
);

select is(
  (
    select response_body ->> 'status'
    from public.review_merchant_application(
      '88888888-8888-4888-8888-888888888888',
      (select id from private.merchant_applications where account_id = '77777777-7777-4777-8777-777777777777'),
      'approve',
      null,
      'owner-review-key',
      'owner-review-digest'
    )
  ),
  'approved',
  'active owner can approve the application'
);

select is(
  (
    select response_body ->> 'status'
    from public.review_merchant_application(
      '88888888-8888-4888-8888-888888888888',
      (select id from private.merchant_applications where account_id = '77777777-7777-4777-8777-777777777777'),
      'approve',
      null,
      'owner-review-key',
      'owner-review-digest'
    )
  ),
  'approved',
  'identical owner review replays the approved response'
);

select is(
  exists (
    select 1
    from private.account_memberships
    where account_id = '77777777-7777-4777-8777-777777777777'
      and role = 'merchant'
      and approved_at is not null
  ),
  true,
  'approval grants an approved merchant membership'
);
select is(
  (select route from public.resolve_app_access('77777777-7777-4777-8777-777777777777', 'merchant')),
  'active',
  'approved merchant receives the active route'
);

reset role;

select is(
  exists (
    select 1 from audit.events
    where action = 'merchant_application_submitted'
      and actor_id = '77777777-7777-4777-8777-777777777777'
  ),
  true,
  'merchant submission is audited'
);
select is(
  exists (
    select 1 from audit.events
    where action = 'merchant_application_reviewed'
      and actor_id = '88888888-8888-4888-8888-888888888888'
  ),
  true,
  'owner review is audited'
);

set local role service_role;

select is(
  (select count(*)::integer from public.list_merchant_applications('88888888-8888-4888-8888-888888888888')),
  0,
  'reviewed applications leave the pending owner queue'
);

insert into storage.objects (bucket_id, name, owner_id)
values (
  'dastak-evidence',
  'merchant/99999999-9999-4999-8999-999999999999/registration.pdf',
  '99999999-9999-4999-8999-999999999999'
);

select is(
  (
    select response_body ->> 'status'
    from public.submit_merchant_application(
      '99999999-9999-4999-8999-999999999999',
      'Rejected Store',
      '14 Main Road',
      'merchant/99999999-9999-4999-8999-999999999999/registration.pdf',
      'rejected-submit-key',
      'rejected-submit-digest'
    )
  ),
  'pending',
  'second valid application reaches owner review'
);

select is(
  (
    select response_body ->> 'status'
    from public.review_merchant_application(
      '88888888-8888-4888-8888-888888888888',
      (select id from private.merchant_applications where account_id = '99999999-9999-4999-8999-999999999999'),
      'reject',
      'Registration is incomplete',
      'rejected-review-key',
      'rejected-review-digest'
    )
  ),
  'rejected',
  'active owner can reject an application'
);
select is(
  (select review_reason from private.merchant_applications where account_id = '99999999-9999-4999-8999-999999999999'),
  'Registration is incomplete',
  'rejection reason is stored for the reviewed application'
);
select is(
  exists (
    select 1 from private.account_memberships
    where account_id = '99999999-9999-4999-8999-999999999999'
      and role = 'merchant'
  ),
  false,
  'rejection does not grant merchant membership'
);
select is(
  (select route from public.resolve_app_access('99999999-9999-4999-8999-999999999999', 'merchant')),
  'access_denied',
  'rejected merchant remains blocked from Dastak Merchant'
);

reset role;

select * from finish();

rollback;
