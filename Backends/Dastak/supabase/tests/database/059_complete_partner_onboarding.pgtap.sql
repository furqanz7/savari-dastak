begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(36);

select has_column('private', 'merchant_applications', 'merchant_type',
  'merchant applications record the authoritative business type');
select has_column('private', 'merchant_applications', 'legal_name',
  'merchant applications retain the legal business name');
select has_column('private', 'merchant_applications', 'location',
  'merchant applications retain the selected branch location');
select has_column('private', 'merchant_applications', 'service_zone_id',
  'merchant applications retain the server-resolved service zone');
select has_column('private', 'merchant_applications', 'provisioned_organization_id',
  'merchant applications link to their provisioned organization');
select has_column('private', 'merchant_applications', 'provisioned_branch_id',
  'merchant applications link to their provisioned branch');
select has_function('public', 'submit_merchant_application_v2',
  array['uuid', 'text', 'text', 'text', 'text', 'double precision',
    'double precision', 'text', 'text', 'text']);
select is(has_function_privilege('anon',
  'public.submit_merchant_application_v2(uuid,text,text,text,text,double precision,double precision,text,text,text)',
  'EXECUTE'), false, 'anonymous clients cannot submit applications directly');
select is(has_function_privilege('authenticated',
  'public.submit_merchant_application_v2(uuid,text,text,text,text,double precision,double precision,text,text,text)',
  'EXECUTE'), false, 'authenticated clients cannot impersonate the verified handler');
select is(has_function_privilege('service_role',
  'public.submit_merchant_application_v2(uuid,text,text,text,text,double precision,double precision,text,text,text)',
  'EXECUTE'), true, 'the authenticated Edge handler can submit applications');
select has_index('private', 'merchant_applications',
  'merchant_applications_service_zone_idx',
  'service-zone review queries are indexed');
select has_index('private', 'merchant_applications',
  'merchant_applications_provisioned_org_uidx',
  'an organization can provision only one application');
select has_index('private', 'merchant_applications',
  'merchant_applications_provisioned_branch_uidx',
  'a branch can provision only one application');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('59000000-0000-4000-8000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'onboarding-admin@example.test', '', now(), now(), now()),
  ('59000000-0000-4000-8000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'retail-applicant@example.test', '', now(), now(), now()),
  ('59000000-0000-4000-8000-000000000003',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'restaurant-applicant@example.test', '', now(), now(), now());

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
  ('59000000-0000-4000-8000-000000000001', 'Onboarding Admin', '+919590000001'),
  ('59000000-0000-4000-8000-000000000002', 'Retail Applicant', '+919590000002'),
  ('59000000-0000-4000-8000-000000000003', 'Restaurant Applicant', '+919590000003');

insert into private.account_memberships (account_id, role, approved_at) values
  ('59000000-0000-4000-8000-000000000001', 'owner', now()),
  ('59000000-0000-4000-8000-000000000002', 'customer', null),
  ('59000000-0000-4000-8000-000000000003', 'customer', null);

insert into public.service_zones (id, name, boundary, active) values (
  '59000000-0000-4000-8000-000000000010',
  'Complete onboarding test zone',
  extensions.st_geomfromtext(
    'POLYGON((78.50 12.50,78.50 12.80,78.80 12.80,78.80 12.50,78.50 12.50))',
    4326
  ), true
);

insert into storage.objects (bucket_id, name, owner_id) values
  ('dastak-evidence',
   'merchant/59000000-0000-4000-8000-000000000002/retail.pdf',
   '59000000-0000-4000-8000-000000000002'),
  ('dastak-evidence',
   'merchant/59000000-0000-4000-8000-000000000003/restaurant.pdf',
   '59000000-0000-4000-8000-000000000003');

select is((select response_body ->> 'status'
  from public.submit_merchant_application_v2(
    '59000000-0000-4000-8000-000000000002', 'RETAIL',
    'Retail Applicant Private Limited', 'North Street Market', '12 North Street',
    12.65, 78.65,
    'merchant/59000000-0000-4000-8000-000000000002/retail.pdf',
    'retail-submit', 'retail-submit-digest')),
  'pending', 'a complete retail application enters review');
select is((select response_body ->> 'merchantType'
  from public.submit_merchant_application_v2(
    '59000000-0000-4000-8000-000000000002', 'RETAIL',
    'Retail Applicant Private Limited', 'North Street Market', '12 North Street',
    12.65, 78.65,
    'merchant/59000000-0000-4000-8000-000000000002/retail.pdf',
    'retail-submit', 'retail-submit-digest')),
  'RETAIL', 'the business type is part of the idempotent response');
select is((select response_body ->> 'serviceZoneName'
  from public.submit_merchant_application_v2(
    '59000000-0000-4000-8000-000000000002', 'RETAIL',
    'Retail Applicant Private Limited', 'North Street Market', '12 North Street',
    12.65, 78.65,
    'merchant/59000000-0000-4000-8000-000000000002/retail.pdf',
    'retail-submit', 'retail-submit-digest')),
  'Complete onboarding test zone', 'the active service zone is resolved server-side');
select is((select legal_name from private.merchant_applications
  where account_id = '59000000-0000-4000-8000-000000000002'),
  'Retail Applicant Private Limited', 'legal identity is persisted');
select is((select extensions.st_y(location) from private.merchant_applications
  where account_id = '59000000-0000-4000-8000-000000000002'),
  12.65::double precision, 'store latitude is persisted');
select is((select extensions.st_x(location) from private.merchant_applications
  where account_id = '59000000-0000-4000-8000-000000000002'),
  78.65::double precision, 'store longitude is persisted');
select is((select response_body #>> '{error,code}'
  from public.submit_merchant_application_v2(
    '59000000-0000-4000-8000-000000000003', 'RESTAURANT_CAFE',
    'Restaurant Applicant LLP', 'Station Cafe', '1 Station Road',
    20.00, 75.00,
    'merchant/59000000-0000-4000-8000-000000000003/restaurant.pdf',
    'outside-submit', 'outside-submit-digest')),
  'outside_service_area', 'a branch outside an active service area is rejected');
select is((select applicant_name from public.list_merchant_applications(
  '59000000-0000-4000-8000-000000000001')),
  'Retail Applicant', 'Admin review receives the applicant identity');
select is((select applicant_phone from public.list_merchant_applications(
  '59000000-0000-4000-8000-000000000001')),
  '+919590000002', 'Admin review receives the mandatory contact number');

select is((select response_body ->> 'status'
  from public.review_merchant_application(
    '59000000-0000-4000-8000-000000000001',
    (select id from private.merchant_applications
      where account_id = '59000000-0000-4000-8000-000000000002'),
    'approve', null, 'retail-review', 'retail-review-digest')),
  'approved', 'Admin approval succeeds atomically');
select is((select count(*)::integer from dastak_v1.merchant_organizations
  where created_by = '59000000-0000-4000-8000-000000000002'),
  1, 'approval creates exactly one active merchant organization');
select is((select count(*)::integer from dastak_v1.merchant_branches branch
  join private.merchant_applications application
    on application.provisioned_branch_id = branch.id
  where application.account_id = '59000000-0000-4000-8000-000000000002'),
  1, 'approval creates the customer-facing branch');
select is((select count(*)::integer from dastak_v1.merchant_users
  where account_id = '59000000-0000-4000-8000-000000000002' and status = 'ACTIVE'),
  1, 'approval connects the applicant to the V1 merchant organization');
select is((select count(*)::integer from dastak_v1.merchant_permission_grants grant_row
  join dastak_v1.merchant_users merchant_user on merchant_user.id = grant_row.merchant_user_id
  where merchant_user.account_id = '59000000-0000-4000-8000-000000000002'
    and grant_row.bundle_id = '10000000-0000-4000-8000-000000000001'),
  1, 'approval grants the locked merchant-owner permission bundle');
select is((select state.is_open from dastak_v1.branch_operational_states state
  join private.merchant_applications application
    on application.provisioned_branch_id = state.branch_id
  where application.account_id = '59000000-0000-4000-8000-000000000002'),
  false, 'a newly approved branch starts closed');
select is((select state.accepting_orders from dastak_v1.branch_operational_states state
  join private.merchant_applications application
    on application.provisioned_branch_id = state.branch_id
  where application.account_id = '59000000-0000-4000-8000-000000000002'),
  false, 'a newly approved branch cannot accept orders before merchant activation');
select is((select count(*)::integer from private.account_memberships
  where account_id = '59000000-0000-4000-8000-000000000002'
    and role = 'merchant' and approved_at is not null),
  1, 'legacy app routing is connected to the same approval');
select ok((select response_body ->> 'organizationId' is not null
  from public.review_merchant_application(
    '59000000-0000-4000-8000-000000000001',
    (select id from private.merchant_applications
      where account_id = '59000000-0000-4000-8000-000000000002'),
    'approve', null, 'retail-review', 'retail-review-digest')),
  'an identical review replays the provisioned organization');
select is((select count(*)::integer from dastak_v1.merchant_organizations
  where created_by = '59000000-0000-4000-8000-000000000002'),
  1, 'review replay cannot duplicate the organization');
reset role;
select is((select count(*)::integer from audit.events
  where actor_id = '59000000-0000-4000-8000-000000000001'
    and action = 'merchant_application_reviewed'),
  1, 'the provisioning decision has one immutable audit record');
set local role service_role;

select is((select response_body ->> 'merchantType'
  from public.submit_merchant_application_v2(
    '59000000-0000-4000-8000-000000000003', 'RESTAURANT_CAFE',
    'Restaurant Applicant LLP', 'Station Cafe', '1 Station Road',
    12.66, 78.66,
    'merchant/59000000-0000-4000-8000-000000000003/restaurant.pdf',
    'restaurant-submit', 'restaurant-submit-digest')),
  'RESTAURANT_CAFE', 'restaurant and cafe onboarding uses the same complete contract');
select is((select response_body ->> 'status'
  from public.review_merchant_application(
    '59000000-0000-4000-8000-000000000001',
    (select id from private.merchant_applications
      where account_id = '59000000-0000-4000-8000-000000000003'),
    'reject', 'Business document needs a clearer legal name',
    'restaurant-review', 'restaurant-review-digest')),
  'rejected', 'Admin can return a restaurant application for correction');
select is((select count(*)::integer from dastak_v1.merchant_organizations
  where created_by = '59000000-0000-4000-8000-000000000003'),
  0, 'rejection never provisions a merchant organization');

select * from finish();
rollback;
