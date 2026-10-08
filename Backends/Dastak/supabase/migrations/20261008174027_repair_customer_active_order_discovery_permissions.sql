-- Do not grant customers USAGE on the private data schema. Reuse the
-- unexposed, already-authorized API schema for this guarded read function.
alter function private.customer_active_order_discovery(uuid) set schema dastak_v1_api;
create or replace function public.dastak_v1_customer_active_orders() returns jsonb
language sql stable security invoker set search_path='' as $$
 select dastak_v1_api.customer_active_order_discovery(auth.uid());
$$;
revoke all on function dastak_v1_api.customer_active_order_discovery(uuid),public.dastak_v1_customer_active_orders() from public,anon,service_role;
grant execute on function dastak_v1_api.customer_active_order_discovery(uuid),public.dastak_v1_customer_active_orders() to authenticated;
