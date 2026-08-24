-- Keep the Admin Web projection aligned with the strict V1 client contract.
-- This is additive: it does not mutate order history or business state.

create or replace function dastak_v1_api.admin_execution_orders(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.orders.trace'
  );
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'limit must be between 1 and 100';
  end if;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, metadata
  ) values (
    p_actor_id,
    'ADMIN_EXECUTION_ORDERS_READ',
    'order_collection',
    pg_catalog.jsonb_build_object('limit', p_limit)
  );

  return pg_catalog.jsonb_build_object(
    'orders', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', selected.id,
        'displayOrderNumber', selected.display_order_number,
        'orderType', selected.order_type,
        'status', selected.status,
        'version', selected.version,
        'submittedAt', selected.submitted_at,
        'fullySecuredAt', selected.fully_secured_at,
        'paymentExpiresAt', selected.payment_expires_at,
        'paidAt', selected.paid_at,
        'updatedAt', selected.updated_at,
        'deliveredAt', selected.delivered_at
      ) order by selected.updated_at desc, selected.id desc)
      from (
        select customer_order.*
        from dastak_v1.orders customer_order
        order by customer_order.updated_at desc, customer_order.id desc
        limit p_limit
      ) selected
    ), '[]'::jsonb)
  );
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_pre_projection_contract;

create function dastak_v1_api.admin_execution_trace(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trace jsonb;
  v_order dastak_v1.orders%rowtype;
begin
  -- The previous function remains authoritative for permission checks, audit,
  -- and the complete operational/financial trace.
  v_trace := dastak_v1_api.admin_execution_trace_pre_projection_contract(
    p_actor_id, p_order_id
  );

  select customer_order.*
  into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  return pg_catalog.jsonb_set(
    v_trace,
    '{order}',
    coalesce(v_trace -> 'order', '{}'::jsonb) || pg_catalog.jsonb_build_object(
      'orderType', v_order.order_type,
      'updatedAt', v_order.updated_at,
      'deliveredAt', v_order.delivered_at
    ),
    true
  );
end;
$$;

-- Recompile the exposed wrappers against the current internal functions.
create or replace function public.dastak_v1_admin_execution_orders(
  p_limit integer default 50
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_execution_orders(auth.uid(), p_limit);
$$;

create or replace function public.dastak_v1_admin_execution_trace(
  p_order_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_execution_trace(auth.uid(), p_order_id);
$$;

revoke all on function dastak_v1_api.admin_execution_orders(uuid, integer)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.admin_execution_trace_pre_projection_contract(uuid, uuid)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_admin_execution_orders(integer)
  from public, anon;
revoke all on function public.dastak_v1_admin_execution_trace(uuid)
  from public, anon;

grant execute on function dastak_v1_api.admin_execution_orders(uuid, integer)
  to service_role;
grant execute on function dastak_v1_api.admin_execution_trace_pre_projection_contract(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  to service_role;
grant execute on function public.dastak_v1_admin_execution_orders(integer)
  to authenticated, service_role;
grant execute on function public.dastak_v1_admin_execution_trace(uuid)
  to authenticated, service_role;

comment on function dastak_v1_api.admin_execution_orders(uuid, integer) is
  'Strict Admin V1 order list projection including order type and lifecycle timestamps.';
comment on function dastak_v1_api.admin_execution_trace(uuid, uuid) is
  'Strict Admin V1 execution trace including the complete client order projection.';
