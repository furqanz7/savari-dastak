create table private.customer_delivery_addresses (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.accounts(id) on delete cascade,
  label text not null check (
    pg_catalog.char_length(pg_catalog.btrim(label)) between 1 and 40
  ),
  address text not null check (
    pg_catalog.char_length(pg_catalog.btrim(address)) between 1 and 300
  ),
  details text not null check (
    pg_catalog.char_length(pg_catalog.btrim(details)) between 1 and 300
  ),
  location extensions.geometry(Point, 4326) not null,
  is_default boolean not null default false,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create unique index customer_delivery_addresses_default_uidx
  on private.customer_delivery_addresses(account_id)
  where is_default;
create index customer_delivery_addresses_account_idx
  on private.customer_delivery_addresses(account_id, updated_at desc);

alter table private.customer_delivery_addresses enable row level security;
revoke all on table private.customer_delivery_addresses
  from public, anon, authenticated;
grant select, insert, update, delete on table private.customer_delivery_addresses
  to service_role;

create function private.customer_delivery_address_json(
  address_row private.customer_delivery_addresses
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when (address_row).id is null then null
    else pg_catalog.jsonb_build_object(
      'addressId', (address_row).id,
      'label', (address_row).label,
      'address', (address_row).address,
      'details', (address_row).details,
      'displayAddress', (address_row).details || ', ' || (address_row).address,
      'location', pg_catalog.jsonb_build_object(
        'latitude', extensions.st_y((address_row).location),
        'longitude', extensions.st_x((address_row).location)
      ),
      'isDefault', (address_row).is_default,
      'updatedAt', (address_row).updated_at
    )
  end;
$$;

create function public.get_customer_delivery_addresses(p_account_id uuid)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.accounts as account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete your Dastak profile before saving an address.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'addresses', coalesce(
      (
        select pg_catalog.jsonb_agg(
          private.customer_delivery_address_json(address)
          order by address.is_default desc, address.updated_at desc, address.id
        )
        from private.customer_delivery_addresses as address
        where address.account_id = p_account_id
      ),
      '[]'::jsonb
    )
  );
  response_status := 200;
  return next;
end;
$$;

create function public.save_default_customer_delivery_address(
  p_account_id uuid,
  p_label text,
  p_address text,
  p_details text,
  p_latitude double precision,
  p_longitude double precision,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_address private.customer_delivery_addresses%rowtype;
  v_existing private.request_deduplication%rowtype;
  v_function_name constant text := 'save_default_customer_delivery_address';
  v_location extensions.geometry(Point, 4326);
begin
  if p_account_id is null
    or nullif(pg_catalog.btrim(p_label), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_label)) > 40
    or nullif(pg_catalog.btrim(p_address), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_address)) > 300
    or nullif(pg_catalog.btrim(p_details), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_details)) > 300
    or p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A complete delivery address is required.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used for another address.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if not exists (
    select 1 from public.accounts as account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete your Dastak profile before saving an address.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_location := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude),
    4326
  );

  select address.* into v_address
  from private.customer_delivery_addresses as address
  where address.account_id = p_account_id and address.is_default
  for update;

  if found then
    update private.customer_delivery_addresses as address
    set label = pg_catalog.btrim(p_label),
        address = pg_catalog.btrim(p_address),
        details = pg_catalog.btrim(p_details),
        location = v_location,
        updated_at = pg_catalog.now()
    where address.id = v_address.id
    returning address.* into v_address;
  else
    insert into private.customer_delivery_addresses (
      account_id, label, address, details, location, is_default
    ) values (
      p_account_id,
      pg_catalog.btrim(p_label),
      pg_catalog.btrim(p_address),
      pg_catalog.btrim(p_details),
      v_location,
      true
    ) returning * into v_address;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'addresses', pg_catalog.jsonb_build_array(
      private.customer_delivery_address_json(v_address)
    )
  );
  response_status := 200;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    p_request_digest, response_body, response_status
  );

  insert into audit.events (
    actor_id, action, entity_type, entity_id, after_state
  ) values (
    p_account_id, 'customer_delivery_address_saved',
    'customer_delivery_address', v_address.id,
    private.customer_delivery_address_json(v_address)
  );

  return next;
end;
$$;

revoke execute on function private.customer_delivery_address_json(
  private.customer_delivery_addresses
) from public, anon, authenticated;
revoke execute on function public.get_customer_delivery_addresses(uuid)
  from public, anon, authenticated;
revoke execute on function public.save_default_customer_delivery_address(
  uuid, text, text, text, double precision, double precision, text, text
) from public, anon, authenticated;
grant execute on function private.customer_delivery_address_json(
  private.customer_delivery_addresses
) to service_role;
grant execute on function public.get_customer_delivery_addresses(uuid)
  to service_role;
grant execute on function public.save_default_customer_delivery_address(
  uuid, text, text, text, double precision, double precision, text, text
) to service_role;

alter table private.merchant_order_quotes
  add column dropoff_address_id uuid references private.customer_delivery_addresses(id),
  add column dropoff_label text,
  add column dropoff_address text,
  add column dropoff_details text;

alter table private.merchant_orders
  add column dropoff_address_id uuid references private.customer_delivery_addresses(id),
  add column dropoff_label text,
  add column dropoff_address text,
  add column dropoff_details text;

create function private.snapshot_merchant_quote_delivery_address()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_address private.customer_delivery_addresses%rowtype;
begin
  select address.* into v_address
  from private.customer_delivery_addresses as address
  where address.account_id = new.customer_account_id
    and address.is_default
    and extensions.st_dwithin(
      address.location::extensions.geography,
      new.dropoff::extensions.geography,
      1000
    )
  order by address.updated_at desc, address.id
  limit 1;

  if found then
    new.dropoff_address_id := v_address.id;
    new.dropoff_label := v_address.label;
    new.dropoff_address := v_address.address;
    new.dropoff_details := v_address.details;
  end if;
  return new;
end;
$$;

create function private.snapshot_merchant_order_delivery_address()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_quote private.merchant_order_quotes%rowtype;
begin
  select quote.* into v_quote
  from private.merchant_order_quotes as quote
  where quote.id = new.quote_id;

  new.dropoff_address_id := v_quote.dropoff_address_id;
  new.dropoff_label := v_quote.dropoff_label;
  new.dropoff_address := v_quote.dropoff_address;
  new.dropoff_details := v_quote.dropoff_details;
  return new;
end;
$$;

create trigger merchant_quote_delivery_address_snapshot
before insert on private.merchant_order_quotes
for each row execute function private.snapshot_merchant_quote_delivery_address();

create trigger merchant_order_delivery_address_snapshot
before insert on private.merchant_orders
for each row execute function private.snapshot_merchant_order_delivery_address();

revoke execute on function private.snapshot_merchant_quote_delivery_address()
  from public, anon, authenticated;
revoke execute on function private.snapshot_merchant_order_delivery_address()
  from public, anon, authenticated;
grant execute on function private.snapshot_merchant_quote_delivery_address()
  to service_role;
grant execute on function private.snapshot_merchant_order_delivery_address()
  to service_role;

create function private.customer_courier_json(
  p_partner_account_id uuid,
  p_include_location boolean
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when account.id is null then null
    else pg_catalog.jsonb_build_object(
      'displayName', account.display_name,
      'phoneNumber', account.phone_number,
      'deliveryMethod', profile.delivery_method,
      'location', case
        when p_include_location
          and availability.location is not null
          and availability.last_seen_at > pg_catalog.now() - interval '5 minutes'
        then pg_catalog.jsonb_build_object(
          'latitude', extensions.st_y(availability.location),
          'longitude', extensions.st_x(availability.location)
        )
        else null
      end,
      'lastSeenAt', case
        when p_include_location then availability.last_seen_at
        else null
      end
    )
  end
  from public.accounts as account
  join private.delivery_partner_profiles as profile
    on profile.account_id = account.id
  left join private.delivery_partner_availability as availability
    on availability.account_id = account.id
  where account.id = p_partner_account_id;
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
            'unitPrice', pg_catalog.jsonb_build_object('paise', line.unit_price_paise),
            'quantity', line.quantity,
            'lineSubtotal', pg_catalog.jsonb_build_object('paise', line.line_subtotal_paise)
          ) order by line.product_name, line.product_id
        )
        from private.merchant_order_quote_lines as line
        where line.quote_id = (quote_row).id
      ),
      '[]'::jsonb
    ),
    'itemSubtotal', pg_catalog.jsonb_build_object('paise', (quote_row).item_subtotal_paise),
    'deliveryFee', pg_catalog.jsonb_build_object('paise', (quote_row).delivery_fee_paise),
    'deliveryDistanceMeters', (quote_row).delivery_distance_m,
    'total', pg_catalog.jsonb_build_object('paise', (quote_row).total_paise),
    'dropoff', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((quote_row).dropoff),
      'longitude', extensions.st_x((quote_row).dropoff)
    ),
    'deliveryAddress', pg_catalog.jsonb_build_object(
      'label', (quote_row).dropoff_label,
      'address', (quote_row).dropoff_address,
      'details', (quote_row).dropoff_details,
      'displayAddress', case
        when (quote_row).dropoff_address is null then null
        else pg_catalog.concat_ws(
          ', ', (quote_row).dropoff_details, (quote_row).dropoff_address
        )
      end
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
    'store', (
      select pg_catalog.jsonb_build_object(
        'name', store.name,
        'phoneNumber', account.phone_number,
        'pickup', pg_catalog.jsonb_build_object(
          'latitude', extensions.st_y(store.location),
          'longitude', extensions.st_x(store.location),
          'address', store.address
        )
      )
      from private.merchant_stores as store
      join public.accounts as account on account.id = store.merchant_account_id
      where store.id = (order_row).store_id
    ),
    'status', (order_row).status,
    'paymentState', (order_row).payment_state,
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'productId', line.product_id,
            'name', line.product_name,
            'unitLabel', line.unit_label,
            'unitPrice', pg_catalog.jsonb_build_object('paise', line.unit_price_paise),
            'quantity', line.quantity,
            'lineSubtotal', pg_catalog.jsonb_build_object('paise', line.line_subtotal_paise)
          ) order by line.product_name, line.product_id
        )
        from private.merchant_order_lines as line
        where line.order_id = (order_row).id
      ),
      '[]'::jsonb
    ),
    'itemSubtotal', pg_catalog.jsonb_build_object('paise', (order_row).item_subtotal_paise),
    'deliveryFee', pg_catalog.jsonb_build_object('paise', (order_row).delivery_fee_paise),
    'deliveryDistanceMeters', (order_row).delivery_distance_m,
    'total', pg_catalog.jsonb_build_object('paise', (order_row).total_paise),
    'dropoff', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((order_row).dropoff),
      'longitude', extensions.st_x((order_row).dropoff)
    ),
    'deliveryAddress', pg_catalog.jsonb_build_object(
      'label', (order_row).dropoff_label,
      'address', (order_row).dropoff_address,
      'details', (order_row).dropoff_details,
      'displayAddress', case
        when (order_row).dropoff_address is null then null
        else pg_catalog.concat_ws(
          ', ', (order_row).dropoff_details, (order_row).dropoff_address
        )
      end
    ),
    'courier', (
      select private.customer_courier_json(
        assignment.partner_account_id,
        (order_row).status in ('assigned', 'en_route_to_pickup', 'at_store', 'picked_up', 'in_transit')
      )
      from private.delivery_assignment_attempts as assignment
      where assignment.order_id = (order_row).id
        and assignment.status in ('accepted', 'completed')
      order by assignment.attempt_number desc
      limit 1
    ),
    'timeline', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'createdAt', (order_row).created_at,
      'acceptedAt', (order_row).accepted_at,
      'readyAt', (order_row).ready_at,
      'assignedAt', (order_row).assigned_at,
      'enRouteToPickupAt', (order_row).en_route_to_pickup_at,
      'atStoreAt', (order_row).arrived_at_store_at,
      'pickedUpAt', (order_row).picked_up_at,
      'inTransitAt', (order_row).in_transit_at,
      'deliveredAt', (order_row).delivered_at,
      'cancelledAt', (order_row).cancelled_at
    )),
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

create or replace function private.merchant_order_json_with_handoff(
  order_row private.merchant_orders,
  p_audience text
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case
      when (order_row).controlled_scope = 'general'
        then private.merchant_order_json(order_row)
      else private.controlled_order_json(order_row)
    end
    || pg_catalog.jsonb_build_object(
      'handoffCode',
      case
        when p_audience = 'merchant'
          and (order_row).status in ('assigned', 'en_route_to_pickup', 'at_store')
          and (order_row).pickup_code_digest is not null
          and (order_row).pickup_code_expires_at > pg_catalog.now()
          and (order_row).pickup_code_locked_at is null
        then pg_catalog.jsonb_build_object(
          'purpose', 'pickup',
          'code', private.order_handoff_code((order_row).id, 'pickup'),
          'expiresAt', (order_row).pickup_code_expires_at
        )
        when p_audience = 'customer'
          and (order_row).status in ('picked_up', 'in_transit')
          and (order_row).delivery_code_digest is not null
          and (order_row).delivery_code_expires_at > pg_catalog.now()
          and (order_row).delivery_code_locked_at is null
        then pg_catalog.jsonb_build_object(
          'purpose', 'delivery',
          'code', private.order_handoff_code((order_row).id, 'delivery'),
          'expiresAt', (order_row).delivery_code_expires_at
        )
        else null
      end
    );
$$;

revoke execute on function private.customer_courier_json(uuid, boolean)
  from public, anon, authenticated;
revoke execute on function private.merchant_order_quote_json(
  private.merchant_order_quotes
) from public, anon, authenticated;
revoke execute on function private.merchant_order_json(private.merchant_orders)
  from public, anon, authenticated;
grant execute on function private.customer_courier_json(uuid, boolean)
  to service_role;
grant execute on function private.merchant_order_quote_json(
  private.merchant_order_quotes
) to service_role;
grant execute on function private.merchant_order_json(private.merchant_orders)
  to service_role;
revoke execute on function private.merchant_order_json_with_handoff(
  private.merchant_orders, text
) from public, anon, authenticated;
grant execute on function private.merchant_order_json_with_handoff(
  private.merchant_orders, text
) to service_role;

create or replace function private.parcel_delivery_json(
  parcel_row private.parcel_deliveries,
  p_audience text
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'parcelId', (parcel_row).id,
    'status', (parcel_row).status,
    'paymentStatus', (parcel_row).payment_status,
    'refundStatus', (parcel_row).refund_status,
    'deliveryMethod', (parcel_row).delivery_method,
    'pickup', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((parcel_row).pickup),
      'longitude', extensions.st_x((parcel_row).pickup),
      'address', (parcel_row).pickup_address
    ),
    'dropoff', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((parcel_row).dropoff),
      'longitude', extensions.st_x((parcel_row).dropoff),
      'address', (parcel_row).dropoff_address
    ),
    'recipient', pg_catalog.jsonb_build_object(
      'name', (parcel_row).recipient_name,
      'phoneNumber', case
        when p_audience in ('customer', 'recipient', 'partner_current')
          then (parcel_row).recipient_phone_number
        else null
      end
    ),
    'declaredContents', (parcel_row).declared_contents,
    'declaredValue', pg_catalog.jsonb_build_object('currency', 'INR', 'paise', (parcel_row).declared_value_paise),
    'deliveryFee', pg_catalog.jsonb_build_object('currency', 'INR', 'paise', (parcel_row).delivery_fee_paise),
    'courierPayout', pg_catalog.jsonb_build_object('currency', 'INR', 'paise', (parcel_row).courier_payout_paise),
    'courier', case
      when p_audience in ('customer', 'recipient') then (
        select private.customer_courier_json(
          assignment.partner_account_id,
          (parcel_row).status in ('assigned', 'en_route_to_pickup', 'picked_up', 'in_transit')
        )
        from private.parcel_assignment_attempts as assignment
        where assignment.parcel_id = (parcel_row).id
          and assignment.status in ('acknowledged', 'completed')
        order by assignment.attempt_number desc
        limit 1
      )
      else null
    end,
    'timeline', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'createdAt', (parcel_row).created_at,
      'paymentCapturedAt', (parcel_row).payment_captured_at,
      'assignedAt', (parcel_row).assigned_at,
      'enRouteToPickupAt', (parcel_row).en_route_to_pickup_at,
      'pickedUpAt', (parcel_row).picked_up_at,
      'inTransitAt', (parcel_row).in_transit_at,
      'deliveredAt', (parcel_row).delivered_at,
      'cancelledAt', (parcel_row).cancelled_at
    )),
    'stateVersion', (parcel_row).state_version,
    'createdAt', (parcel_row).created_at,
    'updatedAt', (parcel_row).updated_at,
    'handoffCode', case
      when p_audience = 'customer'
        and (parcel_row).status in ('assigned', 'en_route_to_pickup')
        and (parcel_row).pickup_code_expires_at > pg_catalog.now()
        and (parcel_row).pickup_code_locked_at is null
      then pg_catalog.jsonb_build_object(
        'purpose', 'pickup',
        'code', private.parcel_handoff_code((parcel_row).id, 'pickup'),
        'expiresAt', (parcel_row).pickup_code_expires_at
      )
      when p_audience = 'recipient'
        and (parcel_row).status in ('picked_up', 'in_transit')
        and (parcel_row).delivery_code_expires_at > pg_catalog.now()
        and (parcel_row).delivery_code_locked_at is null
      then pg_catalog.jsonb_build_object(
        'purpose', 'delivery',
        'code', private.parcel_handoff_code((parcel_row).id, 'delivery'),
        'expiresAt', (parcel_row).delivery_code_expires_at
      )
      else null
    end
  );
$$;

revoke execute on function private.parcel_delivery_json(
  private.parcel_deliveries, text
) from public, anon, authenticated;
grant execute on function private.parcel_delivery_json(
  private.parcel_deliveries, text
) to service_role;

create table public.dastak_parcel_notification_queue (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  parcel_id uuid not null references private.parcel_deliveries(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  status text not null,
  payment_state text not null,
  created_at timestamptz not null default pg_catalog.now(),
  processed_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0)
);

alter table public.dastak_parcel_notification_queue enable row level security;
revoke all on public.dastak_parcel_notification_queue from anon, authenticated;
grant select, update on public.dastak_parcel_notification_queue to service_role;
create index dastak_parcel_notification_queue_pending_idx
  on public.dastak_parcel_notification_queue(processed_at, created_at)
  where processed_at is null;

create function private.queue_dastak_parcel_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status
    or old.payment_status is distinct from new.payment_status
  then
    insert into public.dastak_parcel_notification_queue (
      parcel_id, account_id, status, payment_state
    ) values (
      new.id, new.customer_account_id, new.status, new.payment_status
    );
    if new.recipient_account_id is not null
      and new.recipient_account_id <> new.customer_account_id
    then
      insert into public.dastak_parcel_notification_queue (
        parcel_id, account_id, status, payment_state
      ) values (
        new.id, new.recipient_account_id, new.status, new.payment_status
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger parcel_deliveries_queue_dastak_notification
after insert or update of status, payment_status on private.parcel_deliveries
for each row execute function private.queue_dastak_parcel_notification();

revoke execute on function private.queue_dastak_parcel_notification()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
