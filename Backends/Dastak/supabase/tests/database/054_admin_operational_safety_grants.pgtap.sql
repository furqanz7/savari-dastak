begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.admin_operational_safety(uuid)',
    'EXECUTE'
  ),
  true,
  'the authenticated Admin wrapper can execute its internal safety projection'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.manage_rider_escalation(uuid,uuid,text,text,bigint,text)',
    'EXECUTE'
  ),
  true,
  'the authenticated Admin wrapper can execute rider escalation management'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.set_operational_pause(uuid,text,uuid,boolean,text,bigint,text)',
    'EXECUTE'
  ),
  true,
  'the authenticated Admin wrapper can execute operational pause management'
);

select is(
  has_function_privilege(
    'anon',
    'dastak_v1_api.admin_operational_safety(uuid)',
    'EXECUTE'
  ),
  false,
  'anonymous callers cannot execute the internal safety projection'
);
select is(
  has_function_privilege(
    'anon',
    'dastak_v1_api.manage_rider_escalation(uuid,uuid,text,text,bigint,text)',
    'EXECUTE'
  ),
  false,
  'anonymous callers cannot execute rider escalation management'
);
select is(
  has_function_privilege(
    'anon',
    'dastak_v1_api.set_operational_pause(uuid,text,uuid,boolean,text,bigint,text)',
    'EXECUTE'
  ),
  false,
  'anonymous callers cannot execute operational pause management'
);

select * from finish();
rollback;
