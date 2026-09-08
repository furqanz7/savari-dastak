begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(53);

select has_table('dastak_v1', 'launch_payment_commitments',
  'launch commitments have a canonical table');
select has_table('dastak_v1', 'launch_payment_collection_attempts',
  'doorstep collection attempts have an append-only table');
select has_column('dastak_v1', 'launch_payment_commitments', 'option_code',
  'the immutable option code is persisted');
select has_column('dastak_v1', 'launch_payment_commitments', 'amount_paise',
  'the server amount is persisted');
select has_column('dastak_v1', 'launch_payment_commitments', 'reservation_expires_at',
  'the secured reservation window is persisted');
select has_column('dastak_v1', 'launch_payment_collection_attempts', 'outcome',
  'each attempt persists its outcome');
select has_column('dastak_v1', 'launch_payment_collection_attempts', 'method',
  'each attempt persists CASH or UPI');
select has_column('dastak_v1', 'launch_payment_collection_attempts', 'attempted_at',
  'attempt time is authoritative');
select has_column('dastak_v1', 'launch_payment_collection_attempts', 'collected_at',
  'successful collection time is authoritative');

select is((select relrowsecurity from pg_catalog.pg_class where oid =
  'dastak_v1.launch_payment_commitments'::regclass), true,
  'commitments enforce RLS');
select is((select relrowsecurity from pg_catalog.pg_class where oid =
  'dastak_v1.launch_payment_collection_attempts'::regclass), true,
  'collection attempts enforce RLS');
select is(has_table_privilege('authenticated',
  'dastak_v1.launch_payment_commitments', 'SELECT'), false,
  'customers cannot read raw commitment rows');
select is(has_table_privilege('authenticated',
  'dastak_v1.launch_payment_collection_attempts', 'SELECT'), false,
  'clients cannot read raw collection attempts');
select is(has_table_privilege('service_role',
  'dastak_v1.launch_payment_commitments', 'SELECT'), true,
  'trusted handlers can build safe projections');
select is(has_table_privilege('service_role',
  'dastak_v1.launch_payment_collection_attempts', 'SELECT'), true,
  'trusted handlers can build safe collection projections');
select has_trigger('dastak_v1', 'launch_payment_commitments',
  'launch_payment_commitments_immutable', 'commitments are immutable');
select has_trigger('dastak_v1', 'launch_payment_collection_attempts',
  'launch_payment_collection_attempts_immutable', 'attempts are append-only');
select has_index('dastak_v1', 'launch_payment_collection_attempts',
  'launch_payment_one_collection_uidx', 'one successful collection is enforced');
select has_index('dastak_v1', 'launch_payment_commitments',
  'launch_payment_commitment_customer_idx', 'customer foreign key is indexed');
select has_index('dastak_v1', 'launch_payment_collection_attempts',
  'launch_payment_collection_commitment_idx', 'commitment foreign key is indexed');

select has_function('public', 'dastak_v1_commit_launch_payment',
  array['uuid', 'bigint', 'text']);
select has_function('public', 'dastak_v1_record_launch_payment_collection',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'bigint', 'text']);
select is(has_function_privilege('authenticated',
  'public.dastak_v1_commit_launch_payment(uuid,bigint,text)', 'EXECUTE'), true,
  'authenticated customers can call the ownership-checked commitment wrapper');
select is(has_function_privilege('anon',
  'public.dastak_v1_commit_launch_payment(uuid,bigint,text)', 'EXECUTE'), false,
  'anonymous callers cannot commit');
select is(has_function_privilege('authenticated',
  'public.dastak_v1_record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)',
  'EXECUTE'), false, 'clients cannot supply a rider identity directly');
select is(has_function_privilege('service_role',
  'public.dastak_v1_record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)',
  'EXECUTE'), true, 'the authenticated courier handler owns the rider binding');
select is((select prosecdef from pg_catalog.pg_proc where oid =
  'dastak_v1_api.commit_launch_payment(uuid,uuid,bigint,text)'::regprocedure), true,
  'commitment executes through the secured domain command');
select is((select prosecdef from pg_catalog.pg_proc where oid =
  'dastak_v1_api.record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)'::regprocedure), true,
  'collection executes through the secured domain command');
select ok(not ('p_amount_paise' = any(coalesce((select proargnames
  from pg_catalog.pg_proc where oid =
  'dastak_v1_api.record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)'::regprocedure),
  array[]::text[]))), 'the rider command accepts no client amount');

select is((select default_value #>> '{}' from dastak_v1.setting_definitions
  where setting_key = 'payment.launch_option_code'),
  'PAY_VIA_UPI_OR_CASH_ON_DELIVERY', 'the only launch option is authoritative');
select is((select default_value::text from dastak_v1.setting_definitions
  where setting_key = 'commerce.allow_cod'), 'true', 'COD is enabled for launch');
select is((select default_value::text from dastak_v1.setting_definitions
  where setting_key = 'commerce.prepaid_only'), 'false', 'prepaid-only is dormant');
select is((select requires_explicit_value from dastak_v1.setting_definitions
  where setting_key = 'settlement.merchant_commission_bps'), true,
  'missing merchant commission config remains a system configuration error');
select is(dastak_v1_api.calculate_platform_fee(1000), 20::bigint,
  'the locked platform fee remains exactly two percent');

select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)'::regprocedure
  ) ~ 'calculate_platform_fee', 'collection calculates the fee from server truth');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)'::regprocedure
  ) ~ 'post_balanced_financial_transaction', 'collection posts balanced append-only finance');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)'::regprocedure
  ) !~ 'payment_provider_events', 'launch collection never fabricates provider events');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.record_launch_payment_collection(uuid,uuid,text,text,text,text,bigint,text)'::regprocedure
  ) !~ 'set[[:space:]]+status[[:space:]]*=[[:space:]]*''SUCCEEDED''',
  'launch collection never fabricates a provider-paid payment');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.commit_launch_payment(uuid,uuid,bigint,text)'::regprocedure
  ) ~ 'status[[:space:]]*=[[:space:]]*''CANCELLED''',
  'commitment retires the dormant provider reservation');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.commit_launch_payment(uuid,uuid,bigint,text)'::regprocedure
  ) ~ 'status[[:space:]]*=[[:space:]]*''PREPARING''',
  'commitment starts preparation atomically');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.commit_launch_payment(uuid,uuid,bigint,text)'::regprocedure
  ) ~ 'SYSTEM_CONFIGURATION_ERROR',
  'missing launch configuration is an explicit system error');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.complete_final_delivery_locked(uuid,uuid,uuid,dastak_v1.verification_handoff_status,timestamp with time zone)'::regprocedure
  ) ~ 'launch_payment_collection_attempts',
  'normal delivery requires launch collection truth');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.complete_final_delivery_locked(uuid,uuid,uuid,dastak_v1.verification_handoff_status,timestamp with time zone)'::regprocedure
  ) ~ 'SUCCEEDED', 'historical legitimate provider payments remain deliverable');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.order_json_pre_tracking(uuid,uuid)'::regprocedure) ~ '''launchPayment''',
  'customer projection exposes only the safe launch state');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.order_json_pre_tracking(uuid,uuid)'::regprocedure
  ) ~ 'snapshot[[:space:]]*-[[:space:]]*''payment''',
  'launch orders omit dormant provider-attempt metadata from the customer projection');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.delivery_partner_snapshot(uuid)'::regprocedure) ~ 'launchCollection',
  'rider projection exposes the mission collection state');
select ok(pg_catalog.pg_get_functiondef(
  'dastak_v1_api.admin_execution_trace(uuid,uuid)'::regprocedure) ~ '''launchPayment''',
  'admin trace exposes the audited launch trace');

select is((select title from dastak_v1.notification_routes where
  event_type = 'LAUNCH_PAYMENT_COLLECTED' and audience = 'CUSTOMER'),
  'Payment collected', 'customer notification describes doorstep collection');
select is((select title from dastak_v1.notification_routes where
  event_type = 'PREPARATION_STARTED' and audience = 'MERCHANT'),
  'Order confirmed', 'merchant notification confirms preparation, not provider payment');
select has_table('dastak_v1', 'payments', 'legacy provider payments are preserved');
select has_table('dastak_v1', 'payment_attempts', 'legacy provider attempts are preserved');
select has_table('dastak_v1', 'payment_provider_events',
  'legacy provider event history is preserved');
select is(has_table_privilege('authenticated',
  'dastak_v1.launch_payment_collection_attempts', 'INSERT'), false,
  'assigned riders cannot bypass the service-bound command');

select * from finish();
rollback;
