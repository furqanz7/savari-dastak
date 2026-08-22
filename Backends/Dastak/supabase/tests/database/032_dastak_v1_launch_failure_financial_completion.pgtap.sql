begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('dastak_v1', 'recovery_cases', 'exact-SKU and delivery recovery cases exist');
select has_table('dastak_v1', 'customer_issues', 'customer issue truth exists');
select has_table('dastak_v1', 'returns', 'physical-return decisions exist');
select has_table('dastak_v1', 'return_packages', 'return packages have independent custody truth');
select has_table('dastak_v1', 'return_verifications', 'reverse custody uses in-app verification');
select has_table('dastak_v1', 'refunds', 'original-method refund truth exists');
select has_table('dastak_v1', 'settlement_entries', 'merchant and rider settlement truth exists');
select has_table('dastak_v1', 'settlement_entry_history', 'settlement history is append-only');

select is(
  (
    select count(*) from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relname in (
        'recovery_cases', 'recovery_opportunities', 'customer_issues',
        'customer_issue_evidence', 'returns', 'return_lines', 'return_packages',
        'return_missions', 'return_stops', 'return_verifications',
        'return_evidence', 'return_evidence_packages', 'return_custody_events',
        'delivery_address_exceptions', 'refunds', 'refund_provider_events',
        'settlement_entries', 'settlement_entry_history'
      ) and relation.relrowsecurity
  ),
  18::bigint,
  'all Step 5 business tables enforce RLS'
);

select is(
  has_table_privilege('authenticated', 'dastak_v1.refunds', 'INSERT'),
  false,
  'customers cannot forge refunds'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.settlement_entries', 'UPDATE'),
  false,
  'clients cannot mutate settlements directly'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.return_custody_events', 'INSERT'),
  false,
  'clients cannot forge reverse custody events'
);

select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_report_customer_issue(uuid,uuid,text,text,text,text,text)',
    'EXECUTE'
  ), true,
  'customers may report issues only through the authenticated command boundary'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_advance_return_mission(uuid,uuid,text,uuid,text,text,text)',
    'EXECUTE'
  ), false,
  'browser clients cannot inject rider identity into return custody commands'
);
select is(
  has_function_privilege(
    'service_role',
    'public.dastak_v1_advance_return_mission(uuid,uuid,text,uuid,text,text,text)',
    'EXECUTE'
  ), true,
  'the authenticated Edge boundary may execute reverse custody commands'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_prepare_razorpay_refund(uuid,uuid,text)',
    'EXECUTE'
  ), false,
  'clients cannot prepare provider refunds directly'
);
select is(
  has_function_privilege(
    'service_role',
    'public.dastak_v1_prepare_razorpay_refund(uuid,uuid,text)',
    'EXECUTE'
  ), true,
  'refund preparation is restricted to the payment service boundary'
);

select is(
  (
    select count(*) from pg_catalog.pg_trigger trigger
    where trigger.tgrelid in (
      'dastak_v1.customer_issue_evidence'::regclass,
      'dastak_v1.return_lines'::regclass,
      'dastak_v1.return_evidence'::regclass,
      'dastak_v1.return_evidence_packages'::regclass,
      'dastak_v1.return_custody_events'::regclass,
      'dastak_v1.delivery_address_exceptions'::regclass,
      'dastak_v1.refund_provider_events'::regclass,
      'dastak_v1.settlement_entry_history'::regclass
    ) and trigger.tgname in (
      'customer_issue_evidence_immutable', 'return_lines_immutable',
      'return_evidence_immutable', 'return_evidence_packages_immutable',
      'return_custody_events_immutable', 'delivery_address_exceptions_immutable',
      'refund_provider_events_immutable', 'settlement_entry_history_immutable'
    ) and not trigger.tgisinternal
  ),
  8::bigint,
  'issue evidence, reverse custody, provider events, and settlement history are immutable'
);

select is(
  (
    select count(*) from dastak_v1.setting_definitions
    where setting_key in (
      'recovery.radius_meters', 'recovery.offer_timeout_seconds',
      'returns.reporting_window_seconds', 'refunds.approval_limit_paise',
      'settlement.merchant_commission_bps', 'settlement.rider_flat_payout_paise',
      'returns.pickup_photo_required'
    )
  ),
  7::bigint,
  'Step 5 operational behavior is explicit configuration'
);
select is(
  (
    select count(*) from dastak_v1.setting_definitions
    where setting_key = 'returns.pickup_photo_required'
      and protected and default_value = 'true'::jsonb
  ),
  1::bigint,
  'return pickup photo remains a locked custody requirement'
);

select is(
  (
    select count(*) from dastak_v1.permission_definitions
    where permission_key in (
      'platform.recovery.manage', 'platform.returns.approve',
      'platform.refunds.approve', 'platform.refunds.process',
      'platform.settlements.manage'
    )
  ),
  5::bigint,
  'recovery, return, refund, and settlement powers are separate permissions'
);

select * from finish();
rollback;
