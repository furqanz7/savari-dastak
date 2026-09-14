-- Legacy merchant order projections are served through a service-role Edge
-- boundary.  Keep customer and owner projections intact, while providing the
-- merchant feed with only its immutable product value.  Delivery and order
-- total values are customer/rider/admin concerns and must never reach a
-- merchant browser response.
create function private.merchant_order_json_for_merchant(
  order_row private.merchant_orders
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.merchant_order_json_with_handoff(order_row, 'merchant')
    - 'deliveryFee'
    - 'deliveryDistanceMeters'
    - 'total'
    - 'refundDecision';
$$;

revoke all on function private.merchant_order_json_for_merchant(private.merchant_orders)
  from public, anon, authenticated, service_role;
grant execute on function private.merchant_order_json_for_merchant(private.merchant_orders)
  to service_role;

create or replace function public.get_merchant_orders(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_store_id uuid;
  v_orders jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  select store.id
  into v_store_id
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.merchant_order_json_for_merchant(merchant_order)
      order by merchant_order.created_at desc, merchant_order.id desc
    ),
    '[]'::jsonb
  )
  into v_orders
  from private.merchant_orders as merchant_order
  where merchant_order.store_id = v_store_id
    and merchant_order.status <> 'payment_pending'
    and not (
      merchant_order.status = 'cancelled'
      and merchant_order.payment_state = 'not_collected'
    );

  response_body := pg_catalog.jsonb_build_object('orders', v_orders);
  response_status := 200;
  return next;
end;
$$;

revoke all on function public.get_merchant_orders(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_merchant_orders(uuid) to service_role;

notify pgrst, 'reload schema';
