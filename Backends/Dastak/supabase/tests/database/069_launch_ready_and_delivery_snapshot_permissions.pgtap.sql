begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege(
    'service_role',
    'dastak_v1_api.delivery_partner_snapshot(uuid)',
    'EXECUTE'
  ),
  true,
  'the courier-dispatch backend can read the V1 delivery snapshot'
);

select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.delivery_partner_snapshot(uuid)',
    'EXECUTE'
  ),
  false,
  'authenticated clients cannot bypass the courier-dispatch edge function'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.mark_fulfilment_ready(uuid,uuid,text,bigint)'::regprocedure
  ) like '%dastak_v1.launch_payment_commitments%',
  'launch pay-at-delivery commitments authorize the Ready transition'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.mark_fulfilment_ready(uuid,uuid,text,bigint)'::regprocedure
  ) like '%payment.status = ''SUCCEEDED''%',
  'legacy successful payments continue to authorize the Ready transition'
);

select * from finish();
rollback;
