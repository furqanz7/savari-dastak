begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(16);

select has_table('dastak_v1', 'payment_client_completions',
  'verified Custom Checkout returns have an immutable record');
select is((select relrowsecurity from pg_catalog.pg_class where oid =
  'dastak_v1.payment_client_completions'::regclass), true,
  'completion evidence enforces RLS');
select is(has_table_privilege('authenticated',
  'dastak_v1.payment_client_completions', 'SELECT'), false,
  'ordinary clients cannot read provider completion evidence');
select is(has_function_privilege('authenticated',
  'public.dastak_v1_record_custom_checkout_completion(uuid,uuid,uuid,text,text,text,text,text)',
  'EXECUTE'), false, 'customers cannot bypass server-side signature verification');
select is(has_function_privilege('service_role',
  'public.dastak_v1_record_custom_checkout_completion(uuid,uuid,uuid,text,text,text,text,text)',
  'EXECUTE'), true, 'the authenticated payment Edge Function can record verified evidence');
select has_trigger('dastak_v1', 'payment_client_completions',
  'payment_client_completions_immutable', 'completion evidence is append-only');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('97000000-0000-4000-8000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'custom-checkout-owner@example.test', '', now(), now(), now()),
  ('97000000-0000-4000-8000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'custom-checkout-outsider@example.test', '', now(), now(), now());
insert into public.accounts (id, display_name, phone_number) values
  ('97000000-0000-4000-8000-000000000001', 'Checkout Owner', '+919700000001'),
  ('97000000-0000-4000-8000-000000000002', 'Checkout Outsider', '+919700000002');
insert into private.account_memberships (account_id, role, approved_at) values
  ('97000000-0000-4000-8000-000000000001', 'customer', now()),
  ('97000000-0000-4000-8000-000000000002', 'customer', now());

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, fully_secured_at, payment_expires_at
) values (
  '97000000-0000-4000-8000-000000000010', 'DSK-CUSTOM-CHECKOUT-1',
  '97000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'AWAITING_PAYMENT',
  now() - interval '5 minutes', now() - interval '4 minutes', now() + interval '5 minutes'
);
insert into dastak_v1.payments (
  id, order_id, customer_id, status, amount_paise, currency_code,
  reserved_at, expires_at
) values (
  '97000000-0000-4000-8000-000000000020',
  '97000000-0000-4000-8000-000000000010',
  '97000000-0000-4000-8000-000000000001', 'RESERVED', 7500, 'INR',
  now() - interval '1 minute', now() + interval '5 minutes'
);
insert into dastak_v1.payment_attempts (
  id, payment_id, order_id, customer_id, status, idempotency_key,
  request_hash, amount_paise, currency_code, provider_receipt,
  provider_order_reference, provider_ready_at
) values (
  '97000000-0000-4000-8000-000000000030',
  '97000000-0000-4000-8000-000000000020',
  '97000000-0000-4000-8000-000000000010',
  '97000000-0000-4000-8000-000000000001', 'PROVIDER_READY', 'checkout-attempt-1',
  decode(repeat('01', 32), 'hex'), 7500, 'INR', 'dastak-custom-checkout-1',
  'order_custom123', now()
);

select is(
  dastak_v1_api.custom_checkout_completion_context(
    '97000000-0000-4000-8000-000000000001',
    '97000000-0000-4000-8000-000000000010',
    '97000000-0000-4000-8000-000000000030'
  ) ->> 'providerOrderId',
  'order_custom123', 'server context returns the stored Razorpay order identity'
);
select throws_ok($$
  select dastak_v1_api.custom_checkout_completion_context(
    '97000000-0000-4000-8000-000000000002',
    '97000000-0000-4000-8000-000000000010',
    '97000000-0000-4000-8000-000000000030'
  )
$$, 'P0002', 'payment attempt not found', 'another customer cannot load the attempt');

select is(
  dastak_v1_api.record_custom_checkout_completion(
    '97000000-0000-4000-8000-000000000001',
    '97000000-0000-4000-8000-000000000010',
    '97000000-0000-4000-8000-000000000030',
    'order_custom123', 'pay_custom123', repeat('a', 64), repeat('b', 64),
    'custom-return-1'
  ) ->> 'state',
  'AWAITING_PROVIDER_CONFIRMATION',
  'verified client return waits for payment.captured authority'
);
select is((select status::text from dastak_v1.payments where id =
  '97000000-0000-4000-8000-000000000020'), 'RESERVED',
  'client-return verification does not mark the payment paid');
select is((select status::text from dastak_v1.orders where id =
  '97000000-0000-4000-8000-000000000010'), 'AWAITING_PAYMENT',
  'client-return verification does not advance the customer order');
select is(
  dastak_v1_api.record_custom_checkout_completion(
    '97000000-0000-4000-8000-000000000001',
    '97000000-0000-4000-8000-000000000010',
    '97000000-0000-4000-8000-000000000030',
    'order_custom123', 'pay_custom123', repeat('a', 64), repeat('b', 64),
    'custom-return-1'
  ) ->> 'duplicate',
  'true', 'duplicate completion callback is idempotent'
);
select is((select count(*) from dastak_v1.payment_client_completions), 1::bigint,
  'duplicate completion stores exactly one record');
select throws_ok($$
  select dastak_v1_api.record_custom_checkout_completion(
    '97000000-0000-4000-8000-000000000001',
    '97000000-0000-4000-8000-000000000010',
    '97000000-0000-4000-8000-000000000030',
    'order_custom123', 'pay_replayed999', repeat('c', 64), repeat('d', 64),
    'custom-return-1'
  )
$$, '23505', 'checkout completion conflict',
  'same attempt or idempotency identity cannot be rebound to another payment');
select throws_ok($$
  update dastak_v1.payment_client_completions set provider = 'RAZORPAY'
$$, 'P0001', 'dastak_v1.payment_client_completions is append-only',
  'verified provider evidence cannot be rewritten');
select is((select count(*) from dastak_v1.audit_events where
  action = 'CUSTOM_CHECKOUT_COMPLETION_VERIFIED' and resource_id =
  '97000000-0000-4000-8000-000000000030'), 1::bigint,
  'one immutable audit fact records the verified client return');

select * from finish();
rollback;
