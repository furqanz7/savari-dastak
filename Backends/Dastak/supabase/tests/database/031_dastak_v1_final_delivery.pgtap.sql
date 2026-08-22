begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('dastak_v1', 'delivery_evidence', 'immutable rider delivery evidence exists');
select has_table('dastak_v1', 'delivery_evidence_packages', 'evidence covers explicit packages');
select has_table('dastak_v1', 'exceptional_handoff_authorizations', 'exceptional handoffs have separate truth');

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relname in (
        'delivery_evidence', 'delivery_evidence_packages',
        'exceptional_handoff_authorizations'
      )
      and relation.relrowsecurity
  ),
  3::bigint,
  'every Step 4B business table has RLS enabled'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.delivery_evidence', 'SELECT'),
  false,
  'clients cannot query immutable delivery evidence rows directly'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.exceptional_handoff_authorizations', 'INSERT'),
  false,
  'clients cannot forge exceptional handoff authorization rows'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_advance_final_delivery(uuid,uuid,text,text,text,text,text)',
    'EXECUTE'
  ),
  false,
  'browser clients cannot inject rider identity into final-delivery commands'
);
select is(
  has_function_privilege(
    'service_role',
    'public.dastak_v1_advance_final_delivery(uuid,uuid,text,text,text,text,text)',
    'EXECUTE'
  ),
  true,
  'the authenticated Edge boundary can advance final delivery'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_authorize_exceptional_delivery_handoff(uuid,uuid,text,bigint,text)',
    'EXECUTE'
  ),
  true,
  'authenticated Operations may enter the permission-scoped override boundary'
);
select is(
  has_function_privilege(
    'service_role',
    'public.dastak_v1_authorize_exceptional_delivery_handoff(uuid,uuid,text,bigint,text)',
    'EXECUTE'
  ),
  false,
  'the service role cannot silently masquerade as Operations for override'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_trigger trigger
    where trigger.tgrelid in (
      'dastak_v1.delivery_evidence'::regclass,
      'dastak_v1.delivery_evidence_packages'::regclass,
      'dastak_v1.exceptional_handoff_authorizations'::regclass
    )
      and trigger.tgname in (
        'delivery_evidence_immutable',
        'delivery_evidence_packages_immutable',
        'exceptional_handoff_authorizations_immutable'
      )
      and not trigger.tgisinternal
  ),
  3::bigint,
  'evidence, package links and override authorizations are immutable'
);
select is(
  (
    select count(*) from dastak_v1.setting_definitions
    where setting_key = 'delivery.rider_pre_delivery_photo_required'
      and protected and default_value = 'true'::jsonb
  ),
  1::bigint,
  'pre-delivery rider photo is a locked requirement'
);
select is(
  (
    select count(*) from dastak_v1.permission_bundle_permissions
    where bundle_id = '10000000-0000-4000-8000-000000000007'::uuid
      and permission_key = 'platform.delivery.handoff_override'
  ),
  1::bigint,
  'exceptional handoff is isolated in the Delivery Operations bundle'
);

select * from finish();
rollback;
