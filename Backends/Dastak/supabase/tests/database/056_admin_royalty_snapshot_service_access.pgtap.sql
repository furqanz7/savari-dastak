begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);

select is(
  has_function_privilege(
    'service_role',
    'public.dastak_v1_razorpayx_admin_snapshot(uuid,integer)',
    'EXECUTE'
  ),
  true,
  'the earnings service can execute the public Admin Royalty wrapper'
);
select is(
  has_function_privilege(
    'service_role',
    'dastak_v1_api.razorpayx_admin_snapshot(uuid,integer)',
    'EXECUTE'
  ),
  true,
  'the wrapper can execute its narrow private Admin Royalty target'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_razorpayx_admin_snapshot(uuid,integer)',
    'EXECUTE'
  ),
  false,
  'anonymous clients cannot execute the public Admin Royalty wrapper'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_razorpayx_admin_snapshot(uuid,integer)',
    'EXECUTE'
  ),
  false,
  'ordinary authenticated clients cannot execute the service wrapper'
);
select is(
  has_function_privilege(
    'anon',
    'dastak_v1_api.razorpayx_admin_snapshot(uuid,integer)',
    'EXECUTE'
  ),
  false,
  'anonymous clients cannot execute the private Admin Royalty target'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.razorpayx_admin_snapshot(uuid,integer)',
    'EXECUTE'
  ),
  false,
  'ordinary authenticated clients cannot execute the private target'
);

select * from finish();
rollback;
