begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('private', 'account_personas',
  'Dastak stores independent Customer, Merchant and Delivery personas');
select has_table('private', 'account_phone_claims',
  'Dastak stores one canonical verified-phone claim per identity');
select is((select relrowsecurity from pg_catalog.pg_class where oid =
  'private.account_personas'::regclass), true, 'persona authority enforces RLS');
select is(has_table_privilege('authenticated', 'private.account_personas', 'SELECT'), false,
  'clients cannot read the raw persona authority');
select is(has_function_privilege('authenticated',
  'public.prepare_dastak_persona_deletion(uuid,text,text)', 'EXECUTE'), false,
  'clients cannot forge persona deletion around the authenticated Edge boundary');
select is(has_function_privilege('authenticated',
  'public.dastak_identity_retirement_inventory()', 'EXECUTE'), false,
  'only the service boundary can read the sanitized retirement inventory');

insert into auth.users (
  id, instance_id, aud, role, email, phone, encrypted_password,
  email_confirmed_at, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('bb000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'customer@example.com', '+919200000001', '',
   pg_catalog.now(), pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
   pg_catalog.now(), pg_catalog.now()),
  ('bb000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'merchant@example.com', '+919200000002', '',
   pg_catalog.now(), pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
   pg_catalog.now(), pg_catalog.now()),
  ('bb000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'delivery@example.com', '+919200000003', '',
   pg_catalog.now(), pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
   pg_catalog.now(), pg_catalog.now()),
  ('bb000000-0000-4000-8000-000000000004', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'admin@example.com', '+919200000004', '',
   pg_catalog.now(), pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
   pg_catalog.now(), pg_catalog.now()),
  ('bb000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'recovery@example.com', '+919200000005', '',
   pg_catalog.now(), pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
   pg_catalog.now(), pg_catalog.now()),
  ('bb000000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'superadmin-personas@example.com', '+919200000006', '',
   pg_catalog.now(), pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
   pg_catalog.now(), pg_catalog.now()),
  ('bb000000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'old-recovery@example.com', '+919200000007', '',
   pg_catalog.now(), pg_catalog.now(), '{"provider":"google","providers":["google"]}'::jsonb, '{}'::jsonb,
   pg_catalog.now(), pg_catalog.now());

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000001', 'customer', 'Customer', '+919200000001',
  '+919200000001', 'customer-bootstrap', 'customer-digest')$$,
  'Customer bootstrap accepts only the explicitly requested persona');
select is((select pg_catalog.count(*) from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000001'), 1::bigint,
  'Customer bootstrap creates exactly one persona');
select is((select persona::text from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000001'), 'CUSTOMER',
  'Customer bootstrap does not create Merchant or Delivery');

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000002', 'merchant', 'Merchant', '+919200000002',
  '+919200000002', 'merchant-bootstrap', 'merchant-digest')$$,
  'Merchant app bootstrap creates the base identity before onboarding');
select is((select pg_catalog.count(*) from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000002'), 0::bigint,
  'Merchant persona is not created before mandatory Merchant onboarding and approval');
select is((select pg_catalog.count(*) from private.account_memberships
  where account_id = 'bb000000-0000-4000-8000-000000000002'), 0::bigint,
  'Merchant bootstrap does not manufacture Customer or Merchant membership');

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000003', 'delivery', 'Delivery', '+919200000003',
  '+919200000003', 'delivery-bootstrap', 'delivery-digest')$$,
  'Delivery app bootstrap creates the base identity before onboarding');
select is((select pg_catalog.count(*) from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000003'), 0::bigint,
  'Delivery persona is not created before mandatory Delivery onboarding and approval');

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000004', 'admin', 'Admin', '+919200000004',
  '+919200000004', 'admin-bootstrap', 'admin-digest')$$,
  'Admin bootstrap creates only a canonical identity');
select is((select pg_catalog.count(*) from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000004'), 0::bigint,
  'Admin bootstrap does not auto-create a Customer, Merchant or Delivery persona');
select is((select route from public.resolve_app_access(
  'bb000000-0000-4000-8000-000000000004', 'admin')), 'access_denied',
  'an unassigned signed-in identity cannot enter Admin');

select is((select response_status from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000005', 'customer', 'Recovery', '+919200000001',
  '+919200000001', 'collision', 'collision-digest')), 409,
  'an active verified phone cannot be claimed by a second identity');
select is((select response_body #>> '{error,code}' from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000005', 'customer', 'Recovery', '+919200000001',
  '+919200000001', 'collision', 'collision-digest')), 'phone_number_in_use',
  'active phone collision returns a stable safe error');

insert into private.account_memberships (account_id, role, approved_at) values
  ('bb000000-0000-4000-8000-000000000001', 'merchant', pg_catalog.now()),
  ('bb000000-0000-4000-8000-000000000001', 'dastak_partner', pg_catalog.now());
select is((select pg_catalog.count(*) from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000001' and state = 'ACTIVE'), 3::bigint,
  'one identity can independently hold all three personas after onboarding');

select lives_ok($$select public.prepare_dastak_persona_deletion(
  'bb000000-0000-4000-8000-000000000001', 'MERCHANT', 'delete-merchant')$$,
  'Merchant persona can be deleted independently');
select is((select state::text from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000001' and persona = 'MERCHANT'),
  'DELETED', 'only Merchant is deleted');
select is((select pg_catalog.count(*) from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000001'
    and persona in ('CUSTOMER', 'DELIVERY') and state = 'ACTIVE'), 2::bigint,
  'Customer and Delivery remain active after Merchant deletion');
select is((select claim_state::text from private.account_phone_claims
  where account_id = 'bb000000-0000-4000-8000-000000000001'), 'ACTIVE',
  'phone remains reserved while any persona remains active');

select lives_ok($$select public.prepare_dastak_persona_deletion(
  'bb000000-0000-4000-8000-000000000001', 'CUSTOMER', 'delete-customer')$$,
  'Customer can be deleted without deleting Delivery');
select lives_ok($$select public.prepare_dastak_persona_deletion(
  'bb000000-0000-4000-8000-000000000001', 'DELIVERY', 'delete-delivery')$$,
  'the final persona can be deleted');
select is((select claim_state::text from private.account_phone_claims
  where account_id = 'bb000000-0000-4000-8000-000000000001'), 'RECOVERY_ELIGIBLE',
  'phone transfer becomes eligible only after every persona is deleted');
select is((select phone from auth.users
  where id = 'bb000000-0000-4000-8000-000000000001'), null,
  'fully deleting every persona releases the phone from Supabase Auth');

select is((select response_body #>> '{error,code}' from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000005', 'customer', 'Recovery', '+919200000001',
  '+919200000001', 'recovery', 'recovery-digest')), 'identity_recovery_required',
  'a newly verified email is routed to canonical identity recovery for the fully deleted phone');

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000001', 'customer', 'Customer', '+919200000001',
  '+919200000001', 'recover-customer', 'recover-customer-digest')$$,
  'the same canonical identity can recover only the selected deleted persona');
select is((select state::text from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000001' and persona = 'CUSTOMER'),
  'ACTIVE', 'selected Customer persona is recovered');
select is((select pg_catalog.count(*) from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000001'
    and persona in ('MERCHANT', 'DELIVERY') and state = 'ACTIVE'), 0::bigint,
  'recovering Customer does not recreate Merchant or Delivery');

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000006', 'customer', 'Superadmin', '+919200000006',
  '+919200000006', 'superadmin-customer', 'superadmin-digest')$$,
  'Superadmin may independently onboard Customer');
select lives_ok($$select dastak_v1_api.bootstrap_superadmin(
  'bb000000-0000-4000-8000-000000000006')$$,
  'the one immutable Superadmin assignment can be established');
select lives_ok($$select public.prepare_dastak_persona_deletion(
  'bb000000-0000-4000-8000-000000000006', 'CUSTOMER', 'superadmin-delete-customer')$$,
  'Superadmin may delete only the independent Customer persona');
select is((select claim_state::text from private.account_phone_claims
  where account_id = 'bb000000-0000-4000-8000-000000000006'), 'ACTIVE',
  'immutable Superadmin assignment keeps the canonical identity and phone active');
select is((select (public.dastak_identity_retirement_inventory()
  ->> 'superadminAssignments')::bigint), 1::bigint,
  'retirement inventory proves exactly one immutable Superadmin assignment');

select lives_ok($$select * from public.bootstrap_dastak_persona(
  'bb000000-0000-4000-8000-000000000007', 'customer', 'Old identity', '+919200000007',
  '+919200000007', 'old-recovery-bootstrap', 'old-recovery-digest')$$,
  'a canonical identity is established before new-email recovery');
insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
values ('old-google-subject', 'bb000000-0000-4000-8000-000000000007',
  '{"sub":"old-google-subject","email":"old-recovery@example.com"}', 'google',
  pg_catalog.now(), pg_catalog.now()),
  ('919200000007', 'bb000000-0000-4000-8000-000000000007',
  '{"sub":"919200000007","phone":"+919200000007"}', 'phone',
  pg_catalog.now(), pg_catalog.now());
select lives_ok($$select public.prepare_dastak_persona_deletion(
  'bb000000-0000-4000-8000-000000000007', 'CUSTOMER', 'delete-for-new-email')$$,
  'fully deleted canonical identity can prepare for a new verified email');

insert into auth.users (
  id, instance_id, aud, role, email, phone, encrypted_password,
  email_confirmed_at, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values (
  'bb000000-0000-4000-8000-000000000008', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'new-recovery@example.com', '919200000007', '',
  pg_catalog.now(), pg_catalog.now(), '{"provider":"google","providers":["google","phone"]}'::jsonb,
  '{"full_name":"Recovered identity"}'::jsonb, pg_catalog.now(), pg_catalog.now()
);
insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
values ('new-google-subject', 'bb000000-0000-4000-8000-000000000008',
  '{"sub":"new-google-subject","email":"new-recovery@example.com"}', 'google',
  pg_catalog.now(), pg_catalog.now()),
  ('919200000007', 'bb000000-0000-4000-8000-000000000008',
  '{"sub":"919200000007","phone":"+919200000007"}', 'phone',
  pg_catalog.now(), pg_catalog.now());

select lives_ok($$select public.complete_dastak_identity_recovery(
  public.prepare_dastak_identity_recovery(
    'bb000000-0000-4000-8000-000000000008',
    'bb000000-0000-4000-8000-000000000007',
    '+919200000007',
    pg_catalog.encode(extensions.digest('new-recovery@example.com', 'sha256'), 'hex'),
    'customer', 'Recovered identity', 'new-recovery-bootstrap-digest'
  ), true, null)$$,
  'new verified email and phone identities transfer to the canonical Dastak identity');
select is((select pg_catalog.count(*) from auth.users
  where id = 'bb000000-0000-4000-8000-000000000008'), 0::bigint,
  'temporary recovery Auth user is removed');
select is((select email from auth.users
  where id = 'bb000000-0000-4000-8000-000000000007'), 'new-recovery@example.com',
  'canonical identity adopts the newly verified email');
select is((select phone from auth.users
  where id = 'bb000000-0000-4000-8000-000000000007'), '919200000007',
  'canonical identity regains the verified phone after recovery');
select is((select pg_catalog.string_agg(provider, ',' order by provider)
  from auth.identities where user_id = 'bb000000-0000-4000-8000-000000000007'), 'google,phone',
  'canonical identity receives only the newly verified sign-in identities');
select is((select pg_catalog.count(*)
  from private.customer_auth_identities identity
  join auth.identities auth_identity
    on auth_identity.user_id = identity.account_id
    and auth_identity.provider = identity.provider
    and identity.provider_subject_digest = extensions.digest(auth_identity.provider_id, 'sha256')
  where identity.account_id = 'bb000000-0000-4000-8000-000000000007'
    and identity.revoked_at is null), 1::bigint,
  'new-email recovery keeps the custom token hook registry aligned with the transferred OAuth identity');
select is((select claim_state::text from private.account_phone_claims
  where account_id = 'bb000000-0000-4000-8000-000000000007'), 'ACTIVE',
  'successful identity transfer reactivates the canonical phone claim');
select is((select state::text from private.account_personas
  where account_id = 'bb000000-0000-4000-8000-000000000007' and persona = 'CUSTOMER'),
  'ACTIVE', 'new-email recovery reactivates only the selected Customer persona');

select * from finish();
rollback;
