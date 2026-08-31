begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege('authenticated', 'public.dastak_v1_admin_command_center()', 'EXECUTE'),
  true,
  'authenticated Admin sessions can reach the permission-bound command center wrapper'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_admin_network_page(text,text,text,integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  true,
  'authenticated Admin sessions can reach the permission-bound network wrapper'
);
select is(
  has_function_privilege('anon', 'public.dastak_v1_admin_command_center()', 'EXECUTE'),
  false,
  'anonymous sessions cannot execute the Admin command center'
);
select is(
  has_table_privilege('authenticated', 'private.account_personas', 'SELECT'),
  false,
  'Admin clients cannot bypass the safe directory to read raw persona rows'
);
select is(
  has_table_privilege('authenticated', 'private.merchant_applications', 'SELECT'),
  false,
  'Admin clients cannot read raw merchant evidence-bearing applications'
);
select is(
  has_table_privilege('authenticated', 'private.delivery_partner_applications', 'SELECT'),
  false,
  'Admin clients cannot read raw Delivery Partner evidence-bearing applications'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.catalogue_source_brand_aliases', 'SELECT'),
  false,
  'Admin clients cannot read raw source brand-alias rules'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.catalogue_source_taxonomy_rules', 'SELECT'),
  false,
  'Admin clients cannot read raw source taxonomy rules'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    'ad000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'command-superadmin@example.com', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ad000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'command-executive@example.com', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ad000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'command-outsider@example.com', '',
    pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
    pg_catalog.now(), pg_catalog.now()
  );

insert into public.accounts (id, display_name, phone_number, account_state) values
  ('ad000000-0000-4000-8000-000000000001', 'Command Superadmin', '+919200000001', 'ACTIVE'),
  ('ad000000-0000-4000-8000-000000000002', 'Command Executive', '+919200000002', 'ACTIVE'),
  ('ad000000-0000-4000-8000-000000000003', 'Command Outsider', '+919200000003', 'ACTIVE');

insert into private.account_memberships (account_id, role) values
  ('ad000000-0000-4000-8000-000000000001', 'customer'),
  ('ad000000-0000-4000-8000-000000000002', 'customer'),
  ('ad000000-0000-4000-8000-000000000003', 'customer');

insert into private.account_personas (account_id, persona) values
  ('ad000000-0000-4000-8000-000000000002', 'MERCHANT'),
  ('ad000000-0000-4000-8000-000000000003', 'DELIVERY');

insert into private.merchant_applications (
  account_id, business_name, business_address, evidence_object_path
) values (
  'ad000000-0000-4000-8000-000000000002',
  'Command Store', '1 Admin Avenue', 'merchant-applications/command/evidence.jpg'
);
insert into private.delivery_partner_applications (
  account_id, delivery_method, identity_evidence_object_path
) values (
  'ad000000-0000-4000-8000-000000000003',
  'bicycle', 'delivery-applications/command/identity.jpg'
);

select lives_ok(
  $$select dastak_v1_api.bootstrap_superadmin(
    'ad000000-0000-4000-8000-000000000001'
  )$$,
  'the test founder can establish the immutable Superadmin assignment'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'ad000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_set_executive_admin(
    1::smallint,
    'command-executive@example.com',
    1::bigint,
    'Bind the first Executive Admin for command-center parity testing.'
  )$$,
  'the Superadmin can bind an Executive Admin before parity checks'
);
select lives_ok(
  $$select public.dastak_v1_admin_command_center()$$,
  'the Superadmin can load the complete command center'
);
select is(
  pg_catalog.jsonb_typeof(public.dastak_v1_admin_command_center()->'actionQueue'),
  'object',
  'the command center returns a structured action queue'
);
select ok(
  (public.dastak_v1_admin_command_center()->'actionQueue'->>'merchantApplications')::bigint >= 1,
  'pending merchant onboarding is connected to the Admin action queue'
);
select ok(
  (public.dastak_v1_admin_command_center()->'actionQueue'->>'deliveryApplications')::bigint >= 1,
  'pending Delivery Partner onboarding is connected to the Admin action queue'
);
select is(
  pg_catalog.jsonb_array_length(
    public.dastak_v1_admin_network_page(
      'command-executive@example.com', 'MERCHANT', 'ACTIVE', 20, null, null
    )->'people'
  ),
  1,
  'the safe network directory joins the matching independent Merchant persona'
);
select lives_ok(
  $$select public.dastak_v1_admin_catalogue_page(
    null, null, null, null, null, null, 1, null, null
  )$$,
  'the Superadmin can load the governed exact-SKU catalogue page'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.admin_catalogue_page(uuid,text,uuid,uuid,uuid,text,text,integer,text,uuid)'::regprocedure
  ),
  'activationReady[\s\S]*activationBlockers',
  'the installed catalogue projection exposes database-authoritative activation readiness'
);
select is(
  public.dastak_v1_admin_network_page(
    'command-executive@example.com', 'MERCHANT', 'ACTIVE', 20, null, null
  )->'people'->0->>'displayName',
  'Command Executive',
  'the directory exposes the intended safe identity summary'
);
select is(
  public.dastak_v1_admin_network_page(
    'command-executive@example.com', 'MERCHANT', 'ACTIVE', 20, null, null
  )->'people'->0->'merchant'->>'businessName',
  'Command Store',
  'the directory connects Merchant application state without exposing evidence paths'
);
select is(
  public.dastak_v1_admin_network_page(
    'command-executive@example.com', 'MERCHANT', 'ACTIVE', 20, null, null
  )->'people'->0->'merchant' ? 'evidenceObjectPath',
  false,
  'the network projection excludes private Merchant evidence locations'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'ad000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select lives_ok(
  $$select public.dastak_v1_admin_command_center()$$,
  'an Executive Admin has the same operational command-center visibility'
);
select lives_ok(
  $$select public.dastak_v1_admin_network_page(
    null, 'DELIVERY', 'ACTIVE', 20, null, null
  )$$,
  'an Executive Admin has the same connected-network visibility'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'ad000000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select throws_ok(
  $$select public.dastak_v1_admin_command_center()$$,
  '42501',
  'platform permission required',
  'an ordinary authenticated account cannot read Admin operating state'
);
select throws_ok(
  $$select public.dastak_v1_admin_network_page(null, null, null, 20, null, null)$$,
  '42501',
  'platform permission required',
  'an ordinary authenticated account cannot enumerate marketplace identities'
);
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'ad000000-0000-4000-8000-000000000001', true
);
select throws_ok(
  $$select dastak_v1_api.admin_network_page(
    'ad000000-0000-4000-8000-000000000001',
    null, 'OWNER', null, 20, null, null
  )$$,
  '22023',
  'invalid persona filter',
  'the database rejects unsupported persona filters independently of Edge validation'
);
select throws_ok(
  $$select dastak_v1_api.admin_network_page(
    'ad000000-0000-4000-8000-000000000001',
    null, null, null, 20, pg_catalog.now(), null
  )$$,
  '22023',
  'complete network cursor required',
  'the database rejects partial cursors independently of Edge validation'
);

select * from finish();
rollback;
