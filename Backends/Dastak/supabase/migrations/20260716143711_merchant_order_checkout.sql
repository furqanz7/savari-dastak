create table private.merchant_order_rate_cards (
  id uuid primary key default gen_random_uuid(),
  service_zone_id uuid not null unique references public.service_zones(id),
  delivery_fee_paise integer not null check (
    delivery_fee_paise between 0 and 100000000
  ),
  version bigint not null default 1 check (version > 0),
  active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table private.merchant_order_quotes (
  id uuid primary key default gen_random_uuid(),
  customer_account_id uuid not null references public.accounts(id),
  store_id uuid not null references private.merchant_stores(id),
  rate_card_id uuid not null references private.merchant_order_rate_cards(id),
  rate_card_version bigint not null check (rate_card_version > 0),
  dropoff extensions.geometry(Point, 4326) not null,
  item_subtotal_paise bigint not null check (item_subtotal_paise > 0),
  delivery_fee_paise integer not null check (delivery_fee_paise >= 0),
  total_paise bigint not null check (
    total_paise = item_subtotal_paise + delivery_fee_paise
  ),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at),
  check (consumed_at is null or consumed_at >= created_at)
);

create index merchant_order_quotes_customer_idx
  on private.merchant_order_quotes (customer_account_id, created_at desc);
create index merchant_order_quotes_store_idx
  on private.merchant_order_quotes (store_id);
create index merchant_order_quotes_rate_card_idx
  on private.merchant_order_quotes (rate_card_id);
create index merchant_order_quotes_expiry_idx
  on private.merchant_order_quotes (expires_at)
  where consumed_at is null;

create table private.merchant_order_quote_lines (
  quote_id uuid not null references private.merchant_order_quotes(id) on delete cascade,
  product_id uuid not null references private.catalogue_products(id),
  product_name text not null check (char_length(trim(product_name)) between 1 and 160),
  unit_label text not null check (char_length(trim(unit_label)) between 1 and 40),
  unit_price_paise integer not null check (unit_price_paise > 0),
  quantity integer not null check (quantity between 1 and 99),
  line_subtotal_paise bigint not null check (
    line_subtotal_paise = unit_price_paise::bigint * quantity
  ),
  primary key (quote_id, product_id)
);

create index merchant_order_quote_lines_product_idx
  on private.merchant_order_quote_lines (product_id);

create table private.merchant_orders (
  id uuid primary key default gen_random_uuid(),
  customer_account_id uuid not null references public.accounts(id),
  store_id uuid not null references private.merchant_stores(id),
  service_zone_id uuid not null references public.service_zones(id),
  quote_id uuid not null unique references private.merchant_order_quotes(id),
  status text not null check (
    status in (
      'payment_pending', 'paid', 'merchant_accepted', 'ready', 'assigned',
      'en_route_to_pickup', 'picked_up', 'in_transit', 'delivered',
      'cancelled', 'returning_to_merchant'
    )
  ),
  payment_state text not null check (
    payment_state in (
      'payment_pending', 'paid', 'not_collected', 'refund_pending', 'refunded'
    )
  ),
  dropoff extensions.geometry(Point, 4326) not null,
  item_subtotal_paise bigint not null check (item_subtotal_paise > 0),
  delivery_fee_paise integer not null check (delivery_fee_paise >= 0),
  total_paise bigint not null check (
    total_paise = item_subtotal_paise + delivery_fee_paise
  ),
  provider_payment_reference text unique check (
    provider_payment_reference is null
    or char_length(trim(provider_payment_reference)) between 1 and 200
  ),
  state_version bigint not null default 1 check (state_version > 0),
  accepted_at timestamptz,
  ready_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index merchant_orders_customer_idx
  on private.merchant_orders (customer_account_id, created_at desc);
create index merchant_orders_store_idx
  on private.merchant_orders (store_id, status, created_at desc);
create index merchant_orders_service_zone_idx
  on private.merchant_orders (service_zone_id);

create table private.merchant_order_lines (
  order_id uuid not null references private.merchant_orders(id) on delete cascade,
  product_id uuid not null references private.catalogue_products(id),
  product_name text not null check (char_length(trim(product_name)) between 1 and 160),
  unit_label text not null check (char_length(trim(unit_label)) between 1 and 40),
  unit_price_paise integer not null check (unit_price_paise > 0),
  quantity integer not null check (quantity between 1 and 99),
  line_subtotal_paise bigint not null check (
    line_subtotal_paise = unit_price_paise::bigint * quantity
  ),
  primary key (order_id, product_id)
);

create index merchant_order_lines_product_idx
  on private.merchant_order_lines (product_id);

create table private.merchant_order_refund_decisions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references private.merchant_orders(id),
  requested_by_account_id uuid references public.accounts(id),
  source text not null check (source in ('customer', 'merchant', 'owner', 'system')),
  order_status text not null,
  eligibility text not null check (
    eligibility in (
      'no_payment', 'full_refund', 'owner_review_required',
      'merchant_fault_full_refund', 'delivery_fee_retained_unless_fault'
    )
  ),
  decision_status text not null check (
    decision_status in ('not_required', 'eligible', 'review_required', 'denied')
  ),
  item_refund_paise bigint,
  delivery_fee_refund_paise integer,
  reason text not null check (char_length(trim(reason)) between 1 and 300),
  created_at timestamptz not null default now(),
  check (
    (
      eligibility = 'no_payment'
      and decision_status = 'not_required'
      and item_refund_paise = 0
      and delivery_fee_refund_paise = 0
    )
    or (
      eligibility in ('full_refund', 'merchant_fault_full_refund')
      and decision_status = 'eligible'
      and item_refund_paise is not null
      and item_refund_paise >= 0
      and delivery_fee_refund_paise is not null
      and delivery_fee_refund_paise >= 0
    )
    or (
      eligibility in (
        'owner_review_required', 'delivery_fee_retained_unless_fault'
      )
      and decision_status = 'review_required'
      and item_refund_paise is null
      and delivery_fee_refund_paise is null
    )
    or decision_status = 'denied'
  )
);

create index merchant_order_refund_decisions_order_idx
  on private.merchant_order_refund_decisions (order_id, created_at desc);
create index merchant_order_refund_decisions_requester_idx
  on private.merchant_order_refund_decisions (requested_by_account_id)
  where requested_by_account_id is not null;

alter table private.merchant_order_rate_cards enable row level security;
alter table private.merchant_order_quotes enable row level security;
alter table private.merchant_order_quote_lines enable row level security;
alter table private.merchant_orders enable row level security;
alter table private.merchant_order_lines enable row level security;
alter table private.merchant_order_refund_decisions enable row level security;

revoke all on table private.merchant_order_rate_cards from public, anon, authenticated;
revoke all on table private.merchant_order_quotes from public, anon, authenticated;
revoke all on table private.merchant_order_quote_lines from public, anon, authenticated;
revoke all on table private.merchant_orders from public, anon, authenticated;
revoke all on table private.merchant_order_lines from public, anon, authenticated;
revoke all on table private.merchant_order_refund_decisions from public, anon, authenticated;

grant select, insert, update on table private.merchant_order_rate_cards to service_role;
grant select, insert, update on table private.merchant_order_quotes to service_role;
grant select, insert on table private.merchant_order_quote_lines to service_role;
grant select, insert, update on table private.merchant_orders to service_role;
grant select, insert on table private.merchant_order_lines to service_role;
grant select, insert on table private.merchant_order_refund_decisions to service_role;

create or replace function private.reject_merchant_order_financial_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'merchant order financial ledger is append-only';
end;
$$;

revoke execute on function private.reject_merchant_order_financial_mutation()
  from public, anon, authenticated;
grant execute on function private.reject_merchant_order_financial_mutation()
  to service_role;

create trigger merchant_order_quote_lines_immutable
before update or delete on private.merchant_order_quote_lines
for each row execute function private.reject_merchant_order_financial_mutation();

create trigger merchant_order_lines_immutable
before update or delete on private.merchant_order_lines
for each row execute function private.reject_merchant_order_financial_mutation();

create trigger merchant_order_refund_decisions_immutable
before update or delete on private.merchant_order_refund_decisions
for each row execute function private.reject_merchant_order_financial_mutation();

create or replace function private.merchant_order_rate_card_json(
  rate_row private.merchant_order_rate_cards
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'rateCardId', (rate_row).id,
    'serviceZoneId', (rate_row).service_zone_id,
    'deliveryFee', pg_catalog.jsonb_build_object(
      'paise', (rate_row).delivery_fee_paise
    ),
    'version', (rate_row).version,
    'active', (rate_row).active
  );
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
    'total', pg_catalog.jsonb_build_object('paise', (quote_row).total_paise),
    'dropoff', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((quote_row).dropoff),
      'longitude', extensions.st_x((quote_row).dropoff)
    ),
    'expiresAt', (quote_row).expires_at
  );
$$;

create or replace function private.merchant_order_refund_json(
  decision_row private.merchant_order_refund_decisions
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when (decision_row).id is null then null
    else pg_catalog.jsonb_build_object(
      'decisionId', (decision_row).id,
      'eligibility', (decision_row).eligibility,
      'decisionStatus', (decision_row).decision_status,
      'itemRefund', case
        when (decision_row).item_refund_paise is null then null
        else pg_catalog.jsonb_build_object(
          'paise', (decision_row).item_refund_paise
        )
      end,
      'deliveryFeeRefund', case
        when (decision_row).delivery_fee_refund_paise is null then null
        else pg_catalog.jsonb_build_object(
          'paise', (decision_row).delivery_fee_refund_paise
        )
      end,
      'reason', (decision_row).reason,
      'createdAt', (decision_row).created_at
    )
  end;
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

revoke execute on function private.merchant_order_rate_card_json(
  private.merchant_order_rate_cards
) from public, anon, authenticated;
revoke execute on function private.merchant_order_quote_json(
  private.merchant_order_quotes
) from public, anon, authenticated;
revoke execute on function private.merchant_order_refund_json(
  private.merchant_order_refund_decisions
) from public, anon, authenticated;
revoke execute on function private.merchant_order_json(private.merchant_orders)
  from public, anon, authenticated;

grant execute on function private.merchant_order_rate_card_json(
  private.merchant_order_rate_cards
) to service_role;
grant execute on function private.merchant_order_quote_json(
  private.merchant_order_quotes
) to service_role;
grant execute on function private.merchant_order_refund_json(
  private.merchant_order_refund_decisions
) to service_role;
grant execute on function private.merchant_order_json(private.merchant_orders)
  to service_role;

create or replace function public.upsert_merchant_order_rate_card(
  p_account_id uuid,
  p_service_zone_id uuid,
  p_delivery_fee_paise integer,
  p_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_merchant_order_rate_card';
  v_existing_dedup private.request_deduplication%rowtype;
  v_rate private.merchant_order_rate_cards%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_changed boolean := false;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
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
        'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_service_zone_id is null
    or p_delivery_fee_paise is null
    or p_delivery_fee_paise not between 0 and 100000000
    or p_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant order rate-card request is invalid.'
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

  perform 1
  from public.service_zones as zone
  where zone.id = p_service_zone_id
    and zone.active = true
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'An active Dastak service zone is required.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_service_zone_id::text || ':merchant_order_rate', 0)
  );

  select rate.*
  into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.service_zone_id = p_service_zone_id
  for update;

  if found then
    v_before_state := private.merchant_order_rate_card_json(v_rate);
    if v_rate.delivery_fee_paise <> p_delivery_fee_paise
      or v_rate.active <> p_active
    then
      update private.merchant_order_rate_cards as rate
      set delivery_fee_paise = p_delivery_fee_paise,
          active = p_active,
          version = rate.version + 1,
          updated_at = pg_catalog.now()
      where rate.id = v_rate.id
      returning rate.* into v_rate;
      v_changed := true;
    end if;
  else
    insert into private.merchant_order_rate_cards (
      service_zone_id, delivery_fee_paise, active
    ) values (
      p_service_zone_id, p_delivery_fee_paise, p_active
    )
    returning * into v_rate;
    v_changed := true;
  end if;

  v_response_body := private.merchant_order_rate_card_json(v_rate);

  if v_changed then
    insert into audit.events (
      actor_id, action, entity_type, entity_id, before_state, after_state
    ) values (
      p_account_id,
      'merchant_order_rate_card_upserted',
      'merchant_order_rate_card',
      v_rate.id,
      v_before_state,
      v_response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.quote_merchant_order(
  p_account_id uuid,
  p_store_id uuid,
  p_lines jsonb,
  p_dropoff_latitude double precision,
  p_dropoff_longitude double precision,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'quote_merchant_order';
  v_existing_dedup private.request_deduplication%rowtype;
  v_store private.merchant_stores%rowtype;
  v_rate private.merchant_order_rate_cards%rowtype;
  v_quote private.merchant_order_quotes%rowtype;
  v_dropoff extensions.geometry(Point, 4326);
  v_requested_count integer;
  v_matched_count integer;
  v_item_subtotal bigint;
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

  if p_store_id is null
    or p_lines is null
    or pg_catalog.jsonb_typeof(p_lines) <> 'array'
    or pg_catalog.jsonb_array_length(p_lines) not between 1 and 50
    or p_dropoff_latitude is null
    or p_dropoff_latitude < -90 or p_dropoff_latitude > 90
    or p_dropoff_longitude is null
    or p_dropoff_longitude < -180 or p_dropoff_longitude > 180
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant order quote request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_lines) as requested(line)
    where pg_catalog.jsonb_typeof(requested.line) <> 'object'
      or coalesce(requested.line ->> 'productId', '') !~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or case
        when coalesce(requested.line ->> 'quantity', '') ~ '^[0-9]+$'
          then (requested.line ->> 'quantity')::numeric not between 1 and 99
        else true
      end
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Each merchant order line requires one product and quantity.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if exists (
    select (requested.line ->> 'productId')::uuid
    from pg_catalog.jsonb_array_elements(p_lines) as requested(line)
    group by (requested.line ->> 'productId')::uuid
    having pg_catalog.count(*) > 1
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A product may appear only once in a merchant order.'
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
  where store.id = p_store_id
    and store.is_published = true
    and store.accepting_orders = true
  for share of store;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'store_unavailable',
        'message', 'The merchant is not accepting orders.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_dropoff := extensions.st_setsrid(
    extensions.st_makepoint(p_dropoff_longitude, p_dropoff_latitude),
    4326
  );

  perform 1
  from public.service_zones as zone
  where zone.id = v_store.service_zone_id
    and zone.active = true
    and extensions.st_covers(zone.boundary, v_dropoff)
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'The delivery point must be inside the merchant service area.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  select rate.*
  into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.service_zone_id = v_store.service_zone_id
    and rate.active = true
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'pricing_unavailable',
        'message', 'Checkout pricing is not configured for this service area.'
      )
    );
    response_status := 503;
    return next;
    return;
  end if;

  perform 1
  from pg_catalog.jsonb_array_elements(p_lines) as source(line)
  join private.catalogue_products as product
    on product.id = (source.line ->> 'productId')::uuid
  join private.catalogue_categories as category
    on category.id = product.category_id
    and category.store_id = product.store_id
  where product.store_id = v_store.id
  for share of product, category;

  v_requested_count := pg_catalog.jsonb_array_length(p_lines);

  with requested as (
    select
      (line ->> 'productId')::uuid as product_id,
      (line ->> 'quantity')::integer as quantity
    from pg_catalog.jsonb_array_elements(p_lines) as source(line)
  )
  select
    pg_catalog.count(product.id)::integer,
    coalesce(
      pg_catalog.sum(product.price_paise::bigint * requested.quantity),
      0
    )
  into v_matched_count, v_item_subtotal
  from requested
  join private.catalogue_products as product
    on product.id = requested.product_id
  join private.catalogue_categories as category
    on category.id = product.category_id
    and category.store_id = product.store_id
  where product.store_id = v_store.id
    and product.is_active = true
    and product.availability = 'in_stock'
    and product.catalogue_kind = 'general'
    and product.restricted_approval_state = 'not_applicable'
    and category.is_active = true;

  if v_matched_count <> v_requested_count or v_item_subtotal <= 0 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_changed',
        'message', 'One or more products are no longer available for checkout.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into private.merchant_order_quotes (
    customer_account_id, store_id, rate_card_id, rate_card_version,
    dropoff, item_subtotal_paise, delivery_fee_paise, total_paise,
    expires_at
  ) values (
    p_account_id,
    v_store.id,
    v_rate.id,
    v_rate.version,
    v_dropoff,
    v_item_subtotal,
    v_rate.delivery_fee_paise,
    v_item_subtotal + v_rate.delivery_fee_paise,
    pg_catalog.now() + interval '5 minutes'
  )
  returning * into v_quote;

  with requested as (
    select
      (line ->> 'productId')::uuid as product_id,
      (line ->> 'quantity')::integer as quantity
    from pg_catalog.jsonb_array_elements(p_lines) as source(line)
  )
  insert into private.merchant_order_quote_lines (
    quote_id, product_id, product_name, unit_label,
    unit_price_paise, quantity, line_subtotal_paise
  )
  select
    v_quote.id,
    product.id,
    product.name,
    product.unit_label,
    product.price_paise,
    requested.quantity,
    product.price_paise::bigint * requested.quantity
  from requested
  join private.catalogue_products as product on product.id = requested.product_id
  join private.catalogue_categories as category
    on category.id = product.category_id
    and category.store_id = product.store_id
  where product.store_id = v_store.id
    and product.is_active = true
    and product.availability = 'in_stock'
    and product.catalogue_kind = 'general'
    and product.restricted_approval_state = 'not_applicable'
    and category.is_active = true;

  v_response_body := private.merchant_order_quote_json(v_quote);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, after_state
  ) values (
    p_account_id,
    'merchant_order_quoted',
    'merchant_order_quote',
    v_quote.id,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

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
  v_rate private.merchant_order_rate_cards%rowtype;
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

  select rate.*
  into v_rate
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

create or replace function public.confirm_merchant_order_payment(
  p_order_id uuid,
  p_provider_reference text,
  p_amount_paise bigint,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'confirm_merchant_order_payment';
  v_customer_account_id uuid;
  v_existing_dedup private.request_deduplication%rowtype;
  v_order private.merchant_orders%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
begin
  if p_order_id is null
    or p_provider_reference is null
    or pg_catalog.char_length(pg_catalog.btrim(p_provider_reference)) not between 1 and 200
    or p_amount_paise is null
    or p_amount_paise < 0
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The provider payment confirmation is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select merchant_order.customer_account_id
  into v_customer_account_id
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_customer_account_id::text || ':' || v_function_name,
      0
    )
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = v_customer_account_id
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

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
  for update;

  if p_amount_paise <> v_order.total_paise then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'payment_amount_mismatch',
        'message', 'The confirmed payment does not match the server order total.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_order.status <> 'payment_pending'
    or v_order.payment_state <> 'payment_pending'
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order cannot accept a payment confirmation in its current state.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_before_state := private.merchant_order_json(v_order);

  update private.merchant_orders as merchant_order
  set status = 'paid',
      payment_state = 'paid',
      provider_payment_reference = pg_catalog.btrim(p_provider_reference),
      state_version = merchant_order.state_version + 1,
      updated_at = pg_catalog.now()
  where merchant_order.id = v_order.id
  returning merchant_order.* into v_order;

  v_response_body := private.merchant_order_json(v_order);

  insert into audit.events (
    action, entity_type, entity_id, before_state, after_state
  ) values (
    'merchant_order_payment_confirmed',
    'merchant_order',
    v_order.id,
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    v_customer_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_customer_orders(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_orders jsonb;
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

  select coalesce(
    pg_catalog.jsonb_agg(
      private.merchant_order_json(merchant_order)
      order by merchant_order.created_at desc, merchant_order.id desc
    ),
    '[]'::jsonb
  )
  into v_orders
  from private.merchant_orders as merchant_order
  where merchant_order.customer_account_id = p_account_id;

  response_body := pg_catalog.jsonb_build_object('orders', v_orders);
  response_status := 200;
  return next;
end;
$$;

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
      private.merchant_order_json(merchant_order)
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

create or replace function public.merchant_accept_order(
  p_account_id uuid,
  p_order_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'merchant_accept_order';
  v_existing_dedup private.request_deduplication%rowtype;
  v_store_id uuid;
  v_order private.merchant_orders%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
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

  if p_order_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant acceptance request is invalid.'
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

  select store.id
  into v_store_id
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id;

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
    and merchant_order.store_id = v_store_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'This merchant cannot manage the requested order.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if v_order.status <> 'paid' or v_order.payment_state <> 'paid' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'Only a paid order can be accepted.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_before_state := private.merchant_order_json(v_order);

  update private.merchant_orders as merchant_order
  set status = 'merchant_accepted',
      accepted_at = pg_catalog.now(),
      state_version = merchant_order.state_version + 1,
      updated_at = pg_catalog.now()
  where merchant_order.id = v_order.id
  returning merchant_order.* into v_order;

  v_response_body := private.merchant_order_json(v_order);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id,
    'merchant_order_accepted',
    'merchant_order',
    v_order.id,
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.merchant_mark_order_ready(
  p_account_id uuid,
  p_order_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'merchant_mark_order_ready';
  v_existing_dedup private.request_deduplication%rowtype;
  v_store_id uuid;
  v_order private.merchant_orders%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
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

  if p_order_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant readiness request is invalid.'
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

  select store.id
  into v_store_id
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id;

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
    and merchant_order.store_id = v_store_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'This merchant cannot manage the requested order.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if v_order.status <> 'merchant_accepted' or v_order.payment_state <> 'paid' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'Only an accepted paid order can be marked ready.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_before_state := private.merchant_order_json(v_order);

  update private.merchant_orders as merchant_order
  set status = 'ready',
      ready_at = pg_catalog.now(),
      state_version = merchant_order.state_version + 1,
      updated_at = pg_catalog.now()
  where merchant_order.id = v_order.id
  returning merchant_order.* into v_order;

  v_response_body := private.merchant_order_json(v_order);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id,
    'merchant_order_ready',
    'merchant_order',
    v_order.id,
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.merchant_reject_order(
  p_account_id uuid,
  p_order_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'merchant_reject_order';
  v_existing_dedup private.request_deduplication%rowtype;
  v_store_id uuid;
  v_order private.merchant_orders%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_order_status text;
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

  if p_order_id is null
    or p_reason is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 1 and 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant rejection request is invalid.'
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

  select store.id
  into v_store_id
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id;

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
    and merchant_order.store_id = v_store_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'This merchant cannot manage the requested order.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if v_order.status not in ('paid', 'merchant_accepted', 'ready')
    or v_order.payment_state <> 'paid'
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order cannot be rejected in its current state.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_order_status := v_order.status;
  v_before_state := private.merchant_order_json(v_order);

  update private.merchant_orders as merchant_order
  set status = 'cancelled',
      payment_state = 'refund_pending',
      cancelled_at = pg_catalog.now(),
      state_version = merchant_order.state_version + 1,
      updated_at = pg_catalog.now()
  where merchant_order.id = v_order.id
  returning merchant_order.* into v_order;

  insert into private.merchant_order_refund_decisions (
    order_id, requested_by_account_id, source, order_status,
    eligibility, decision_status, item_refund_paise,
    delivery_fee_refund_paise, reason
  ) values (
    v_order.id,
    p_account_id,
    'merchant',
    v_order_status,
    'merchant_fault_full_refund',
    'eligible',
    v_order.item_subtotal_paise,
    v_order.delivery_fee_paise,
    pg_catalog.btrim(p_reason)
  );

  v_response_body := private.merchant_order_json(v_order);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason, before_state, after_state
  ) values (
    p_account_id,
    'merchant_order_rejected',
    'merchant_order',
    v_order.id,
    pg_catalog.btrim(p_reason),
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.customer_cancel_order(
  p_account_id uuid,
  p_order_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'customer_cancel_order';
  v_existing_dedup private.request_deduplication%rowtype;
  v_order private.merchant_orders%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_response_status integer;
  v_order_status text;
  v_eligibility text;
  v_decision_status text;
  v_item_refund_paise bigint;
  v_delivery_fee_refund_paise integer;
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

  if p_order_id is null
    or p_reason is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 1 and 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The customer cancellation request is invalid.'
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

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
    and merchant_order.customer_account_id = p_account_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  if v_order.status = 'cancelled' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'The merchant order is already cancelled.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_order_status := v_order.status;
  v_before_state := private.merchant_order_json(v_order);

  if v_order.status = 'payment_pending'
    and v_order.payment_state = 'payment_pending'
  then
    update private.merchant_orders as merchant_order
    set status = 'cancelled',
        payment_state = 'not_collected',
        cancelled_at = pg_catalog.now(),
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning merchant_order.* into v_order;

    v_eligibility := 'no_payment';
    v_decision_status := 'not_required';
    v_item_refund_paise := 0;
    v_delivery_fee_refund_paise := 0;
    v_response_status := 200;
  elsif v_order.status = 'paid' and v_order.payment_state = 'paid' then
    update private.merchant_orders as merchant_order
    set status = 'cancelled',
        payment_state = 'refund_pending',
        cancelled_at = pg_catalog.now(),
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning merchant_order.* into v_order;

    v_eligibility := 'full_refund';
    v_decision_status := 'eligible';
    v_item_refund_paise := v_order.item_subtotal_paise;
    v_delivery_fee_refund_paise := v_order.delivery_fee_paise;
    v_response_status := 200;
  elsif v_order.status in (
    'merchant_accepted', 'ready', 'assigned', 'en_route_to_pickup', 'delivered'
  ) then
    v_eligibility := 'owner_review_required';
    v_decision_status := 'review_required';
    v_item_refund_paise := null;
    v_delivery_fee_refund_paise := null;
    v_response_status := 202;
  elsif v_order.status in ('picked_up', 'in_transit', 'returning_to_merchant') then
    v_eligibility := 'delivery_fee_retained_unless_fault';
    v_decision_status := 'review_required';
    v_item_refund_paise := null;
    v_delivery_fee_refund_paise := null;
    v_response_status := 202;
  else
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order cannot be cancelled in its current state.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into private.merchant_order_refund_decisions (
    order_id, requested_by_account_id, source, order_status,
    eligibility, decision_status, item_refund_paise,
    delivery_fee_refund_paise, reason
  ) values (
    v_order.id,
    p_account_id,
    'customer',
    v_order_status,
    v_eligibility,
    v_decision_status,
    v_item_refund_paise,
    v_delivery_fee_refund_paise,
    pg_catalog.btrim(p_reason)
  );

  v_response_body := private.merchant_order_json(v_order);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason, before_state, after_state
  ) values (
    p_account_id,
    'merchant_order_cancellation_requested',
    'merchant_order',
    v_order.id,
    pg_catalog.btrim(p_reason),
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, v_response_status
  );

  response_body := v_response_body;
  response_status := v_response_status;
  return next;
end;
$$;

revoke execute on function public.upsert_merchant_order_rate_card(
  uuid, uuid, integer, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_merchant_order_rate_card(
  uuid, uuid, integer, boolean, text, text
) to service_role;

revoke execute on function public.quote_merchant_order(
  uuid, uuid, jsonb, double precision, double precision, text, text
) from public, anon, authenticated;
grant execute on function public.quote_merchant_order(
  uuid, uuid, jsonb, double precision, double precision, text, text
) to service_role;

revoke execute on function public.create_merchant_order(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.create_merchant_order(
  uuid, uuid, text, text
) to service_role;

revoke execute on function public.confirm_merchant_order_payment(
  uuid, text, bigint, text, text
) from public, anon, authenticated;
grant execute on function public.confirm_merchant_order_payment(
  uuid, text, bigint, text, text
) to service_role;

revoke execute on function public.merchant_accept_order(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.merchant_accept_order(
  uuid, uuid, text, text
) to service_role;

revoke execute on function public.merchant_reject_order(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.merchant_reject_order(
  uuid, uuid, text, text, text
) to service_role;

revoke execute on function public.merchant_mark_order_ready(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.merchant_mark_order_ready(
  uuid, uuid, text, text
) to service_role;

revoke execute on function public.customer_cancel_order(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.customer_cancel_order(
  uuid, uuid, text, text, text
) to service_role;

revoke execute on function public.get_customer_orders(uuid)
  from public, anon, authenticated;
grant execute on function public.get_customer_orders(uuid) to service_role;

revoke execute on function public.get_merchant_orders(uuid)
  from public, anon, authenticated;
grant execute on function public.get_merchant_orders(uuid) to service_role;
