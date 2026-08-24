begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(8);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'cf000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'admin-projection@example.test', '',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
);
insert into public.accounts (id, display_name, phone_number) values (
  'cf000000-0000-4000-8000-000000000001',
  'Admin Projection Owner', '+919500000301'
);
insert into private.account_memberships (account_id, role, approved_at) values (
  'cf000000-0000-4000-8000-000000000001', 'owner', pg_catalog.now()
);
insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
) values (
  'cf000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-00000000000c',
  'cf000000-0000-4000-8000-000000000001',
  'Admin projection contract test.'
);

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, version
) values (
  'cf100000-0000-4000-8000-000000000001', 'DSK-ADMIN-0001',
  'cf000000-0000-4000-8000-000000000001', 'RETAIL_ONLY',
  'MATCHING', '2026-08-24T10:00:00Z', 2
);

select set_config(
  'request.jwt.claim.sub',
  'cf000000-0000-4000-8000-000000000001',
  true
);

create temporary table tap_admin_orders as
select dastak_v1_api.admin_execution_orders(
  'cf000000-0000-4000-8000-000000000001', 10
) as body;

select is(
  (select body #>> '{orders,0,orderType}' from tap_admin_orders),
  'RETAIL_ONLY',
  'Admin order list returns the strict order type'
);
select ok(
  (select body #> '{orders,0}' ? 'updatedAt' from tap_admin_orders),
  'Admin order list returns updatedAt'
);
select ok(
  (select body #> '{orders,0}' ? 'deliveredAt' from tap_admin_orders),
  'Admin order list returns nullable deliveredAt'
);

create temporary table tap_admin_trace as
select dastak_v1_api.admin_execution_trace(
  'cf000000-0000-4000-8000-000000000001',
  'cf100000-0000-4000-8000-000000000001'
) as body;

select is(
  (select body #>> '{order,orderType}' from tap_admin_trace),
  'RETAIL_ONLY',
  'Admin execution trace returns the strict order type'
);
select ok(
  (select body #> '{order}' ? 'updatedAt' from tap_admin_trace),
  'Admin execution trace returns updatedAt'
);
select ok(
  (select body #> '{order}' ? 'deliveredAt' from tap_admin_trace),
  'Admin execution trace returns nullable deliveredAt'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.admin_execution_trace(uuid,uuid)',
    'EXECUTE'
  ),
  false,
  'Authenticated clients cannot bypass the permission-checked public wrapper'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_admin_execution_trace(uuid)',
    'EXECUTE'
  ),
  true,
  'Authenticated Admin clients retain the public execution-trace entrypoint'
);

select * from finish();
rollback;
