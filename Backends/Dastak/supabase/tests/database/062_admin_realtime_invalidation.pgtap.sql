begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'dastak_v1_api', 'is_active_admin_actor', array[]::text[],
  'the private Admin channel has an authenticated role guard'
);
select is(
  has_function_privilege(
    'authenticated', 'dastak_v1_api.is_active_admin_actor()', 'EXECUTE'
  ),
  true,
  'authenticated callers may evaluate only their own Admin status'
);
select is(
  has_function_privilege(
    'authenticated', 'private.send_admin_change(text[],uuid)', 'EXECUTE'
  ),
  false,
  'authenticated clients cannot fabricate Admin invalidations'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'realtime'
      and policy.tablename = 'messages'
      and policy.policyname = 'dastak_admin_control_events'
      and policy.cmd = 'SELECT'
      and 'authenticated' = any (policy.roles)
      and policy.qual like '%admin-control%'
      and policy.qual like '%is_active_admin_actor%'
  ),
  'Admin broadcasts are private and restricted to active Admin accounts'
);

select has_trigger(
  'private', 'merchant_applications',
  'zzz_admin_merchant_applications_realtime',
  'merchant approval changes invalidate Admin immediately'
);
select has_trigger(
  'private', 'delivery_partner_applications',
  'zzz_admin_delivery_applications_realtime',
  'Delivery Partner approval changes invalidate Admin immediately'
);
select has_trigger(
  'dastak_v1', 'orders', 'zzz_admin_orders_realtime',
  'order changes invalidate Admin immediately'
);
select has_trigger(
  'dastak_v1', 'fulfilments', 'zzz_admin_fulfilments_realtime',
  'fulfilment changes invalidate Admin immediately'
);
select has_trigger(
  'dastak_v1', 'delivery_missions', 'zzz_admin_delivery_missions_realtime',
  'delivery mission changes invalidate Admin immediately'
);

select * from finish();
rollback;
