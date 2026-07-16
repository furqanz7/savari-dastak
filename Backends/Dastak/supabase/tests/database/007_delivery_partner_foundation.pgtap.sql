begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table(
  'private',
  'delivery_partner_applications',
  'private delivery partner applications exist'
);
select has_table(
  'private',
  'delivery_partner_profiles',
  'private delivery partner profiles exist'
);
select has_table(
  'private',
  'delivery_partner_availability',
  'private delivery partner availability exists'
);
select is(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'private.delivery_partner_applications'::regclass),
  true,
  'delivery partner applications have RLS enabled'
);
select is(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'private.delivery_partner_profiles'::regclass),
  true,
  'delivery partner profiles have RLS enabled'
);
select is(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'private.delivery_partner_availability'::regclass),
  true,
  'delivery partner availability has RLS enabled'
);
select is(
  has_table_privilege('authenticated', 'private.delivery_partner_applications', 'SELECT'),
  false,
  'authenticated cannot read applications directly'
);
select is(
  has_table_privilege('authenticated', 'private.delivery_partner_profiles', 'UPDATE'),
  false,
  'authenticated cannot change an approved delivery method'
);
select is(
  has_table_privilege('authenticated', 'private.delivery_partner_availability', 'UPDATE'),
  false,
  'authenticated cannot forge availability directly'
);

select has_function(
  'public',
  'submit_delivery_partner_application',
  array['uuid', 'text', 'text', 'text', 'text']
);
select has_function('public', 'get_delivery_partner_snapshot', array['uuid']);
select has_function('public', 'list_delivery_partner_applications', array['uuid']);
select has_function(
  'public',
  'review_delivery_partner_application',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text']
);
select has_function(
  'public',
  'set_delivery_partner_availability',
  array['uuid', 'boolean', 'double precision', 'double precision', 'text', 'text']
);
select is(
  has_function_privilege(
    'authenticated',
    'public.submit_delivery_partner_application(uuid,text,text,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass the partner Edge Function'
);
select is(
  has_function_privilege(
    'service_role',
    'public.submit_delivery_partner_application(uuid,text,text,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can submit after bearer verification'
);
select is(
  has_function_privilege(
    'service_role',
    'public.review_delivery_partner_application(uuid,uuid,text,text,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can invoke owner-gated review'
);
select is(
  has_function_privilege(
    'service_role',
    'public.set_delivery_partner_availability(uuid,boolean,double precision,double precision,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can invoke approved partner availability'
);
select is(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_evidence_update_own'
  ),
  false,
  'identity evidence cannot be overwritten after upload'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '70000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'partner-owner@example.test', '',
  now(), now(), now()
),
(
  '70000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'partner-approved@example.test', '',
  now(), now(), now()
),
(
  '70000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'partner-rejected@example.test', '',
  now(), now(), now()
),
(
  '70000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'partner-pending@example.test', '',
  now(), now(), now()
),
(
  '70000000-0000-4000-8000-000000000005',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'partner-outsider@example.test', '',
  now(), now(), now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
  ('70000000-0000-4000-8000-000000000001', 'Marketplace Owner', '+919000000001'),
  ('70000000-0000-4000-8000-000000000002', 'Approved Partner', '+919000000002'),
  ('70000000-0000-4000-8000-000000000003', 'Rejected Partner', '+919000000003'),
  ('70000000-0000-4000-8000-000000000004', 'Pending Partner', '+919000000004'),
  ('70000000-0000-4000-8000-000000000005', 'Ordinary Customer', '+919000000005');

insert into private.account_memberships (account_id, role, approved_at) values
  ('70000000-0000-4000-8000-000000000001', 'owner', pg_catalog.now()),
  ('70000000-0000-4000-8000-000000000002', 'customer', null),
  ('70000000-0000-4000-8000-000000000003', 'customer', null),
  ('70000000-0000-4000-8000-000000000004', 'customer', null),
  ('70000000-0000-4000-8000-000000000005', 'customer', null);

insert into public.service_zones (id, name, boundary, active) values (
  '70000000-0000-4000-8000-000000000010',
  'Delivery Partner Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.55 12.60,78.55 12.75,78.75 12.75,78.75 12.60,78.55 12.60))',
    4326
  ),
  true
);

select is(
  (
    select response_body ->> 'onboardingState'
    from public.get_delivery_partner_snapshot('70000000-0000-4000-8000-000000000002')
  ),
  'not_applied',
  'new customer has not applied'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000002',
      'bike',
      'dastak-partner/70000000-0000-4000-8000-000000000003/identity.pdf',
      'partner-foreign-evidence',
      'partner-foreign-evidence-digest'
    )
  ),
  'validation_failed',
  'another account evidence path is rejected'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000002',
      'truck',
      'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf',
      'partner-invalid-method',
      'partner-invalid-method-digest'
    )
  ),
  'validation_failed',
  'unsupported delivery methods are rejected'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000002',
      'bike',
      'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf',
      'partner-missing-evidence',
      'partner-missing-evidence-digest'
    )
  ),
  'evidence_not_found',
  'application requires uploaded identity evidence'
);

insert into storage.objects (bucket_id, name, owner_id) values
  (
    'dastak-evidence',
    'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf',
    '70000000-0000-4000-8000-000000000002'
  ),
  (
    'dastak-evidence',
    'dastak-partner/70000000-0000-4000-8000-000000000003/identity.pdf',
    '70000000-0000-4000-8000-000000000003'
  ),
  (
    'dastak-evidence',
    'dastak-partner/70000000-0000-4000-8000-000000000003/identity-v2.pdf',
    '70000000-0000-4000-8000-000000000003'
  ),
  (
    'dastak-evidence',
    'dastak-partner/70000000-0000-4000-8000-000000000004/identity.pdf',
    '70000000-0000-4000-8000-000000000004'
  );

select is(
  (
    select response_body ->> 'status'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000002',
      'bike',
      'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf',
      'partner-submit',
      'partner-submit-digest'
    )
  ),
  'pending',
  'valid delivery partner application becomes pending'
);
select is(
  (
    select response_body ->> 'applicationId'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000002',
      'bike',
      'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf',
      'partner-submit',
      'partner-submit-digest'
    )
  ),
  (
    select id::text
    from private.delivery_partner_applications
    where account_id = '70000000-0000-4000-8000-000000000002'
  ),
  'identical application submission replays the original result'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000002',
      'car',
      'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf',
      'partner-submit',
      'changed-partner-submit-digest'
    )
  ),
  'idempotency_conflict',
  'changed application cannot reuse an idempotency key'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000002',
      'bike',
      'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf',
      'partner-submit-again',
      'partner-submit-again-digest'
    )
  ),
  'delivery_partner_application_pending',
  'one account cannot create duplicate pending applications'
);
select is(
  (
    select count(*)::integer
    from public.list_delivery_partner_applications('70000000-0000-4000-8000-000000000005')
  ),
  0,
  'non-owner cannot list pending delivery partners'
);
select is(
  (
    select display_name
    from public.list_delivery_partner_applications('70000000-0000-4000-8000-000000000001')
    where account_id = '70000000-0000-4000-8000-000000000002'
  ),
  'Approved Partner',
  'owner queue includes the applicant identity'
);
select is(
  (
    select phone_number
    from public.list_delivery_partner_applications('70000000-0000-4000-8000-000000000001')
    where account_id = '70000000-0000-4000-8000-000000000002'
  ),
  '+919000000002',
  'owner queue includes the mandatory contact number'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.review_delivery_partner_application(
      '70000000-0000-4000-8000-000000000005',
      (
        select id
        from private.delivery_partner_applications
        where account_id = '70000000-0000-4000-8000-000000000002'
      ),
      'approve', null,
      'partner-non-owner-review',
      'partner-non-owner-review-digest'
    )
  ),
  'access_denied',
  'non-owner cannot approve a delivery partner'
);
select is(
  (
    select response_body ->> 'status'
    from public.review_delivery_partner_application(
      '70000000-0000-4000-8000-000000000001',
      (
        select id
        from private.delivery_partner_applications
        where account_id = '70000000-0000-4000-8000-000000000002'
      ),
      'approve', null,
      'partner-owner-review',
      'partner-owner-review-digest'
    )
  ),
  'approved',
  'active owner approves the delivery partner'
);
select is(
  exists (
    select 1
    from private.account_memberships
    where account_id = '70000000-0000-4000-8000-000000000002'
      and role = 'dastak_partner'
      and approved_at is not null
  ),
  true,
  'approval creates approved Dastak partner membership'
);
select is(
  (
    select delivery_method
    from private.delivery_partner_profiles
    where account_id = '70000000-0000-4000-8000-000000000002'
  ),
  'bike',
  'approval fixes the reviewed delivery method on the profile'
);
select is(
  (
    select status
    from private.delivery_partner_availability
    where account_id = '70000000-0000-4000-8000-000000000002'
  ),
  'offline',
  'approved partner begins offline'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.review_delivery_partner_application(
      '70000000-0000-4000-8000-000000000001',
      (
        select id
        from private.delivery_partner_applications
        where account_id = '70000000-0000-4000-8000-000000000002'
      ),
      'approve', null,
      'partner-second-review',
      'partner-second-review-digest'
    )
  ),
  'delivery_partner_application_reviewed',
  'reviewed application cannot be reviewed again'
);

select is(
  (
    select response_body ->> 'status'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000003',
      'walking',
      'dastak-partner/70000000-0000-4000-8000-000000000003/identity.pdf',
      'partner-reject-submit',
      'partner-reject-submit-digest'
    )
  ),
  'pending',
  'second applicant reaches owner review'
);
select is(
  (
    select response_body ->> 'status'
    from public.review_delivery_partner_application(
      '70000000-0000-4000-8000-000000000001',
      (
        select id
        from private.delivery_partner_applications
        where account_id = '70000000-0000-4000-8000-000000000003'
      ),
      'reject', 'Identity image is unclear',
      'partner-reject-review',
      'partner-reject-review-digest'
    )
  ),
  'rejected',
  'owner can reject with a reason'
);
select is(
  exists (
    select 1
    from private.account_memberships
    where account_id = '70000000-0000-4000-8000-000000000003'
      and role = 'dastak_partner'
  ),
  false,
  'rejection grants no delivery partner membership'
);
select is(
  (
    select response_body ->> 'status'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000003',
      'bicycle',
      'dastak-partner/70000000-0000-4000-8000-000000000003/identity-v2.pdf',
      'partner-reapply',
      'partner-reapply-digest'
    )
  ),
  'pending',
  'rejected applicant can submit fresh evidence for review'
);

select is(
  (
    select response_body ->> 'status'
    from public.submit_delivery_partner_application(
      '70000000-0000-4000-8000-000000000004',
      'auto',
      'dastak-partner/70000000-0000-4000-8000-000000000004/identity.pdf',
      'partner-pending-submit',
      'partner-pending-submit-digest'
    )
  ),
  'pending',
  'unreviewed applicant remains pending'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000004',
      true, 12.68, 78.62,
      'pending-partner-online',
      'pending-partner-online-digest'
    )
  ),
  'access_denied',
  'pending applicant cannot go online'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      false, 12.68, 78.62,
      'partner-invalid-offline',
      'partner-invalid-offline-digest'
    )
  ),
  'validation_failed',
  'offline intent cannot smuggle a location'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, null, null,
      'partner-missing-location',
      'partner-missing-location-digest'
    )
  ),
  'validation_failed',
  'online intent requires a current location'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, 13.00, 79.00,
      'partner-outside-zone',
      'partner-outside-zone-digest'
    )
  ),
  'outside_service_area',
  'partner cannot go online outside an active service zone'
);
select is(
  (
    select response_body ->> 'status'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, 12.68, 78.62,
      'partner-online',
      'partner-online-digest'
    )
  ),
  'online',
  'approved in-zone partner goes online'
);
select is(
  (
    select response_body ->> 'serviceZoneId'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, 12.68, 78.62,
      'partner-online',
      'partner-online-digest'
    )
  ),
  '70000000-0000-4000-8000-000000000010',
  'server resolves the service zone from location'
);
select ok(
  (
    select (response_body ->> 'availableUntil')::timestamptz
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, 12.68, 78.62,
      'partner-online',
      'partner-online-digest'
    )
  ) between pg_catalog.now() + interval '14 minutes 50 seconds'
    and pg_catalog.now() + interval '15 minutes 10 seconds',
  'online presence expires after fifteen minutes without refresh'
);
select is(
  (
    select response_body ->> 'stateVersion'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, 12.68, 78.62,
      'partner-online',
      'partner-online-digest'
    )
  ),
  '2',
  'identical online request replays without another state transition'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      false, null, null,
      'partner-online',
      'changed-partner-online-digest'
    )
  ),
  'idempotency_conflict',
  'availability key cannot be reused with changed intent'
);
select is(
  (
    select response_body #>> '{availability,status}'
    from public.get_delivery_partner_snapshot('70000000-0000-4000-8000-000000000002')
  ),
  'online',
  'self snapshot reports fresh online presence'
);

update private.delivery_partner_availability
set last_seen_at = pg_catalog.now() - interval '16 minutes',
    available_until = pg_catalog.now() - interval '1 minute'
where account_id = '70000000-0000-4000-8000-000000000002';

select is(
  (
    select response_body #>> '{availability,status}'
    from public.get_delivery_partner_snapshot('70000000-0000-4000-8000-000000000002')
  ),
  'offline',
  'stale online row is semantically offline after fifteen minutes'
);
select is(
  (
    select response_body ->> 'status'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, 12.69, 78.63,
      'partner-heartbeat',
      'partner-heartbeat-digest'
    )
  ),
  'online',
  'fresh online activity restores availability'
);

update private.account_memberships
set suspended_until = pg_catalog.now() + interval '1 day'
where account_id = '70000000-0000-4000-8000-000000000002'
  and role = 'dastak_partner';

select is(
  (
    select response_body #>> '{availability,status}'
    from public.get_delivery_partner_snapshot('70000000-0000-4000-8000-000000000002')
  ),
  'offline',
  'suspended partner is never exposed as online'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      true, 12.68, 78.62,
      'suspended-partner-online',
      'suspended-partner-online-digest'
    )
  ),
  'access_denied',
  'suspended partner cannot refresh availability'
);

update private.account_memberships
set suspended_until = null
where account_id = '70000000-0000-4000-8000-000000000002'
  and role = 'dastak_partner';

select is(
  (
    select response_body ->> 'status'
    from public.set_delivery_partner_availability(
      '70000000-0000-4000-8000-000000000002',
      false, null, null,
      'partner-offline',
      'partner-offline-digest'
    )
  ),
  'offline',
  'active partner can explicitly go offline'
);
select is(
  (
    select location is null
      and service_zone_id is null
      and available_until is null
    from private.delivery_partner_availability
    where account_id = '70000000-0000-4000-8000-000000000002'
  ),
  true,
  'offline state clears dispatchable location and expiry'
);

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000002', true);
select results_eq(
  $$
    update storage.objects
    set metadata = '{"changed":true}'::jsonb
    where name = 'dastak-partner/70000000-0000-4000-8000-000000000002/identity.pdf'
    returning name
  $$,
  array[]::text[],
  'authenticated partner cannot replace reviewed evidence'
);
reset role;

select is(
  (
    select count(*)::integer
    from audit.events
    where action = 'delivery_partner_application_submitted'
      and actor_id in (
        '70000000-0000-4000-8000-000000000002',
        '70000000-0000-4000-8000-000000000003',
        '70000000-0000-4000-8000-000000000004'
      )
  ),
  4,
  'every accepted application or reapplication is audited once'
);
select is(
  (
    select count(*)::integer
    from audit.events
    where action = 'delivery_partner_application_reviewed'
      and actor_id = '70000000-0000-4000-8000-000000000001'
  ),
  2,
  'owner decisions are audited once'
);
select is(
  (
    select count(*)::integer
    from audit.events
    where action = 'delivery_partner_went_online'
      and actor_id = '70000000-0000-4000-8000-000000000002'
  ),
  2,
  'initial online state and post-expiry activity are audited'
);
select is(
  (
    select count(*)::integer
    from audit.events
    where action = 'delivery_partner_went_offline'
      and actor_id = '70000000-0000-4000-8000-000000000002'
  ),
  1,
  'explicit offline transition is audited once'
);

select * from finish();
rollback;
