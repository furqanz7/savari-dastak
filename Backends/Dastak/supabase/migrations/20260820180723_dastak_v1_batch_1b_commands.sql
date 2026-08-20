-- Batch 1B exposes only the approved V1 customer commands and reads.
-- All writes stay inside security-definer functions in the unexposed API
-- schema; public wrappers are security invokers.

create function dastak_v1_api.request_hash(p_request jsonb)
returns bytea
language sql
immutable
security invoker
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(p_request::text, 'UTF8'),
    'sha256'
  );
$$;

create function dastak_v1_api.assert_customer_actor(p_actor_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_actor_id is null or p_actor_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  if not exists (
    select 1
    from public.accounts account
    join private.account_memberships membership
      on membership.account_id = account.id
    where account.id = p_actor_id
      and membership.role = 'customer'
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
  ) then
    raise exception using errcode = '42501', message = 'active customer access required';
  end if;
end;
$$;

create function dastak_v1_api.order_json(
  p_order_id uuid,
  p_customer_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', customer_order.id,
    'displayOrderNumber', customer_order.display_order_number,
    'orderType', customer_order.order_type,
    'status', customer_order.status,
    'version', customer_order.version,
    'deliveryAddress', context_snapshot.delivery_address,
    'recipient', context_snapshot.recipient,
    'price', (
      select pg_catalog.jsonb_build_object(
        'snapshotKind', price_snapshot.snapshot_kind,
        'subtotalPaise', price_snapshot.subtotal_paise,
        'deliveryFeePaise', price_snapshot.delivery_fee_paise,
        'platformFeePaise', price_snapshot.platform_fee_paise,
        'discountPaise', price_snapshot.discount_paise,
        'taxPaise', price_snapshot.tax_paise,
        'totalPaise', price_snapshot.total_paise,
        'currencyCode', price_snapshot.currency_code
      )
      from dastak_v1.order_price_snapshots price_snapshot
      where price_snapshot.order_id = customer_order.id
      order by case price_snapshot.snapshot_kind
        when 'FINAL' then 4
        when 'PAID' then 3
        when 'FULLY_SECURED' then 2
        else 1
      end desc
      limit 1
    ),
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              'id', order_line.id,
              'lineType', order_line.line_type,
              'skuId', order_line.sku_id,
              'menuItemId', order_line.food_menu_item_id,
              'name', order_line.product_name_snapshot,
              'variant', order_line.variant_snapshot,
              'packSize', order_line.pack_size_snapshot,
              'quantity', order_line.quantity,
              'unitPricePaise', order_line.unit_price_paise,
              'lineTotalPaise', order_line.line_total_paise,
              'status', order_line.status
            )
          )
          order by order_line.created_at, order_line.id
        )
        from dastak_v1.order_lines order_line
        where order_line.order_id = customer_order.id
      ),
      '[]'::jsonb
    ),
    'submittedAt', customer_order.submitted_at,
    'fullySecuredAt', customer_order.fully_secured_at,
    'paymentExpiresAt', customer_order.payment_expires_at,
    'paidAt', customer_order.paid_at,
    'deliveredAt', customer_order.delivered_at,
    'createdAt', customer_order.created_at,
    'updatedAt', customer_order.updated_at
  )
  from dastak_v1.orders customer_order
  join dastak_v1.order_context_snapshots context_snapshot
    on context_snapshot.order_id = customer_order.id
  where customer_order.id = p_order_id
    and customer_order.customer_id = p_customer_id;
$$;

create function dastak_v1_api.submit_order(
  p_actor_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_order jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'submitOrder';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_account public.accounts%rowtype;
  v_delivery_input jsonb;
  v_recipient_input jsonb;
  v_address jsonb;
  v_recipient jsonb;
  v_address_line text;
  v_recipient_name text;
  v_recipient_phone text;
  v_country_code text;
  v_latitude numeric;
  v_longitude numeric;
  v_line_input jsonb;
  v_sku_id uuid;
  v_quantity_bigint bigint;
  v_quantity integer;
  v_sku dastak_v1.skus%rowtype;
  v_order_id uuid := gen_random_uuid();
  v_display_order_number text;
  v_subtotal_paise bigint := 0;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);

  if p_expected_version is distinct from 0 then
    raise exception using errcode = '40001', message = 'new order expectedVersion must be 0';
  end if;
  if p_idempotency_key is null
    or char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;
  if p_order is null or jsonb_typeof(p_order) <> 'object' then
    raise exception using errcode = '22023', message = 'order must be a JSON object';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'expectedVersion', p_expected_version,
      'order', p_order
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select * into v_existing
  from dastak_v1.idempotency_records
  where actor_id = p_actor_id
    and command_name = v_command
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select * into v_account
  from public.accounts
  where id = p_actor_id;

  v_delivery_input := p_order -> 'deliveryAddress';
  if v_delivery_input is null or jsonb_typeof(v_delivery_input) <> 'object' then
    raise exception using errcode = '22023', message = 'deliveryAddress is required';
  end if;

  v_address_line := nullif(
    pg_catalog.btrim(
      coalesce(
        v_delivery_input ->> 'line1',
        v_delivery_input ->> 'formattedAddress',
        ''
      )
    ),
    ''
  );
  v_country_code := upper(pg_catalog.btrim(coalesce(v_delivery_input ->> 'countryCode', '')));

  if v_address_line is null or char_length(v_address_line) > 300 then
    raise exception using errcode = '22023', message = 'a valid delivery address is required';
  end if;
  if v_country_code !~ '^[A-Z]{2}$' then
    raise exception using errcode = '22023', message = 'a two-letter countryCode is required';
  end if;

  if v_delivery_input ? 'latitude' or v_delivery_input ? 'longitude' then
    if jsonb_typeof(v_delivery_input -> 'latitude') <> 'number'
      or jsonb_typeof(v_delivery_input -> 'longitude') <> 'number' then
      raise exception using errcode = '22023', message = 'latitude and longitude must be numbers';
    end if;
    v_latitude := (v_delivery_input ->> 'latitude')::numeric;
    v_longitude := (v_delivery_input ->> 'longitude')::numeric;
    if v_latitude not between -90 and 90 or v_longitude not between -180 and 180 then
      raise exception using errcode = '22023', message = 'delivery coordinates are out of range';
    end if;
  end if;

  v_address := pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'label', nullif(pg_catalog.btrim(v_delivery_input ->> 'label'), ''),
      'line1', v_address_line,
      'line2', nullif(pg_catalog.btrim(v_delivery_input ->> 'line2'), ''),
      'landmark', nullif(pg_catalog.btrim(v_delivery_input ->> 'landmark'), ''),
      'locality', nullif(pg_catalog.btrim(v_delivery_input ->> 'locality'), ''),
      'city', nullif(pg_catalog.btrim(v_delivery_input ->> 'city'), ''),
      'state', nullif(pg_catalog.btrim(v_delivery_input ->> 'state'), ''),
      'postalCode', nullif(pg_catalog.btrim(v_delivery_input ->> 'postalCode'), ''),
      'countryCode', v_country_code,
      'latitude', v_latitude,
      'longitude', v_longitude,
      'instructions', nullif(pg_catalog.btrim(v_delivery_input ->> 'instructions'), '')
    )
  );

  v_recipient_input := coalesce(p_order -> 'recipient', '{}'::jsonb);
  if jsonb_typeof(v_recipient_input) <> 'object' then
    raise exception using errcode = '22023', message = 'recipient must be a JSON object';
  end if;

  v_recipient_name := pg_catalog.btrim(
    coalesce(v_recipient_input ->> 'name', v_account.display_name)
  );
  v_recipient_phone := pg_catalog.btrim(
    coalesce(v_recipient_input ->> 'phoneNumber', v_account.phone_number)
  );

  if char_length(v_recipient_name) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'recipient name is invalid';
  end if;
  if v_recipient_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception using errcode = '22023', message = 'recipient phoneNumber must be E.164';
  end if;

  v_recipient := pg_catalog.jsonb_build_object(
    'name', v_recipient_name,
    'phoneNumber', v_recipient_phone
  );

  if coalesce(jsonb_typeof(p_order -> 'lines'), '') <> 'array'
    or jsonb_array_length(p_order -> 'lines') = 0 then
    raise exception using errcode = '22023', message = 'at least one order line is required';
  end if;

  for v_line_input in
    select value from jsonb_array_elements(p_order -> 'lines')
  loop
    if jsonb_typeof(v_line_input) <> 'object'
      or coalesce(v_line_input ->> 'lineType', '') <> 'RETAIL_SKU' then
      raise exception using
        errcode = '22023',
        message = 'Batch 1 accepts canonical RETAIL_SKU lines only';
    end if;
    if coalesce(v_line_input ->> 'skuId', '')
      !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
      raise exception using errcode = '22023', message = 'line skuId is invalid';
    end if;
    if jsonb_typeof(v_line_input -> 'quantity') <> 'number'
      or (v_line_input ->> 'quantity') !~ '^[1-9][0-9]*$' then
      raise exception using errcode = '22023', message = 'line quantity must be a positive integer';
    end if;
  end loop;

  v_display_order_number := 'DSK-'
    || pg_catalog.to_char(pg_catalog.now(), 'YYMMDD')
    || '-'
    || pg_catalog.lpad(
      pg_catalog.nextval('dastak_v1.order_number_sequence'::regclass)::text,
      8,
      '0'
    );

  insert into dastak_v1.orders (
    id,
    display_order_number,
    customer_id,
    order_type,
    status,
    submitted_at,
    version
  ) values (
    v_order_id,
    v_display_order_number,
    p_actor_id,
    'RETAIL_ONLY',
    'CREATED',
    pg_catalog.now(),
    1
  );

  insert into dastak_v1.order_state_journal (
    order_id,
    from_status,
    to_status,
    order_version,
    command_name,
    actor_id,
    reason
  ) values (
    v_order_id,
    null,
    'CREATED',
    1,
    v_command,
    p_actor_id,
    'Customer submitted an order.'
  );

  insert into dastak_v1.order_context_snapshots (
    order_id,
    delivery_address,
    recipient,
    snapshot_hash
  ) values (
    v_order_id,
    v_address,
    v_recipient,
    dastak_v1_api.request_hash(
      pg_catalog.jsonb_build_object('deliveryAddress', v_address, 'recipient', v_recipient)
    )
  );

  for v_sku_id, v_quantity_bigint in
    select
      (value ->> 'skuId')::uuid,
      sum((value ->> 'quantity')::bigint)
    from jsonb_array_elements(p_order -> 'lines')
    group by (value ->> 'skuId')::uuid
    order by (value ->> 'skuId')::uuid
  loop
    if v_quantity_bigint > 2147483647 then
      raise exception using errcode = '22003', message = 'line quantity is too large';
    end if;
    v_quantity := v_quantity_bigint::integer;

    select sku.* into v_sku
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory
      on subcategory.id = sku.subcategory_id
    join dastak_v1.categories category
      on category.id = subcategory.category_id
    left join dastak_v1.brands brand
      on brand.id = sku.brand_id
    where sku.id = v_sku_id
      and sku.status = 'ACTIVE'
      and subcategory.status = 'ACTIVE'
      and category.status = 'ACTIVE'
      and (brand.id is null or brand.status = 'ACTIVE');

    if not found then
      raise exception using errcode = '22023', message = 'one or more SKUs are unavailable';
    end if;

    insert into dastak_v1.order_lines (
      order_id,
      line_type,
      sku_id,
      product_name_snapshot,
      variant_snapshot,
      pack_size_snapshot,
      quantity,
      unit_price_paise,
      tax_rate_bps,
      status
    ) values (
      v_order_id,
      'RETAIL_SKU',
      v_sku.id,
      v_sku.canonical_name,
      v_sku.variant_name,
      v_sku.pack_size,
      v_quantity,
      v_sku.selling_price_paise,
      v_sku.tax_rate_bps,
      'ORDERED'
    );

    v_subtotal_paise := v_subtotal_paise
      + (v_quantity::bigint * v_sku.selling_price_paise);
  end loop;

  insert into dastak_v1.order_price_snapshots (
    order_id,
    snapshot_kind,
    subtotal_paise,
    delivery_fee_paise,
    platform_fee_paise,
    discount_paise,
    tax_paise,
    total_paise,
    currency_code,
    calculation_details
  ) values (
    v_order_id,
    'SUBMITTED',
    v_subtotal_paise,
    0,
    0,
    0,
    0,
    v_subtotal_paise,
    'INR',
    pg_catalog.jsonb_build_object(
      'cataloguePriceAuthority', 'DASTAK',
      'taxIncludedInUnitPrice', true
    )
  );

  update dastak_v1.orders
  set status = 'MATCHING',
      version = version + 1
  where id = v_order_id;

  insert into dastak_v1.order_state_journal (
    order_id,
    from_status,
    to_status,
    order_version,
    command_name,
    actor_id,
    reason
  ) values (
    v_order_id,
    'CREATED',
    'MATCHING',
    2,
    v_command,
    p_actor_id,
    'Submission accepted; later matching batches may now act.'
  );

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_order_id::text || ':ORDER_SUBMITTED:2',
    'ORDER',
    v_order_id,
    2,
    'ORDER_SUBMITTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order_id,
      'customerId', p_actor_id,
      'orderType', 'RETAIL_ONLY',
      'status', 'MATCHING',
      'version', 2
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'ORDER_SUBMITTED',
    'order',
    v_order_id,
    pg_catalog.jsonb_build_object(
      'idempotencyKey', p_idempotency_key,
      'version', 2
    )
  );

  v_response := dastak_v1_api.order_json(v_order_id, p_actor_id);

  insert into dastak_v1.idempotency_records (
    actor_id,
    command_name,
    idempotency_key,
    request_hash,
    response_body,
    response_status,
    resource_id
  ) values (
    p_actor_id,
    v_command,
    p_idempotency_key,
    v_request_hash,
    v_response,
    201,
    v_order_id
  );

  return v_response;
end;
$$;

create function dastak_v1_api.cancel_prepayment_order(
  p_actor_id uuid,
  p_order_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'cancelPrepaymentOrder';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);

  if p_idempotency_key is null
    or char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'orderId', p_order_id,
      'expectedVersion', p_expected_version
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key,
      0
    )
  );

  select * into v_existing
  from dastak_v1.idempotency_records
  where actor_id = p_actor_id
    and command_name = v_command
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select * into v_order
  from dastak_v1.orders
  where id = p_order_id
    and customer_id = p_actor_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  if v_order.status = 'CANCELLED_PREPAYMENT' then
    v_response := dastak_v1_api.order_json(v_order.id, p_actor_id);
    insert into dastak_v1.idempotency_records (
      actor_id,
      command_name,
      idempotency_key,
      request_hash,
      response_body,
      response_status,
      resource_id
    ) values (
      p_actor_id,
      v_command,
      p_idempotency_key,
      v_request_hash,
      v_response,
      200,
      v_order.id
    );
    return v_response;
  end if;

  if v_order.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale order version';
  end if;

  if v_order.paid_at is not null
    or v_order.status not in ('CREATED', 'MATCHING', 'FULLY_SECURED', 'AWAITING_PAYMENT') then
    raise exception using
      errcode = '55000',
      message = 'customer cancellation is not allowed after payment';
  end if;

  update dastak_v1.orders
  set status = 'CANCELLED_PREPAYMENT',
      version = version + 1
  where id = v_order.id;

  insert into dastak_v1.order_state_journal (
    order_id,
    from_status,
    to_status,
    order_version,
    command_name,
    actor_id,
    reason
  ) values (
    v_order.id,
    v_order.status,
    'CANCELLED_PREPAYMENT',
    v_order.version + 1,
    v_command,
    p_actor_id,
    'Customer cancelled before payment.'
  );

  insert into dastak_v1.domain_events_outbox (
    event_key,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    actor_id,
    payload
  ) values (
    v_order.id::text || ':ORDER_CANCELLED_PREPAYMENT:' || (v_order.version + 1)::text,
    'ORDER',
    v_order.id,
    v_order.version + 1,
    'ORDER_CANCELLED_PREPAYMENT',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'customerId', p_actor_id,
      'status', 'CANCELLED_PREPAYMENT',
      'version', v_order.version + 1
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'ORDER_CANCELLED_PREPAYMENT',
    'order',
    v_order.id,
    pg_catalog.jsonb_build_object(
      'idempotencyKey', p_idempotency_key,
      'fromStatus', v_order.status,
      'version', v_order.version + 1
    )
  );

  v_response := dastak_v1_api.order_json(v_order.id, p_actor_id);

  insert into dastak_v1.idempotency_records (
    actor_id,
    command_name,
    idempotency_key,
    request_hash,
    response_body,
    response_status,
    resource_id
  ) values (
    p_actor_id,
    v_command,
    p_idempotency_key,
    v_request_hash,
    v_response,
    200,
    v_order.id
  );

  return v_response;
end;
$$;

create function dastak_v1_api.get_order(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_response jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  v_response := dastak_v1_api.order_json(p_order_id, p_actor_id);

  if v_response is null then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id
  ) values (p_actor_id, 'ORDER_READ', 'order', p_order_id);

  return v_response;
end;
$$;

create function dastak_v1_api.list_customer_orders(
  p_actor_id uuid,
  p_limit integer,
  p_before_created_at timestamptz,
  p_before_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_orders jsonb;
  v_next_created_at timestamptz;
  v_next_order_id uuid;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);

  if (p_before_created_at is null) <> (p_before_order_id is null) then
    raise exception using
      errcode = '22023',
      message = 'both pagination cursor values are required together';
  end if;

  with selected_orders as (
    select customer_order.id, customer_order.created_at
    from dastak_v1.orders customer_order
    where customer_order.customer_id = p_actor_id
      and (
        p_before_created_at is null
        or (customer_order.created_at, customer_order.id)
          < (p_before_created_at, p_before_order_id)
      )
    order by customer_order.created_at desc, customer_order.id desc
    limit v_limit
  )
  select
    coalesce(
      pg_catalog.jsonb_agg(
        dastak_v1_api.order_json(selected_order.id, p_actor_id)
        order by selected_order.created_at desc, selected_order.id desc
      ),
      '[]'::jsonb
    ),
    (
      array_agg(selected_order.created_at order by selected_order.created_at, selected_order.id)
    )[1],
    (
      array_agg(selected_order.id order by selected_order.created_at, selected_order.id)
    )[1]
  into v_orders, v_next_created_at, v_next_order_id
  from selected_orders selected_order;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, metadata
  ) values (
    p_actor_id,
    'CUSTOMER_ORDERS_LISTED',
    'order',
    pg_catalog.jsonb_build_object('resultCount', jsonb_array_length(v_orders))
  );

  return pg_catalog.jsonb_build_object(
    'orders', v_orders,
    'nextCursor', case
      when jsonb_array_length(v_orders) = v_limit then
        pg_catalog.jsonb_build_object(
          'createdAt', v_next_created_at,
          'orderId', v_next_order_id
        )
      else null
    end
  );
end;
$$;

create function public.dastak_v1_submit_order(
  p_idempotency_key text,
  p_expected_version bigint,
  p_order jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.submit_order(
    auth.uid(),
    p_idempotency_key,
    p_expected_version,
    p_order
  );
$$;

create function public.dastak_v1_cancel_prepayment_order(
  p_order_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.cancel_prepayment_order(
    auth.uid(),
    p_order_id,
    p_idempotency_key,
    p_expected_version
  );
$$;

create function public.dastak_v1_get_order(p_order_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.get_order(auth.uid(), p_order_id);
$$;

create function public.dastak_v1_list_customer_orders(
  p_limit integer default 20,
  p_before_created_at timestamptz default null,
  p_before_order_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.list_customer_orders(
    auth.uid(),
    p_limit,
    p_before_created_at,
    p_before_order_id
  );
$$;

revoke execute on all functions in schema dastak_v1_api
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_submit_order(text, bigint, jsonb)
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_cancel_prepayment_order(uuid, text, bigint)
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_get_order(uuid)
  from public, anon, authenticated;
revoke execute on function public.dastak_v1_list_customer_orders(integer, timestamptz, uuid)
  from public, anon, authenticated;

grant usage on schema dastak_v1_api to authenticated;
grant execute on function dastak_v1_api.submit_order(uuid, text, bigint, jsonb)
  to authenticated;
grant execute on function dastak_v1_api.cancel_prepayment_order(uuid, uuid, text, bigint)
  to authenticated;
grant execute on function dastak_v1_api.get_order(uuid, uuid)
  to authenticated;
grant execute on function dastak_v1_api.list_customer_orders(uuid, integer, timestamptz, uuid)
  to authenticated;

grant execute on function public.dastak_v1_submit_order(text, bigint, jsonb)
  to authenticated;
grant execute on function public.dastak_v1_cancel_prepayment_order(uuid, text, bigint)
  to authenticated;
grant execute on function public.dastak_v1_get_order(uuid)
  to authenticated;
grant execute on function public.dastak_v1_list_customer_orders(integer, timestamptz, uuid)
  to authenticated;

comment on function public.dastak_v1_submit_order(text, bigint, jsonb) is
  'V1 submitOrder command. Creates no payment, matching or fulfilment side effects.';
comment on function public.dastak_v1_cancel_prepayment_order(uuid, text, bigint) is
  'V1 cancelPrepaymentOrder command. Customer cancellation is impossible after payment.';
comment on function public.dastak_v1_get_order(uuid) is
  'V1 getOrder read model with an explicit customer-safe field allowlist.';
comment on function public.dastak_v1_list_customer_orders(integer, timestamptz, uuid) is
  'V1 listCustomerOrders keyset-paginated read model.';
