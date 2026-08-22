begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('dastak_v1', 'packages', 'V1 packages exist');
select has_table('dastak_v1', 'fulfilment_evidence', 'immutable Ready evidence exists');
select has_table('dastak_v1', 'fulfilment_problem_reports', 'problem history exists');
select has_column('dastak_v1', 'fulfilments', 'estimated_ready_at', 'estimated Ready is persisted');
select has_column('dastak_v1', 'fulfilments', 'actual_ready_at', 'actual Ready is persisted');
select has_column('dastak_v1', 'fulfilments', 'package_count', 'authoritative package count is persisted');

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relname in ('packages', 'fulfilment_evidence', 'fulfilment_problem_reports')
      and not relation.relrowsecurity
  ),
  0::bigint,
  'all Step 3 transactional tables have RLS enabled'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.packages', 'SELECT'),
  false,
  'merchant package data is not directly exposed'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.fulfilment_evidence', 'SELECT'),
  false,
  'merchant evidence metadata is not directly exposed'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_mark_fulfilment_ready(uuid,text,bigint)',
    'EXECUTE'
  ),
  true,
  'authenticated merchants may invoke the permission-checked Ready command'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_mark_fulfilment_ready(uuid,text,bigint)',
    'EXECUTE'
  ),
  false,
  'anonymous clients cannot mark fulfilments Ready'
);

select is(
  dastak_v1.fulfilment_rider_match_eligible_at(
    'PREPARING',
    '2026-08-22 12:05:01+00'::timestamptz,
    '2026-08-22 12:00:00+00'::timestamptz
  ),
  false,
  '05:01 remaining is not rider-match eligible'
);
select is(
  dastak_v1.fulfilment_rider_match_eligible_at(
    'PREPARING',
    '2026-08-22 12:05:00+00'::timestamptz,
    '2026-08-22 12:00:00+00'::timestamptz
  ),
  true,
  '05:00 remaining is rider-match eligible'
);
select is(
  dastak_v1.fulfilment_rider_match_eligible_at(
    'READY',
    '2026-08-22 13:00:00+00'::timestamptz,
    '2026-08-22 12:00:00+00'::timestamptz
  ),
  true,
  'early Ready immediately satisfies rider-match eligibility'
);

select is(
  (
    select default_value
    from dastak_v1.setting_definitions
    where setting_key = 'preparation.rider_match_threshold_seconds'
  ),
  '300'::jsonb,
  'the locked rider threshold is five minutes'
);
select is(
  (
    select default_value
    from dastak_v1.setting_definitions
    where setting_key = 'preparation.merchant_ready_photo_required'
  ),
  'true'::jsonb,
  'merchant Ready photo remains locked on'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_trigger trigger
    where trigger.tgrelid = 'dastak_v1.payment_provider_events'::regclass
      and trigger.tgname = 'payment_provider_events_start_preparation'
      and not trigger.tgisinternal
  ),
  1::bigint,
  'authoritative successful provider events start preparation once'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_trigger trigger
    where trigger.tgrelid = 'dastak_v1.fulfilment_evidence'::regclass
      and trigger.tgname = 'fulfilment_evidence_immutable'
      and not trigger.tgisinternal
  ),
  1::bigint,
  'Ready evidence has an immutable-history trigger'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_policy policy
    where policy.polrelid = 'storage.objects'::regclass
      and policy.polname like 'dastak_v1_merchant_ready_evidence%'
      and policy.polcmd in ('w', 'd')
  ),
  0::bigint,
  'merchant Ready storage has no update or delete policy'
);

select * from finish();
rollback;
