begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('dastak_v1', 'delivery_missions', 'V1 delivery missions exist');
select has_table('dastak_v1', 'delivery_offers', 'V1 rider offers exist');
select has_table('dastak_v1', 'delivery_stops', 'V1 pickup stops exist');
select has_table('dastak_v1', 'verification_handoffs', 'V1 handoffs exist');
select has_table('dastak_v1', 'package_custody_events', 'V1 custody history exists');

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relname in (
        'delivery_missions', 'delivery_offers', 'delivery_stops',
        'verification_handoffs', 'package_custody_events',
        'delivery_problem_reports'
      )
      and not relation.relrowsecurity
  ),
  0::bigint,
  'every Step 4A business table has RLS enabled'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.delivery_missions', 'SELECT'),
  false,
  'clients cannot directly read mission rows'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.packages', 'UPDATE'),
  false,
  'clients cannot bypass verified package custody commands'
);

select is(
  (
    select count(*) from pg_catalog.pg_indexes
    where schemaname = 'dastak_v1'
      and indexname = 'delivery_missions_one_active_order_uidx'
      and indexdef like '%WHERE (status <> ALL%'
  ),
  1::bigint,
  'one active mission per order is structurally enforced'
);
select is(
  (
    select count(*) from pg_catalog.pg_indexes
    where schemaname = 'dastak_v1'
      and indexname = 'delivery_missions_one_active_rider_uidx'
      and indexdef like '%WHERE%assigned_rider_id IS NOT NULL%'
  ),
  1::bigint,
  'one active customer mission per rider is structurally enforced'
);
select is(
  (
    select count(*) from pg_catalog.pg_indexes
    where schemaname = 'dastak_v1'
      and indexname = 'delivery_offers_one_accepted_mission_uidx'
  ),
  1::bigint,
  'only one rider offer can win a mission'
);

select is(dastak_v1.rider_transport_type('walking')::text, null, 'retired walking does not map to current transport');
select is(dastak_v1.rider_transport_type('bicycle')::text, null, 'retired bicycle does not map to current transport');
select is(dastak_v1.rider_transport_type('bike')::text, 'MOTORBIKE', 'legacy bike maps to motorbike');
select is(dastak_v1.rider_transport_type('motorbike')::text, 'MOTORBIKE', 'motorbike maps exactly');
select is(dastak_v1.rider_transport_type('scooter')::text, 'SCOOTER', 'scooter maps exactly');
select is(dastak_v1.rider_transport_type('auto')::text, 'AUTO', 'auto maps exactly');
select is(dastak_v1.rider_transport_type('goods_vehicle')::text, 'CAR', 'tempo and goods vehicle maps to the heavy-load transport class');

select is(
  (
    select count(*) from dastak_v1.setting_definitions
    where setting_key in (
      'delivery.rider_initial_pool_size', 'delivery.rider_pool_expansion',
      'delivery.verification_invalid_attempt_limit'
    ) and requires_explicit_value and default_value is null
  ),
  3::bigint,
  'operational rider numbers require explicit configuration'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_accept_delivery_offer(uuid,uuid,text,text)',
    'EXECUTE'
  ),
  false,
  'browser clients cannot inject rider identity into privileged dispatch RPCs'
);
select is(
  has_function_privilege(
    'service_role',
    'public.dastak_v1_accept_delivery_offer(uuid,uuid,text,text)',
    'EXECUTE'
  ),
  true,
  'the authenticated Edge boundary can invoke rider acceptance'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.submit_delivery_partner_application_v3(uuid,text,text,text,text,text,text,text)',
    'EXECUTE'
  ),
  false,
  'browser clients cannot bypass V1 transport onboarding through the RPC'
);
select is(
  has_function_privilege(
    'service_role',
    'public.submit_delivery_partner_application_v3(uuid,text,text,text,text,text,text,text)',
    'EXECUTE'
  ),
  true,
  'the authenticated Edge boundary can submit every V1 transport type'
);
select is(
  (
    select count(*) from pg_catalog.pg_trigger trigger
    where trigger.tgrelid = 'dastak_v1.fulfilments'::regclass
      and trigger.tgname = 'fulfilments_activate_pickup_after_ready'
      and not trigger.tgisinternal
  ),
  1::bigint,
  'Ready activates its pickup handoff and immediate rider eligibility path'
);
select is(
  (
    select count(*) from cron.job
    where jobname = 'dastak-v1-rider-matching'
  ),
  1::bigint,
  'clock-derived rider eligibility and pool expansion run automatically'
);

select * from finish();
rollback;
