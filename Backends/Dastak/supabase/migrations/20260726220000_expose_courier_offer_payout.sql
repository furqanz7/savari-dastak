create or replace function private.delivery_assignment_json(
  assignment_row private.delivery_assignment_attempts
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when (assignment_row).id is null then null
    else pg_catalog.jsonb_build_object(
      'assignmentId', (assignment_row).id,
      'orderId', merchant_order.id,
      'assignmentStatus', (assignment_row).status,
      'orderStatus', merchant_order.status,
      'offeredAt', (assignment_row).offered_at,
      'respondBy', (assignment_row).respond_by,
      'acceptedAt', case
        when (assignment_row).status = 'accepted'
          then (assignment_row).responded_at
        else null
      end,
      'distanceMeters', pg_catalog.round(
        (assignment_row).distance_meters::numeric,
        1
      ),
      'courierPayout', pg_catalog.jsonb_build_object(
        'paise', merchant_order.courier_payout_paise
      ),
      'store', pg_catalog.jsonb_build_object(
        'storeId', store.id,
        'name', store.name,
        'address', store.address,
        'pickup', pg_catalog.jsonb_build_object(
          'latitude', extensions.st_y(store.location),
          'longitude', extensions.st_x(store.location)
        )
      ),
      'dropoff', pg_catalog.jsonb_build_object(
        'latitude', extensions.st_y(merchant_order.dropoff),
        'longitude', extensions.st_x(merchant_order.dropoff)
      ),
      'items', coalesce(
        (
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'productId', line.product_id,
              'name', line.product_name,
              'unitLabel', line.unit_label,
              'quantity', line.quantity
            ) order by line.product_name, line.product_id
          )
          from private.merchant_order_lines as line
          where line.order_id = merchant_order.id
        ),
        '[]'::jsonb
      )
    )
  end
  from private.merchant_orders as merchant_order
  join private.merchant_stores as store
    on store.id = merchant_order.store_id
  where merchant_order.id = (assignment_row).order_id;
$$;

revoke execute on function private.delivery_assignment_json(
  private.delivery_assignment_attempts
) from public, anon, authenticated;
grant execute on function private.delivery_assignment_json(
  private.delivery_assignment_attempts
) to service_role;
