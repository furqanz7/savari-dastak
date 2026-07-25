alter table private.merchant_order_quotes
  add column delivery_distance_m integer;

update private.merchant_order_quotes as quote
set delivery_distance_m = pg_catalog.ceil(
  extensions.st_distance(
    store.location::extensions.geography,
    quote.dropoff::extensions.geography
  )
)::integer
from private.merchant_stores as store
where store.id = quote.store_id;

alter table private.merchant_order_quotes
  alter column delivery_distance_m set not null,
  add constraint merchant_order_quotes_delivery_distance_check check (
    delivery_distance_m between 0 and 1000000
  );

alter table private.merchant_orders
  add column delivery_distance_m integer;

update private.merchant_orders as merchant_order
set delivery_distance_m = quote.delivery_distance_m
from private.merchant_order_quotes as quote
where quote.id = merchant_order.quote_id;

alter table private.merchant_orders
  alter column delivery_distance_m set not null,
  add constraint merchant_orders_delivery_distance_check check (
    delivery_distance_m between 0 and 1000000
  );

create or replace function private.snapshot_merchant_order_quote_financial_terms()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_rate private.merchant_order_rate_cards%rowtype;
  v_store private.merchant_stores%rowtype;
  v_distance_terms jsonb;
begin
  select store.*
  into v_store
  from private.merchant_stores as store
  where store.id = new.store_id
    and store.is_published = true
    and store.accepting_orders = true
  for share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_store_unavailable';
  end if;

  perform 1
  from public.service_zones as zone
  where zone.id = v_store.service_zone_id
    and zone.active = true
    and extensions.st_covers(zone.boundary, new.dropoff)
  for share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_dropoff_unavailable';
  end if;

  select rate.*
  into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.id = new.rate_card_id
    and rate.service_zone_id = v_store.service_zone_id
    and rate.version = new.rate_card_version
    and rate.active = true
  for share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_financial_terms_unavailable';
  end if;

  new.delivery_distance_m := pg_catalog.ceil(
    extensions.st_distance(
      v_store.location::extensions.geography,
      new.dropoff::extensions.geography
    )
  )::integer;
  v_distance_terms := private.calculate_merchant_order_distance_terms(
    v_rate,
    new.delivery_distance_m
  );

  new.delivery_fee_paise := (
    v_distance_terms -> 'deliveryFee' ->> 'paise'
  )::integer;
  new.total_paise := new.item_subtotal_paise + new.delivery_fee_paise;
  new.merchant_commission_bps := v_rate.merchant_commission_bps;
  new.courier_payout_paise := (
    v_distance_terms -> 'courierPayout' ->> 'paise'
  )::integer;
  return new;
end;
$$;

create or replace function private.snapshot_merchant_order_financial_terms()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_quote private.merchant_order_quotes%rowtype;
begin
  select quote.*
  into v_quote
  from private.merchant_order_quotes as quote
  where quote.id = new.quote_id
    and quote.item_subtotal_paise = new.item_subtotal_paise
    and quote.delivery_fee_paise = new.delivery_fee_paise
    and quote.total_paise = new.total_paise
  for share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_financial_terms_unavailable';
  end if;

  new.delivery_distance_m := v_quote.delivery_distance_m;
  new.merchant_commission_bps := v_quote.merchant_commission_bps;
  new.merchant_commission_paise :=
    (new.item_subtotal_paise * v_quote.merchant_commission_bps) / 10000;
  new.merchant_payable_paise :=
    new.item_subtotal_paise - new.merchant_commission_paise;
  new.courier_payout_paise := v_quote.courier_payout_paise;
  new.platform_delivery_margin_paise :=
    new.delivery_fee_paise - v_quote.courier_payout_paise;
  return new;
end;
$$;

create or replace function private.merchant_order_quote_json(
  quote_row private.merchant_order_quotes
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'quoteId', (quote_row).id,
    'storeId', (quote_row).store_id,
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'productId', line.product_id,
            'name', line.product_name,
            'unitLabel', line.unit_label,
            'unitPrice', pg_catalog.jsonb_build_object(
              'paise', line.unit_price_paise
            ),
            'quantity', line.quantity,
            'lineSubtotal', pg_catalog.jsonb_build_object(
              'paise', line.line_subtotal_paise
            )
          ) order by line.product_name, line.product_id
        )
        from private.merchant_order_quote_lines as line
        where line.quote_id = (quote_row).id
      ),
      '[]'::jsonb
    ),
    'itemSubtotal', pg_catalog.jsonb_build_object(
      'paise', (quote_row).item_subtotal_paise
    ),
    'deliveryFee', pg_catalog.jsonb_build_object(
      'paise', (quote_row).delivery_fee_paise
    ),
    'deliveryDistanceMeters', (quote_row).delivery_distance_m,
    'total', pg_catalog.jsonb_build_object('paise', (quote_row).total_paise),
    'dropoff', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((quote_row).dropoff),
      'longitude', extensions.st_x((quote_row).dropoff)
    ),
    'expiresAt', (quote_row).expires_at
  );
$$;

create or replace function private.merchant_order_json(
  order_row private.merchant_orders
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'orderId', (order_row).id,
    'storeId', (order_row).store_id,
    'status', (order_row).status,
    'paymentState', (order_row).payment_state,
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'productId', line.product_id,
            'name', line.product_name,
            'unitLabel', line.unit_label,
            'unitPrice', pg_catalog.jsonb_build_object(
              'paise', line.unit_price_paise
            ),
            'quantity', line.quantity,
            'lineSubtotal', pg_catalog.jsonb_build_object(
              'paise', line.line_subtotal_paise
            )
          ) order by line.product_name, line.product_id
        )
        from private.merchant_order_lines as line
        where line.order_id = (order_row).id
      ),
      '[]'::jsonb
    ),
    'itemSubtotal', pg_catalog.jsonb_build_object(
      'paise', (order_row).item_subtotal_paise
    ),
    'deliveryFee', pg_catalog.jsonb_build_object(
      'paise', (order_row).delivery_fee_paise
    ),
    'deliveryDistanceMeters', (order_row).delivery_distance_m,
    'total', pg_catalog.jsonb_build_object('paise', (order_row).total_paise),
    'dropoff', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((order_row).dropoff),
      'longitude', extensions.st_x((order_row).dropoff)
    ),
    'stateVersion', (order_row).state_version,
    'refundDecision', private.merchant_order_refund_json(
      (
        select decision
        from private.merchant_order_refund_decisions as decision
        where decision.order_id = (order_row).id
        order by decision.created_at desc, decision.id desc
        limit 1
      )
    ),
    'createdAt', (order_row).created_at,
    'updatedAt', (order_row).updated_at
  );
$$;

revoke execute on function private.snapshot_merchant_order_quote_financial_terms()
  from public, anon, authenticated;
revoke execute on function private.snapshot_merchant_order_financial_terms()
  from public, anon, authenticated;
revoke execute on function private.merchant_order_quote_json(
  private.merchant_order_quotes
) from public, anon, authenticated;
revoke execute on function private.merchant_order_json(private.merchant_orders)
  from public, anon, authenticated;

grant execute on function private.snapshot_merchant_order_quote_financial_terms()
  to service_role;
grant execute on function private.snapshot_merchant_order_financial_terms()
  to service_role;
grant execute on function private.merchant_order_quote_json(
  private.merchant_order_quotes
) to service_role;
grant execute on function private.merchant_order_json(private.merchant_orders)
  to service_role;
