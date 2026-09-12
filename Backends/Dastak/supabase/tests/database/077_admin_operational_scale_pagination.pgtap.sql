begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at) values (
  'd7000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'admin-scale@example.test', '', pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
);
insert into public.accounts (id, display_name, phone_number) values
  ('d7000000-0000-4000-8000-000000000001', 'Admin Scale', '+919500000701');
insert into private.account_memberships (account_id, role, approved_at) values
  ('d7000000-0000-4000-8000-000000000001', 'owner', pg_catalog.now());
insert into dastak_v1.platform_permission_grants (account_id, bundle_id, granted_by, grant_reason)
values ('d7000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-00000000000c',
  'd7000000-0000-4000-8000-000000000001', 'Admin scale projection test');

insert into dastak_v1.orders (id, display_order_number, customer_id, order_type, status, submitted_at, version, updated_at)
values
  ('d7100000-0000-4000-8000-000000000001', 'DSK-SCALE-0001', 'd7000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'MATCHING', '2026-09-12T09:00:00Z', 1, '2026-09-12T09:00:00Z'),
  ('d7100000-0000-4000-8000-000000000002', 'DSK-SCALE-0002', 'd7000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'PREPARING', '2026-09-12T10:00:00Z', 2, '2026-09-12T10:00:00Z'),
  ('d7100000-0000-4000-8000-000000000003', 'DSK-SCALE-0003', 'd7000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'DELIVERED', '2026-09-12T08:00:00Z', 3, '2026-09-12T11:00:00Z');

select has_function('public', 'dastak_v1_admin_execution_orders_page', array['text','text','integer','timestamp with time zone','uuid']);
select is(has_function_privilege('authenticated', 'public.dastak_v1_admin_execution_orders_page(text,text,integer,timestamptz,uuid)', 'EXECUTE'), true,
  'Authenticated callers can reach the permission-checked wrapper');
select is(has_function_privilege('authenticated', 'dastak_v1_api.admin_execution_orders_page(uuid,text,text,integer,timestamptz,uuid)', 'EXECUTE'), true,
  'Authenticated wrapper callers can reach the internally permission-checked projection');
select is(has_function_privilege('service_role', 'dastak_v1_api.admin_execution_orders_page(uuid,text,text,integer,timestamptz,uuid)', 'EXECUTE'), true,
  'The Edge service can execute the internal Admin projection');

select set_config('request.jwt.claim.sub', 'd7000000-0000-4000-8000-000000000001', true);
create temporary table first_page as
select public.dastak_v1_admin_execution_orders_page('ACTIVE', null, 1, null, null) body;
select is((select pg_catalog.jsonb_array_length(body -> 'orders') from first_page), 1, 'Active first page is bounded');
select is((select body ->> 'hasMore' from first_page), 'true', 'Active page truthfully reports more records');
select ok((select body -> 'nextCursor' is not null from first_page), 'Active page emits an opaque continuation cursor');

create temporary table second_page as
select public.dastak_v1_admin_execution_orders_page('ACTIVE', null, 1,
  (select (body #>> '{nextCursor,updatedAt}')::timestamptz from first_page),
  (select (body #>> '{nextCursor,orderId}')::uuid from first_page)) body;
select is((select pg_catalog.jsonb_array_length(body -> 'orders') from second_page), 1, 'Cursor retrieves the next active order');
select is((select body #>> '{orders,0,status}' from
  (select public.dastak_v1_admin_execution_orders_page('HISTORY', null, 10, null, null) body) history),
  'DELIVERED', 'History is separated from live operational work');
select is((select body #>> '{orders,0,id}' from
  (select public.dastak_v1_admin_execution_orders_page('HISTORY', 'd7100000-0000-4000-8000-000000000003', 10, null, null) body) exact),
  'd7100000-0000-4000-8000-000000000003', 'Exact ID lookup finds an order outside the live queue');

select * from finish();
rollback;
