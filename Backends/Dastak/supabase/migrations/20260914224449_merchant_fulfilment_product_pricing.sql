-- Merchants need the immutable value of the items they are fulfilling, but not
-- customer-facing delivery or platform fees.  Extend the already-authorized
-- fulfilment projection only; this does not alter orders, pricing, or taxes.
alter function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  rename to merchant_fulfilment_json_pre_product_pricing;

create function dastak_v1_api.merchant_fulfilment_json(
  p_actor_id uuid,
  p_fulfilment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_lines jsonb;
  v_product_subtotal_paise bigint;
begin
  -- The predecessor retains the authenticated merchant/branch authorization,
  -- lifecycle capability projection, tracking privacy boundary, and all
  -- existing fulfilment fields.
  v_result := dastak_v1_api.merchant_fulfilment_json_pre_product_pricing(
    p_actor_id,
    p_fulfilment_id
  );

  select
    coalesce(
      pg_catalog.sum(
        fulfilment_line.confirmed_quantity::bigint * order_line.unit_price_paise
      ),
      0
    ),
    coalesce(
      pg_catalog.jsonb_agg(
        projected_line.line_json
        || pg_catalog.jsonb_build_object(
          'unitPricePaise', order_line.unit_price_paise,
          'lineSubtotalPaise', fulfilment_line.confirmed_quantity::bigint
            * order_line.unit_price_paise
        )
        order by order_line.created_at, order_line.id
      ),
      '[]'::jsonb
    )
  into v_product_subtotal_paise, v_lines
  from pg_catalog.jsonb_array_elements(
    coalesce(v_result -> 'lines', '[]'::jsonb)
  ) as projected_line(line_json)
  join dastak_v1.order_lines order_line
    on order_line.id = (projected_line.line_json ->> 'orderLineId')::uuid
  join dastak_v1.fulfilment_lines fulfilment_line
    on fulfilment_line.order_line_id = order_line.id
   and fulfilment_line.fulfilment_id = p_fulfilment_id;

  return v_result || pg_catalog.jsonb_build_object(
    'productSubtotalPaise', v_product_subtotal_paise,
    'lines', v_lines
  );
end;
$$;

-- The new wrapper keeps the exact existing RPC boundary.  The renamed
-- predecessor must not remain callable over PostgREST.
revoke all on function dastak_v1_api.merchant_fulfilment_json_pre_product_pricing(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  to authenticated, service_role;

-- Retail opportunity decisions need the immutable value of the exact items
-- requested from this branch.  As with fulfilments, deliberately omit every
-- customer-wide fee and total.
alter function dastak_v1_api.merchant_opportunity_json(uuid, uuid)
  rename to merchant_opportunity_json_pre_product_pricing;

create function dastak_v1_api.merchant_opportunity_json(
  p_actor_id uuid,
  p_opportunity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_lines jsonb;
  v_product_subtotal_paise bigint;
begin
  -- The predecessor owns the opportunity/branch authorization and state
  -- projection.  Only decorate its exact, already-authorized order lines.
  v_result := dastak_v1_api.merchant_opportunity_json_pre_product_pricing(
    p_actor_id,
    p_opportunity_id
  );

  select
    coalesce(
      pg_catalog.sum(opportunity_line.requested_quantity::bigint * order_line.unit_price_paise),
      0
    ),
    coalesce(
      pg_catalog.jsonb_agg(
        projected_line.line_json
        || pg_catalog.jsonb_build_object(
          'unitPricePaise', order_line.unit_price_paise,
          'lineSubtotalPaise', opportunity_line.requested_quantity::bigint
            * order_line.unit_price_paise
        )
        order by opportunity_line.created_at, opportunity_line.order_line_id
      ),
      '[]'::jsonb
    )
  into v_product_subtotal_paise, v_lines
  from pg_catalog.jsonb_array_elements(
    coalesce(v_result -> 'lines', '[]'::jsonb)
  ) as projected_line(line_json)
  join dastak_v1.merchant_opportunity_lines opportunity_line
    on opportunity_line.order_line_id = (projected_line.line_json ->> 'orderLineId')::uuid
   and opportunity_line.opportunity_id = p_opportunity_id
  join dastak_v1.order_lines order_line
    on order_line.id = opportunity_line.order_line_id;

  return v_result || pg_catalog.jsonb_build_object(
    'productSubtotalPaise', v_product_subtotal_paise,
    'lines', v_lines
  );
end;
$$;

revoke all on function dastak_v1_api.merchant_opportunity_json_pre_product_pricing(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.merchant_opportunity_json(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function dastak_v1_api.merchant_opportunity_json(uuid, uuid)
  to authenticated, service_role;

-- Restaurant requests use the same merchant-only money boundary.  The current
-- request projection already contains the selected food lines; decorate those
-- exact snapshots with their immutable line total (including selected add-ons)
-- and a branch product subtotal.  Never project delivery/platform fees here.
alter function dastak_v1_api.restaurant_request_json(uuid, uuid)
  rename to restaurant_request_json_pre_product_pricing;

create function dastak_v1_api.restaurant_request_json(
  p_actor_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_lines jsonb;
  v_product_subtotal_paise bigint;
begin
  -- The predecessor retains merchant authorization, restaurant operational
  -- state and capability semantics.  This wrapper only exposes exact product
  -- value for the already-authorized request.
  v_result := dastak_v1_api.restaurant_request_json_pre_product_pricing(
    p_actor_id,
    p_request_id
  );

  select
    coalesce(pg_catalog.sum(order_line.line_total_paise), 0),
    coalesce(
      pg_catalog.jsonb_agg(
        projected_line.line_json
        || pg_catalog.jsonb_build_object(
          'lineSubtotalPaise', order_line.line_total_paise
        )
        order by order_line.created_at, order_line.id
      ),
      '[]'::jsonb
    )
  into v_product_subtotal_paise, v_lines
  from pg_catalog.jsonb_array_elements(
    coalesce(v_result -> 'lines', '[]'::jsonb)
  ) as projected_line(line_json)
  join dastak_v1.restaurant_order_requests request
    on request.id = p_request_id
  join dastak_v1.order_lines order_line
    on order_line.id = (projected_line.line_json ->> 'orderLineId')::uuid
   and order_line.order_id = request.order_id
   and order_line.line_type = 'FOOD_MENU_ITEM';

  return v_result || pg_catalog.jsonb_build_object(
    'productSubtotalPaise', v_product_subtotal_paise,
    'lines', v_lines
  );
end;
$$;

revoke all on function dastak_v1_api.restaurant_request_json_pre_product_pricing(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.restaurant_request_json(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function dastak_v1_api.restaurant_request_json(uuid, uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
