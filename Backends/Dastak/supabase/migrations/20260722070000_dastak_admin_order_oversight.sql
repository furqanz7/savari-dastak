create function public.get_owner_merchant_orders(
  p_account_id uuid,
  p_limit integer default 50
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    );

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The order limit must be between 1 and 100.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select pg_catalog.jsonb_build_object(
    'orders', coalesce(
      pg_catalog.jsonb_agg(recent.order_json order by recent.created_at desc),
      '[]'::jsonb
    )
  )
  into response_body
  from (
    select
      merchant_order.created_at,
      pg_catalog.jsonb_build_object(
        'orderId', merchant_order.id,
        'store', pg_catalog.jsonb_build_object(
          'storeId', store.id,
          'name', store.name
        ),
        'status', merchant_order.status,
        'paymentState', merchant_order.payment_state,
        'itemSubtotal', pg_catalog.jsonb_build_object(
          'paise', merchant_order.item_subtotal_paise
        ),
        'deliveryFee', pg_catalog.jsonb_build_object(
          'paise', merchant_order.delivery_fee_paise
        ),
        'total', pg_catalog.jsonb_build_object(
          'paise', merchant_order.total_paise
        ),
        'itemCount', coalesce(line_totals.item_count, 0),
        'assignmentStatus', latest_assignment.status,
        'controlledScope', merchant_order.controlled_scope,
        'createdAt', merchant_order.created_at,
        'updatedAt', merchant_order.updated_at
      ) as order_json
    from private.merchant_orders as merchant_order
    join private.merchant_stores as store
      on store.id = merchant_order.store_id
    left join lateral (
      select pg_catalog.sum(line.quantity)::integer as item_count
      from private.merchant_order_lines as line
      where line.order_id = merchant_order.id
    ) as line_totals on true
    left join lateral (
      select assignment.status
      from private.delivery_assignment_attempts as assignment
      where assignment.order_id = merchant_order.id
      order by assignment.attempt_number desc
      limit 1
    ) as latest_assignment on true
    order by merchant_order.created_at desc, merchant_order.id desc
    limit p_limit
  ) as recent;

  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.get_owner_merchant_orders(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.get_owner_merchant_orders(uuid, integer)
  to service_role;
