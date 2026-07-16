create or replace function public.create_merchant_order(
  p_account_id uuid,
  p_quote_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'create_merchant_order';
  v_existing_dedup private.request_deduplication%rowtype;
  v_quote private.merchant_order_quotes%rowtype;
  v_order private.merchant_orders%rowtype;
  v_store private.merchant_stores%rowtype;
  v_line_count integer;
  v_valid_line_count integer;
  v_response_body jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_quote_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant order creation request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing_dedup.request_digest = p_request_digest then
      response_body := v_existing_dedup.response_body;
      response_status := v_existing_dedup.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select quote.*
  into v_quote
  from private.merchant_order_quotes as quote
  where quote.id = p_quote_id
    and quote.customer_account_id = p_account_id
  for update;

  if not found
    or v_quote.consumed_at is not null
    or v_quote.expires_at <= pg_catalog.now()
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'quote_unavailable',
        'message', 'The checkout quote is missing, expired, or already used.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select store.*
  into v_store
  from private.merchant_stores as store
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  join public.service_zones as zone
    on zone.id = store.service_zone_id
    and zone.active = true
    and extensions.st_covers(zone.boundary, v_quote.dropoff)
  where store.id = v_quote.store_id
    and store.is_published = true
    and store.accepting_orders = true
  for share of store;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'store_unavailable',
        'message', 'The merchant is no longer accepting orders.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  perform 1
  from private.merchant_order_rate_cards as rate
  where rate.id = v_quote.rate_card_id
    and rate.service_zone_id = v_store.service_zone_id
    and rate.version = v_quote.rate_card_version
    and rate.delivery_fee_paise = v_quote.delivery_fee_paise
    and rate.active = true
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_changed',
        'message', 'Checkout pricing changed. Request a new quote.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  perform 1
  from private.merchant_order_quote_lines as quote_line
  join private.catalogue_products as product
    on product.id = quote_line.product_id
  join private.catalogue_categories as category
    on category.id = product.category_id
    and category.store_id = product.store_id
  where quote_line.quote_id = v_quote.id
  for share of product, category;

  select pg_catalog.count(*)::integer
  into v_line_count
  from private.merchant_order_quote_lines as quote_line
  where quote_line.quote_id = v_quote.id;

  select pg_catalog.count(*)::integer
  into v_valid_line_count
  from private.merchant_order_quote_lines as quote_line
  join private.catalogue_products as product
    on product.id = quote_line.product_id
  join private.catalogue_categories as category
    on category.id = product.category_id
    and category.store_id = product.store_id
  where quote_line.quote_id = v_quote.id
    and product.store_id = v_store.id
    and product.name = quote_line.product_name
    and product.unit_label = quote_line.unit_label
    and product.price_paise = quote_line.unit_price_paise
    and product.is_active = true
    and product.availability = 'in_stock'
    and product.catalogue_kind = 'general'
    and product.restricted_approval_state = 'not_applicable'
    and category.is_active = true;

  if v_line_count < 1 or v_valid_line_count <> v_line_count then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_changed',
        'message', 'The catalogue changed after this quote. Request a new quote.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into private.merchant_orders (
    customer_account_id, store_id, service_zone_id, quote_id,
    status, payment_state, dropoff, item_subtotal_paise,
    delivery_fee_paise, total_paise
  ) values (
    p_account_id,
    v_store.id,
    v_store.service_zone_id,
    v_quote.id,
    'payment_pending',
    'payment_pending',
    v_quote.dropoff,
    v_quote.item_subtotal_paise,
    v_quote.delivery_fee_paise,
    v_quote.total_paise
  )
  returning * into v_order;

  insert into private.merchant_order_lines (
    order_id, product_id, product_name, unit_label,
    unit_price_paise, quantity, line_subtotal_paise
  )
  select
    v_order.id,
    quote_line.product_id,
    quote_line.product_name,
    quote_line.unit_label,
    quote_line.unit_price_paise,
    quote_line.quantity,
    quote_line.line_subtotal_paise
  from private.merchant_order_quote_lines as quote_line
  where quote_line.quote_id = v_quote.id;

  update private.merchant_order_quotes as quote
  set consumed_at = pg_catalog.now()
  where quote.id = v_quote.id;

  v_response_body := private.merchant_order_json(v_order);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, after_state
  ) values (
    p_account_id,
    'merchant_order_created',
    'merchant_order',
    v_order.id,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 201
  );

  response_body := v_response_body;
  response_status := 201;
  return next;
end;
$$;
