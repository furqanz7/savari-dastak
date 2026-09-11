begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege(
    'service_role',
    'public.dastak_delivery_partner_work_history(uuid,integer)',
    'EXECUTE'
  ),
  true,
  'courier-dispatch can read bounded rider work history'
);

select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_delivery_partner_work_history(uuid,integer)',
    'EXECUTE'
  ),
  false,
  'authenticated clients cannot bypass the courier Edge boundary'
);

select is(
  has_function_privilege(
    'anon',
    'public.dastak_delivery_partner_work_history(uuid,integer)',
    'EXECUTE'
  ),
  false,
  'anonymous clients cannot read rider history'
);

select is(
  pg_catalog.jsonb_typeof(
    public.dastak_delivery_partner_work_history(
      '11111111-1111-4111-8111-111111111111'::uuid,
      30
    )->'items'
  ),
  'array',
  'the empty rider history contract still returns an items array'
);

select * from finish();
rollback;
