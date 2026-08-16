begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table(
  'private',
  'order_state_transitions',
  'canonical order transition journal exists'
);
select has_trigger(
  'private',
  'order_state_transitions',
  'order_state_transitions_immutable',
  'canonical transition journal is append-only'
);
select has_trigger(
  'private',
  'merchant_orders',
  'zz_merchant_order_state_guard',
  'merchant lifecycle is guarded by Postgres'
);
select has_trigger(
  'private',
  'parcel_deliveries',
  'zz_parcel_state_guard',
  'parcel lifecycle is guarded by Postgres'
);
select has_trigger(
  'private',
  'merchant_orders',
  'zzz_merchant_order_realtime',
  'merchant order changes emit invalidation events'
);
select has_trigger(
  'private',
  'parcel_deliveries',
  'zzz_parcel_realtime',
  'parcel changes emit invalidation events'
);

select ok(
  private.is_valid_merchant_order_transition('ready', 'assigned'),
  'ready merchant orders can be assigned'
);
select ok(
  private.is_valid_merchant_order_transition('assigned', 'ready'),
  'orphan merchant assignments can recover to ready'
);
select ok(
  not private.is_valid_merchant_order_transition('delivered', 'ready'),
  'delivered merchant orders cannot roll back'
);
select ok(
  private.is_valid_parcel_transition('assigned', 'paid'),
  'orphan parcel assignments can recover to paid'
);
select ok(
  not private.is_valid_parcel_transition('in_transit', 'paid'),
  'in-transit parcels cannot roll back'
);
select ok(
  not private.is_valid_merchant_payment_transition('refunded', 'paid'),
  'refunded merchant payments cannot reopen'
);
select ok(
  not private.is_valid_parcel_payment_transition('refunded', 'paid'),
  'refunded parcel payments cannot reopen'
);

select is(
  has_table_privilege(
    'authenticated',
    'private.order_state_transitions',
    'SELECT'
  ),
  false,
  'authenticated clients cannot read the private journal'
);
select is(
  has_table_privilege(
    'service_role',
    'private.order_state_transitions',
    'INSERT'
  ),
  false,
  'service calls cannot forge journal rows'
);
select is(
  has_function_privilege(
    'authenticated',
    'private.reconcile_order_lifecycle()',
    'EXECUTE'
  ),
  false,
  'authenticated clients cannot run reconciliation'
);
select is(
  has_function_privilege(
    'service_role',
    'private.reconcile_order_lifecycle()',
    'EXECUTE'
  ),
  true,
  'service role can run reconciliation'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and policyname = 'dastak_account_order_events'
      and roles = array['authenticated'::name]
  ),
  'private account-scoped realtime policy exists'
);
select ok(
  exists (
    select 1
    from cron.job
    where jobname = 'dastak-order-lifecycle-reconciliation'
      and schedule = '* * * * *'
      and active = true
  ),
  'lifecycle reconciliation runs every minute'
);

select * from finish();
rollback;
