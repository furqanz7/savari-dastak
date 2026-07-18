begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table('private', 'controlled_category_policies', 'controlled-category policies are private');
select has_table('private', 'controlled_store_compliance', 'store compliance is private');
select has_table('private', 'adult_attestations', 'adult attestations are private');
select has_table('private', 'restricted_exclusion_zones', 'restricted exclusion zones are private');
select has_table('private', 'prescription_evidence', 'prescription evidence is private');
select has_table('private', 'restricted_handoff_events', 'restricted handoff evidence is private');
select has_table('private', 'restricted_return_confirmations', 'restricted return evidence is private');
select has_column('private', 'catalogue_products', 'requires_prescription', 'prescription requirement is stored');
select has_column('private', 'catalogue_products', 'restricted_tobacco_kind', 'tobacco kind is stored');
select is(
  has_table_privilege('authenticated', 'private.catalogue_products', 'SELECT'),
  false,
  'customers cannot bypass controlled catalogue functions'
);
select is(
  has_table_privilege('authenticated', 'private.adult_attestations', 'INSERT'),
  false,
  'customers cannot forge adult attestations directly'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.verify_restricted_handoff(uuid,uuid,text,text,text,text,text)',
    'EXECUTE'
  ),
  false,
  'partners cannot bypass the controlled-category Edge Function'
);
select is(
  has_function_privilege(
    'service_role',
    'public.verify_restricted_handoff(uuid,uuid,text,text,text,text,text)',
    'EXECUTE'
  ),
  true,
  'verified server requests can perform restricted handoff'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '93000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'controlled-owner@example.test', '',
  now(), now(), now()
),
(
  '93000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'controlled-merchant@example.test', '',
  now(), now(), now()
),
(
  '93000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'controlled-customer@example.test', '',
  now(), now(), now()
),
(
  '93000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'controlled-partner@example.test', '',
  now(), now(), now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
  ('93000000-0000-4000-8000-000000000001', 'Controlled Owner', '+919300000001'),
  ('93000000-0000-4000-8000-000000000002', 'Controlled Merchant', '+919300000002'),
  ('93000000-0000-4000-8000-000000000003', 'Controlled Customer', '+919300000003'),
  ('93000000-0000-4000-8000-000000000004', 'Controlled Partner', '+919300000004');

insert into private.account_memberships (account_id, role, approved_at) values
  ('93000000-0000-4000-8000-000000000001', 'owner', now()),
  ('93000000-0000-4000-8000-000000000002', 'merchant', now()),
  ('93000000-0000-4000-8000-000000000003', 'customer', null),
  ('93000000-0000-4000-8000-000000000004', 'dastak_partner', now());

insert into public.service_zones (id, name, boundary, active) values (
  '93000000-0000-4000-8000-000000000010',
  'Controlled Category Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.55 12.60,78.55 12.75,78.75 12.75,78.75 12.60,78.55 12.60))',
    4326
  ),
  true
);

insert into private.merchant_stores (
  id, merchant_account_id, service_zone_id, name, address, location,
  is_published, accepting_orders
) values (
  '93000000-0000-4000-8000-000000000020',
  '93000000-0000-4000-8000-000000000002',
  '93000000-0000-4000-8000-000000000010',
  'Controlled Store', '1 Test Road',
  extensions.st_setsrid(extensions.st_makepoint(78.6200, 12.6800), 4326),
  true, true
);

insert into private.catalogue_categories (id, store_id, name, display_order, is_active)
values (
  '93000000-0000-4000-8000-000000000030',
  '93000000-0000-4000-8000-000000000020',
  'Controlled Products', 1, true
);

insert into private.catalogue_products (
  id, store_id, category_id, name, unit_label, price_paise,
  availability, catalogue_kind, restricted_approval_state,
  requires_prescription, restricted_tobacco_kind, is_active
) values
(
  '93000000-0000-4000-8000-000000000041',
  '93000000-0000-4000-8000-000000000020',
  '93000000-0000-4000-8000-000000000030',
  'OTC Medicine', '1 pack', 5000, 'in_stock', 'otc_medicine',
  'pending', false, null, true
),
(
  '93000000-0000-4000-8000-000000000042',
  '93000000-0000-4000-8000-000000000020',
  '93000000-0000-4000-8000-000000000030',
  'Prescription Medicine', '1 strip', 10000, 'in_stock',
  'prescription_medicine', 'pending', true, null, true
),
(
  '93000000-0000-4000-8000-000000000043',
  '93000000-0000-4000-8000-000000000020',
  '93000000-0000-4000-8000-000000000030',
  'Cigarettes', '20 pieces', 20000, 'in_stock', 'paan_corner',
  'pending', false, null, true
),
(
  '93000000-0000-4000-8000-000000000044',
  '93000000-0000-4000-8000-000000000020',
  '93000000-0000-4000-8000-000000000030',
  'Unapproved Cigarettes', '10 pieces', 12000, 'in_stock', 'paan_corner',
  'pending', false, 'cigarette', true
);

insert into storage.objects (bucket_id, name, owner_id) values
(
  'dastak-evidence',
  'pharmacy/93000000-0000-4000-8000-000000000002/licence.pdf',
  '93000000-0000-4000-8000-000000000002'
),
(
  'dastak-evidence',
  'prescription/93000000-0000-4000-8000-000000000003/rx.pdf',
  '93000000-0000-4000-8000-000000000003'
);

select is(
  (
    select response_status
    from public.upsert_controlled_category_policy(
      '93000000-0000-4000-8000-000000000001',
      'controlled-v1', '["cigarette"]', true,
      'policy-1', 'policy-digest-1'
    )
  ),
  201,
  'owner activates an immutable 18+ policy'
);

select is(
  (
    select response_status
    from public.submit_controlled_store_compliance(
      '93000000-0000-4000-8000-000000000002', 'medicine',
      'pharmacy/93000000-0000-4000-8000-000000000002/licence.pdf',
      'medicine-compliance-1', 'medicine-compliance-digest-1'
    )
  ),
  200,
  'merchant submits pharmacy licence evidence'
);

select is(
  (
    select response_status
    from public.review_controlled_store_compliance(
      '93000000-0000-4000-8000-000000000001',
      (
        select id from private.controlled_store_compliance
        where store_id = '93000000-0000-4000-8000-000000000020'
          and scope = 'medicine'
      ),
      'approve', now() + interval '1 year', null,
      'medicine-review-1', 'medicine-review-digest-1'
    )
  ),
  200,
  'owner approves current pharmacy compliance'
);

select is(
  (
    select response_status
    from public.submit_controlled_store_compliance(
      '93000000-0000-4000-8000-000000000002', 'tobacco', null,
      'tobacco-compliance-1', 'tobacco-compliance-digest-1'
    )
  ),
  200,
  'merchant submits tobacco compliance for owner review'
);

select is(
  (
    select response_status
    from public.review_controlled_store_compliance(
      '93000000-0000-4000-8000-000000000001',
      (
        select id from private.controlled_store_compliance
        where store_id = '93000000-0000-4000-8000-000000000020'
          and scope = 'tobacco'
      ),
      'approve', null, null,
      'tobacco-review-1', 'tobacco-review-digest-1'
    )
  ),
  200,
  'owner approves the tobacco merchant'
);

select is(
  (
    select response_status
    from public.upsert_merchant_order_financial_rate_card(
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000010',
      4000, 1000, 3000, true,
      'controlled-rate-1', 'controlled-rate-digest-1'
    )
  ),
  200,
  'owner configures server checkout and courier amounts'
);

select is(
  (
    select response_status
    from public.submit_controlled_product(
      '93000000-0000-4000-8000-000000000002',
      '93000000-0000-4000-8000-000000000041', null,
      'submit-otc-1', 'submit-otc-digest-1'
    )
  ),
  200,
  'merchant submits OTC medicine'
);
select is(
  (
    select response_status
    from public.review_controlled_product(
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000041', 'approve', null,
      'review-otc-1', 'review-otc-digest-1'
    )
  ),
  200,
  'owner approves OTC medicine'
);
select is(
  (
    select response_status
    from public.submit_controlled_product(
      '93000000-0000-4000-8000-000000000002',
      '93000000-0000-4000-8000-000000000042', null,
      'submit-rx-1', 'submit-rx-digest-1'
    )
  ),
  200,
  'merchant submits prescription medicine'
);
select is(
  (
    select response_status
    from public.review_controlled_product(
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000042', 'approve', null,
      'review-rx-1', 'review-rx-digest-1'
    )
  ),
  200,
  'owner approves prescription medicine'
);
select is(
  (
    select response_status
    from public.submit_controlled_product(
      '93000000-0000-4000-8000-000000000002',
      '93000000-0000-4000-8000-000000000043', 'cigarette',
      'submit-tobacco-1', 'submit-tobacco-digest-1'
    )
  ),
  200,
  'merchant submits an allowed non-electronic tobacco kind'
);
select is(
  (
    select response_status
    from public.review_controlled_product(
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000043', 'approve', null,
      'review-tobacco-1', 'review-tobacco-digest-1'
    )
  ),
  200,
  'owner approves the allowed tobacco product'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_controlled_merchant_order(
      '93000000-0000-4000-8000-000000000003', 'medicine',
      '93000000-0000-4000-8000-000000000020',
      '[{"productId":"93000000-0000-4000-8000-000000000042","quantity":1}]',
      12.6900, 78.6400, null,
      'quote-rx-missing', 'quote-rx-missing-digest'
    )
  ),
  'prescription_required',
  'prescription medicine fails closed without evidence'
);

select is(
  (
    select response_status
    from public.quote_controlled_merchant_order(
      '93000000-0000-4000-8000-000000000003', 'medicine',
      '93000000-0000-4000-8000-000000000020',
      '[{"productId":"93000000-0000-4000-8000-000000000042","quantity":1}]',
      12.6900, 78.6400,
      'prescription/93000000-0000-4000-8000-000000000003/rx.pdf',
      'quote-rx-ok', 'quote-rx-ok-digest'
    )
  ),
  200,
  'prescription medicine succeeds with owned uploaded evidence'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_controlled_merchant_order(
      '93000000-0000-4000-8000-000000000003', 'tobacco',
      '93000000-0000-4000-8000-000000000020',
      '[{"productId":"93000000-0000-4000-8000-000000000043","quantity":1}]',
      12.6900, 78.6400, null,
      'quote-tobacco-no-attestation', 'quote-tobacco-no-attestation-digest'
    )
  ),
  'adult_attestation_required',
  'tobacco checkout requires current adult terms'
);

select is(
  (
    select response_status
    from public.record_adult_attestation(
      '93000000-0000-4000-8000-000000000003', 'controlled-v1',
      true, true, 'attest-1', 'attest-digest-1'
    )
  ),
  200,
  'customer records both adult-use confirmations'
);

create temporary table controlled_test_state (
  name text primary key,
  value uuid not null
) on commit drop;

insert into controlled_test_state (name, value)
select 'exclusion', (response_body ->> 'zoneId')::uuid
from public.upsert_restricted_exclusion_zone(
  '93000000-0000-4000-8000-000000000001', null,
  'Test School', 'school', 12.6900, 78.6400, 150, true,
  'exclusion-1', 'exclusion-digest-1'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_controlled_merchant_order(
      '93000000-0000-4000-8000-000000000003', 'tobacco',
      '93000000-0000-4000-8000-000000000020',
      '[{"productId":"93000000-0000-4000-8000-000000000043","quantity":1}]',
      12.6900, 78.6400, null,
      'quote-tobacco-excluded', 'quote-tobacco-excluded-digest'
    )
  ),
  'restricted_location_prohibited',
  'school and college exclusion zones are server enforced'
);

select is(
  (
    select response_status
    from public.upsert_restricted_exclusion_zone(
      '93000000-0000-4000-8000-000000000001',
      (select value from controlled_test_state where name = 'exclusion'),
      'Test School', 'school', 12.6900, 78.6400, 150, false,
      'exclusion-2', 'exclusion-digest-2'
    )
  ),
  200,
  'owner can deactivate a reviewed exclusion zone'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.quote_controlled_merchant_order(
      '93000000-0000-4000-8000-000000000003', 'tobacco',
      '93000000-0000-4000-8000-000000000020',
      '[{"productId":"93000000-0000-4000-8000-000000000044","quantity":1}]',
      12.6900, 78.6400, null,
      'quote-tobacco-unapproved', 'quote-tobacco-unapproved-digest'
    )
  ),
  'restricted_product_unavailable',
  'unapproved controlled products cannot enter checkout'
);

insert into controlled_test_state (name, value)
select 'quote-return', (response_body ->> 'quoteId')::uuid
from public.quote_controlled_merchant_order(
  '93000000-0000-4000-8000-000000000003', 'tobacco',
  '93000000-0000-4000-8000-000000000020',
  '[{"productId":"93000000-0000-4000-8000-000000000043","quantity":1}]',
  12.6900, 78.6400, null,
  'quote-tobacco-return', 'quote-tobacco-return-digest'
);

select is(
  (
    select (response_body #>> '{itemSubtotal,paise}')::bigint
    from public.quote_controlled_merchant_order(
      '93000000-0000-4000-8000-000000000003', 'tobacco',
      '93000000-0000-4000-8000-000000000020',
      '[{"productId":"93000000-0000-4000-8000-000000000043","quantity":1}]',
      12.6900, 78.6400, null,
      'quote-tobacco-return', 'quote-tobacco-return-digest'
    )
  ),
  20000::bigint,
  'controlled checkout snapshots the server product price'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.create_merchant_order(
      '93000000-0000-4000-8000-000000000003',
      (select value from controlled_test_state where name = 'quote-return'),
      'ordinary-create-blocked', 'ordinary-create-blocked-digest'
    )
  ),
  'catalogue_changed',
  'ordinary checkout cannot consume a controlled quote'
);

insert into controlled_test_state (name, value)
select 'order-return', (response_body ->> 'orderId')::uuid
from public.create_controlled_merchant_order(
  '93000000-0000-4000-8000-000000000003',
  (select value from controlled_test_state where name = 'quote-return'),
  'controlled-create-return', 'controlled-create-return-digest'
);

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  status, reviewed_at, reviewed_by
) values (
  '93000000-0000-4000-8000-000000000050',
  '93000000-0000-4000-8000-000000000004', 'bike',
  'dastak-partner/93000000-0000-4000-8000-000000000004/identity.pdf',
  'approved', now(), '93000000-0000-4000-8000-000000000001'
);
insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values (
  '93000000-0000-4000-8000-000000000004',
  '93000000-0000-4000-8000-000000000050', 'bike'
);

update private.merchant_orders
set payment_state = 'paid'
where id = (select value from controlled_test_state where name = 'order-return');
update private.merchant_orders
set status = 'picked_up'
where id = (select value from controlled_test_state where name = 'order-return');
update private.merchant_orders
set status = 'in_transit'
where id = (select value from controlled_test_state where name = 'order-return');

insert into private.delivery_assignment_attempts (
  id, order_id, partner_account_id, attempt_number, status,
  distance_meters, offered_at, respond_by, responded_at
) values (
  '93000000-0000-4000-8000-000000000061',
  (select value from controlled_test_state where name = 'order-return'),
  '93000000-0000-4000-8000-000000000004', 1, 'accepted',
  100, now() - interval '1 minute', now() + interval '1 minute', now()
);

select throws_ok(
  format(
    'update private.merchant_orders set status = ''delivered'' where id = %L',
    (select value::text from controlled_test_state where name = 'order-return')
  ),
  '23514',
  'restricted_handoff_required',
  'ordinary delivery completion cannot bypass restricted handoff'
);

select is(
  (
    select response_status
    from public.verify_restricted_handoff(
      '93000000-0000-4000-8000-000000000004',
      '93000000-0000-4000-8000-000000000061',
      private.order_handoff_code(
        (select value from controlled_test_state where name = 'order-return'),
        'delivery'
      ),
      'uncertain', 'Recipient could not provide acceptable proof of age.',
      'handoff-return-1', 'handoff-return-digest-1'
    )
  ),
  200,
  'uncertain age check records a return requirement'
);

select is(
  (
    select status from private.merchant_orders
    where id = (select value from controlled_test_state where name = 'order-return')
  ),
  'returning_to_merchant',
  'failed age handoff never marks the order delivered'
);

select is(
  (
    select response_status
    from public.confirm_restricted_return(
      '93000000-0000-4000-8000-000000000002',
      (select value from controlled_test_state where name = 'order-return'),
      'Sealed restricted item returned.',
      'return-confirm-1', 'return-confirm-digest-1'
    )
  ),
  200,
  'merchant confirms the physical restricted-item return'
);

select is(
  (
    select payment_state from private.merchant_orders
    where id = (select value from controlled_test_state where name = 'order-return')
  ),
  'refund_pending',
  'returned item enters the existing refund pipeline'
);
select is(
  (
    select refund_reserved_paise from private.merchant_order_payment_records
    where order_id = (select value from controlled_test_state where name = 'order-return')
  ),
  20000::bigint,
  'restricted return refunds items while retaining the delivery fee'
);
select is(
  (
    select status from private.delivery_assignment_attempts
    where id = '93000000-0000-4000-8000-000000000061'
  ),
  'completed',
  'partner becomes available after merchant confirms return'
);

insert into controlled_test_state (name, value)
select 'quote-pass', (response_body ->> 'quoteId')::uuid
from public.quote_controlled_merchant_order(
  '93000000-0000-4000-8000-000000000003', 'tobacco',
  '93000000-0000-4000-8000-000000000020',
  '[{"productId":"93000000-0000-4000-8000-000000000043","quantity":1}]',
  12.6910, 78.6410, null,
  'quote-tobacco-pass', 'quote-tobacco-pass-digest'
);
insert into controlled_test_state (name, value)
select 'order-pass', (response_body ->> 'orderId')::uuid
from public.create_controlled_merchant_order(
  '93000000-0000-4000-8000-000000000003',
  (select value from controlled_test_state where name = 'quote-pass'),
  'controlled-create-pass', 'controlled-create-pass-digest'
);
update private.merchant_orders
set payment_state = 'paid'
where id = (select value from controlled_test_state where name = 'order-pass');
update private.merchant_orders
set status = 'picked_up'
where id = (select value from controlled_test_state where name = 'order-pass');
update private.merchant_orders
set status = 'in_transit'
where id = (select value from controlled_test_state where name = 'order-pass');
insert into private.delivery_assignment_attempts (
  id, order_id, partner_account_id, attempt_number, status,
  distance_meters, offered_at, respond_by, responded_at
) values (
  '93000000-0000-4000-8000-000000000062',
  (select value from controlled_test_state where name = 'order-pass'),
  '93000000-0000-4000-8000-000000000004', 1, 'accepted',
  100, now() - interval '1 minute', now() + interval '1 minute', now()
);

select is(
  (
    select response_status
    from public.verify_restricted_handoff(
      '93000000-0000-4000-8000-000000000004',
      '93000000-0000-4000-8000-000000000062',
      private.order_handoff_code(
        (select value from controlled_test_state where name = 'order-pass'),
        'delivery'
      ),
      'passed', null,
      'handoff-pass-1', 'handoff-pass-digest-1'
    )
  ),
  200,
  'assigned partner can complete a code-verified visual-age handoff'
);
select is(
  (
    select status from private.merchant_orders
    where id = (select value from controlled_test_state where name = 'order-pass')
  ),
  'delivered',
  'passed restricted handoff completes the order'
);

select * from finish();
rollback;
