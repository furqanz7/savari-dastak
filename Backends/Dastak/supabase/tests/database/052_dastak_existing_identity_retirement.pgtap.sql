begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, phone, encrypted_password,
  email_confirmed_at, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('bc000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'founder@example.com', '919300000001', '',
   pg_catalog.now(), pg_catalog.now(), '{"provider":"google","providers":["google","phone"]}'::jsonb,
   '{}'::jsonb, pg_catalog.now(), pg_catalog.now()),
  ('bc000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'executive@example.com', '919300000002', '',
   pg_catalog.now(), pg_catalog.now(), '{"provider":"google","providers":["google","phone"]}'::jsonb,
   '{}'::jsonb, pg_catalog.now(), pg_catalog.now());

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bc000000-0000-4000-8000-000000000001', 'customer', 'Founder', '+919300000001',
  '+919300000001', 'founder-profile', 'founder-profile-digest')$$,
  'founder canonical identity and Customer persona are established');
select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bc000000-0000-4000-8000-000000000002', 'customer', 'Executive', '+919300000002',
  '+919300000002', 'executive-profile', 'executive-profile-digest')$$,
  'second canonical identity and Customer persona are established');
select lives_ok($$select dastak_v1_api.bootstrap_superadmin(
  'bc000000-0000-4000-8000-000000000001')$$,
  'exactly one immutable Superadmin is established');

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'bc000000-0000-4000-8000-000000000001', true
);
select lives_ok($$select dastak_v1_api.set_executive_admin(
  'bc000000-0000-4000-8000-000000000001'::uuid, 1::smallint,
  'executive@example.com', 1::bigint,
  'Identity retirement test')$$,
  'a replaceable Executive Admin is assigned before retirement');

insert into private.merchant_applications (
  account_id, business_name, business_address, evidence_object_path
) values (
  'bc000000-0000-4000-8000-000000000002',
  'Pending shop', 'Pending address', 'private/pending-evidence'
);

select lives_ok($$select private.retire_existing_dastak_personas()$$,
  'owner-authorized retirement completes when no active work exists');
select is((select pg_catalog.count(*) from dastak_v1.admin_role_assignments assignment
  where assignment.slot = 0 and assignment.account_id =
    'bc000000-0000-4000-8000-000000000001'), 1::bigint,
  'the immutable Superadmin assignment is preserved');
select is((select pg_catalog.count(*) from dastak_v1.admin_role_assignments assignment
  where assignment.slot in (1, 2) and assignment.email_normalized is not null), 0::bigint,
  'both replaceable Executive Admin slots are cleared');
select is((select pg_catalog.count(*) from private.account_personas persona
  where persona.state = 'ACTIVE'), 0::bigint,
  'every existing Customer, Merchant and Delivery persona is retired');
select is((select state::text from private.account_personas persona
  where persona.account_id = 'bc000000-0000-4000-8000-000000000001'
    and persona.persona = 'CUSTOMER'), 'DELETED',
  'Superadmin Customer is separate and is retired without changing Admin');
select ok(exists (
  select 1 from private.account_memberships membership
  where membership.account_id = 'bc000000-0000-4000-8000-000000000001'
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now())
), 'Superadmin owner membership remains active');
select is((select pg_catalog.count(*) from private.account_memberships membership
  where membership.account_id = 'bc000000-0000-4000-8000-000000000002'
    and membership.role = 'owner'), 0::bigint,
  'retired Executive Admin owner capability is removed');
select is((select status from private.merchant_applications application
  where application.account_id = 'bc000000-0000-4000-8000-000000000002'), 'rejected',
  'pending onboarding is retained as reviewed history and can be resubmitted');
select is((select claim_state::text from private.account_phone_claims claim
  where claim.account_id = 'bc000000-0000-4000-8000-000000000001'), 'ACTIVE',
  'Superadmin phone remains bound to the immutable Admin identity');
select is((select claim_state::text from private.account_phone_claims claim
  where claim.account_id = 'bc000000-0000-4000-8000-000000000002'), 'RECOVERY_ELIGIBLE',
  'fully retired non-Admin phone becomes recovery eligible');
select is((select phone from auth.users auth_user
  where auth_user.id = 'bc000000-0000-4000-8000-000000000002'), null,
  'retired identity releases its verified Auth phone without deleting history');
select is((select phone from auth.users auth_user
  where auth_user.id = 'bc000000-0000-4000-8000-000000000001'), '919300000001',
  'Superadmin Auth phone is not changed by persona retirement');

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bc000000-0000-4000-8000-000000000002', 'customer', 'Executive recovered',
  '+919300000002', '+919300000002', 'same-email-recovery', 'same-email-recovery-digest')$$,
  'same-email sign-in can recover only the selected persona after phone verification');
select is((select state::text from private.account_personas persona
  where persona.account_id = 'bc000000-0000-4000-8000-000000000002'
    and persona.persona = 'CUSTOMER'), 'ACTIVE',
  'same-email recovery restores the selected Customer persona');
select is((select pg_catalog.count(*) from dastak_v1.admin_role_assignments assignment
  where assignment.account_id = 'bc000000-0000-4000-8000-000000000002'), 0::bigint,
  'persona recovery never restores a former Admin assignment');

select * from finish();
rollback;
