create table private.parcel_rate_cards (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  service_zone_id uuid not null references public.service_zones(id),
  delivery_method text not null check (
    delivery_method in ('walking', 'bicycle', 'bike', 'auto')
  ),
  minimum_fare_paise integer not null check (
    minimum_fare_paise between 1 and 100000000
  ),
  per_kilometre_paise integer not null check (
    per_kilometre_paise between 1 and 100000000
  ),
  courier_payout_bps integer not null check (
    courier_payout_bps between 0 and 10000
  ),
  version integer not null check (version > 0),
  active boolean not null default true,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  unique (service_zone_id, delivery_method, version)
);

create unique index parcel_rate_cards_active_uidx
  on private.parcel_rate_cards(service_zone_id, delivery_method)
  where active = true;

create table private.parcel_quotes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  customer_account_id uuid not null references public.accounts(id),
  rate_card_id uuid not null references private.parcel_rate_cards(id),
  rate_card_version integer not null check (rate_card_version > 0),
  service_zone_id uuid not null references public.service_zones(id),
  delivery_method text not null check (
    delivery_method in ('walking', 'bicycle', 'bike', 'auto')
  ),
  pickup extensions.geometry(Point, 4326) not null,
  pickup_address text not null check (
    pg_catalog.char_length(pg_catalog.btrim(pickup_address)) between 1 and 300
  ),
  dropoff extensions.geometry(Point, 4326) not null,
  dropoff_address text not null check (
    pg_catalog.char_length(pg_catalog.btrim(dropoff_address)) between 1 and 300
  ),
  route_distance_meters integer not null check (route_distance_meters > 0),
  route_duration_seconds integer not null check (route_duration_seconds > 0),
  delivery_fee_paise integer not null check (
    delivery_fee_paise between 1 and 100000000
  ),
  courier_payout_paise integer not null check (
    courier_payout_paise between 0 and delivery_fee_paise
  ),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  check (expires_at > created_at)
);

create index parcel_quotes_customer_idx
  on private.parcel_quotes(customer_account_id, created_at desc);
create index parcel_quotes_expiry_idx
  on private.parcel_quotes(expires_at)
  where consumed_at is null;

create table private.parcel_deliveries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  quote_id uuid not null unique references private.parcel_quotes(id),
  customer_account_id uuid not null references public.accounts(id),
  recipient_account_id uuid not null references public.accounts(id),
  recipient_name text not null check (
    pg_catalog.char_length(pg_catalog.btrim(recipient_name)) between 1 and 80
  ),
  recipient_phone_number text not null check (
    recipient_phone_number ~ '^\+[1-9][0-9]{7,14}$'
  ),
  service_zone_id uuid not null references public.service_zones(id),
  delivery_method text not null check (
    delivery_method in ('walking', 'bicycle', 'bike', 'auto')
  ),
  pickup extensions.geometry(Point, 4326) not null,
  pickup_address text not null,
  dropoff extensions.geometry(Point, 4326) not null,
  dropoff_address text not null,
  route_distance_meters integer not null check (route_distance_meters > 0),
  route_duration_seconds integer not null check (route_duration_seconds > 0),
  declared_contents text not null check (
    pg_catalog.char_length(pg_catalog.btrim(declared_contents)) between 1 and 300
  ),
  declared_value_paise integer not null check (
    declared_value_paise between 0 and 100000000
  ),
  delivery_fee_paise integer not null check (
    delivery_fee_paise between 1 and 100000000
  ),
  courier_payout_paise integer not null check (
    courier_payout_paise between 0 and delivery_fee_paise
  ),
  status text not null default 'payment_pending' check (
    status in (
      'payment_pending', 'paid', 'assigned', 'en_route_to_pickup',
      'picked_up', 'in_transit', 'delivered', 'cancelled'
    )
  ),
  payment_status text not null default 'pending' check (
    payment_status in (
      'pending', 'paid', 'failed', 'refund_pending', 'refunded', 'cancelled'
    )
  ),
  refund_status text not null default 'not_requested' check (
    refund_status in ('not_requested', 'pending', 'completed', 'not_eligible')
  ),
  pickup_code_salt text check (
    pickup_code_salt is null or pg_catalog.char_length(pickup_code_salt) = 64
  ),
  pickup_code_digest bytea,
  pickup_code_expires_at timestamptz,
  pickup_code_failed_attempts integer not null default 0 check (
    pickup_code_failed_attempts between 0 and 5
  ),
  pickup_code_locked_at timestamptz,
  delivery_code_salt text check (
    delivery_code_salt is null or pg_catalog.char_length(delivery_code_salt) = 64
  ),
  delivery_code_digest bytea,
  delivery_code_expires_at timestamptz,
  delivery_code_failed_attempts integer not null default 0 check (
    delivery_code_failed_attempts between 0 and 5
  ),
  delivery_code_locked_at timestamptz,
  payment_captured_at timestamptz,
  assigned_at timestamptz,
  en_route_to_pickup_at timestamptz,
  picked_up_at timestamptz,
  in_transit_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  state_version bigint not null default 1 check (state_version > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check (
    (pickup_code_salt is null and pickup_code_digest is null and pickup_code_expires_at is null)
    or (pickup_code_salt is not null and pickup_code_digest is not null and pickup_code_expires_at is not null)
  ),
  check (
    (delivery_code_salt is null and delivery_code_digest is null and delivery_code_expires_at is null)
    or (delivery_code_salt is not null and delivery_code_digest is not null and delivery_code_expires_at is not null)
  ),
  check (pickup_code_locked_at is null or pickup_code_failed_attempts = 5),
  check (delivery_code_locked_at is null or delivery_code_failed_attempts = 5),
  check (
    (status = 'payment_pending' and payment_status = 'pending')
    or (status = 'cancelled')
    or (status <> 'payment_pending' and payment_status in ('paid', 'refund_pending', 'refunded'))
  )
);

create index parcel_deliveries_customer_idx
  on private.parcel_deliveries(customer_account_id, created_at desc);
create index parcel_deliveries_recipient_idx
  on private.parcel_deliveries(recipient_account_id, created_at desc);
create index parcel_deliveries_dispatch_idx
  on private.parcel_deliveries(service_zone_id, created_at, id)
  where status = 'paid' and payment_status = 'paid';

create table private.parcel_assignment_attempts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  parcel_id uuid not null references private.parcel_deliveries(id) on delete cascade,
  partner_account_id uuid not null
    references private.delivery_partner_profiles(account_id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  status text not null default 'offered' check (
    status in ('offered', 'acknowledged', 'declined', 'expired', 'cancelled', 'completed')
  ),
  distance_meters double precision not null check (distance_meters >= 0),
  offered_at timestamptz not null default pg_catalog.now(),
  respond_by timestamptz not null,
  responded_at timestamptz,
  response_reason text check (
    response_reason is null
    or pg_catalog.char_length(pg_catalog.btrim(response_reason)) between 1 and 300
  ),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (parcel_id, attempt_number),
  check (respond_by > offered_at),
  check (
    (status = 'offered' and responded_at is null and response_reason is null)
    or (status = 'acknowledged' and responded_at is not null and response_reason is null)
    or (status in ('declined', 'expired', 'cancelled', 'completed') and responded_at is not null)
  )
);

create unique index parcel_assignment_parcel_active_uidx
  on private.parcel_assignment_attempts(parcel_id)
  where status in ('offered', 'acknowledged');
create unique index parcel_assignment_partner_active_uidx
  on private.parcel_assignment_attempts(partner_account_id)
  where status in ('offered', 'acknowledged');
create index parcel_assignment_expiry_idx
  on private.parcel_assignment_attempts(respond_by)
  where status = 'offered';

create table private.parcel_payment_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  provider text not null check (
    pg_catalog.char_length(pg_catalog.btrim(provider)) between 1 and 40
  ),
  provider_event_id text not null check (
    pg_catalog.char_length(pg_catalog.btrim(provider_event_id)) between 1 and 200
  ),
  parcel_id uuid not null references private.parcel_deliveries(id),
  event_type text not null check (
    event_type in ('payment_captured', 'payment_failed', 'refund_completed')
  ),
  amount_paise integer not null check (amount_paise >= 0),
  occurred_at timestamptz not null,
  payload_digest text not null check (
    pg_catalog.char_length(pg_catalog.btrim(payload_digest)) between 1 and 200
  ),
  created_at timestamptz not null default pg_catalog.now(),
  unique (provider, provider_event_id)
);

create table private.parcel_partner_reliability_reviews (
  account_id uuid primary key
    references private.delivery_partner_profiles(account_id) on delete cascade,
  window_24h_started_at timestamptz not null default pg_catalog.now(),
  misses_24h integer not null default 0 check (misses_24h >= 0),
  window_7d_started_at timestamptz not null default pg_catalog.now(),
  misses_7d integer not null default 0 check (misses_7d >= 0),
  owner_review_required boolean not null default false,
  owner_review_required_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  check (owner_review_required or owner_review_required_at is null)
);

create table private.parcel_handoff_code_keys (
  singleton boolean primary key default true check (singleton),
  secret text not null check (pg_catalog.char_length(secret) = 64),
  created_at timestamptz not null default pg_catalog.now()
);

alter table private.parcel_rate_cards enable row level security;
alter table private.parcel_quotes enable row level security;
alter table private.parcel_deliveries enable row level security;
alter table private.parcel_assignment_attempts enable row level security;
alter table private.parcel_payment_events enable row level security;
alter table private.parcel_partner_reliability_reviews enable row level security;
alter table private.parcel_handoff_code_keys enable row level security;

revoke all on table private.parcel_rate_cards from public, anon, authenticated;
revoke all on table private.parcel_quotes from public, anon, authenticated;
revoke all on table private.parcel_deliveries from public, anon, authenticated;
revoke all on table private.parcel_assignment_attempts from public, anon, authenticated;
revoke all on table private.parcel_payment_events from public, anon, authenticated;
revoke all on table private.parcel_partner_reliability_reviews from public, anon, authenticated;
revoke all on table private.parcel_handoff_code_keys from public, anon, authenticated;

grant select, insert, update on table private.parcel_rate_cards to service_role;
grant select, insert, update on table private.parcel_quotes to service_role;
grant select, insert, update on table private.parcel_deliveries to service_role;
grant select, insert, update on table private.parcel_assignment_attempts to service_role;
grant select, insert on table private.parcel_payment_events to service_role;
grant select, insert, update on table private.parcel_partner_reliability_reviews to service_role;
grant select on table private.parcel_handoff_code_keys to service_role;
grant select, insert on table private.safety_cases to service_role;

insert into private.parcel_handoff_code_keys (singleton, secret)
values (true, pg_catalog.encode(extensions.gen_random_bytes(32), 'hex'));

create function private.parcel_payment_event_immutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'private.parcel_payment_events is append-only';
end;
$$;

create trigger parcel_payment_events_immutable
before update or delete on private.parcel_payment_events
for each row execute function private.parcel_payment_event_immutable();

create function private.parcel_handoff_secret()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select key.secret
  from private.parcel_handoff_code_keys as key
  where key.singleton;
$$;

create function private.parcel_handoff_code(
  p_parcel_id uuid,
  p_purpose text
)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_bytes bytea;
  v_number bigint;
begin
  if p_parcel_id is null or p_purpose not in ('pickup', 'delivery') then
    raise exception 'invalid parcel handoff code context';
  end if;

  v_bytes := extensions.hmac(
    p_parcel_id::text || ':' || p_purpose,
    private.parcel_handoff_secret(),
    'sha256'
  );
  v_number := (
    pg_catalog.get_byte(v_bytes, 0)::bigint * 16777216
    + pg_catalog.get_byte(v_bytes, 1)::bigint * 65536
    + pg_catalog.get_byte(v_bytes, 2)::bigint * 256
    + pg_catalog.get_byte(v_bytes, 3)::bigint
  ) % 1000000;

  return pg_catalog.lpad(v_number::text, 6, '0');
end;
$$;

create function private.parcel_handoff_digest(
  p_salt text,
  p_code text
)
returns bytea
language sql
stable
security invoker
set search_path = ''
as $$
  select extensions.hmac(
    p_salt || ':' || p_code,
    private.parcel_handoff_secret(),
    'sha256'
  );
$$;

create function private.parcel_quote_json(
  quote_row private.parcel_quotes
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'quoteId', (quote_row).id,
    'deliveryMethod', (quote_row).delivery_method,
    'routeDistanceMeters', (quote_row).route_distance_meters,
    'routeDurationSeconds', (quote_row).route_duration_seconds,
    'deliveryFee', pg_catalog.jsonb_build_object(
      'currency', 'INR', 'paise', (quote_row).delivery_fee_paise
    ),
    'courierPayout', pg_catalog.jsonb_build_object(
      'currency', 'INR', 'paise', (quote_row).courier_payout_paise
    ),
    'expiresAt', (quote_row).expires_at
  );
$$;

create function private.parcel_delivery_json(
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
    'declaredValue', pg_catalog.jsonb_build_object(
      'currency', 'INR', 'paise', (parcel_row).declared_value_paise
    ),
    'deliveryFee', pg_catalog.jsonb_build_object(
      'currency', 'INR', 'paise', (parcel_row).delivery_fee_paise
    ),
    'courierPayout', pg_catalog.jsonb_build_object(
      'currency', 'INR', 'paise', (parcel_row).courier_payout_paise
    ),
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

create function private.parcel_assignment_json(
  assignment_row private.parcel_assignment_attempts
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
      'assignmentStatus', (assignment_row).status,
      'offeredAt', (assignment_row).offered_at,
      'respondBy', (assignment_row).respond_by,
      'acknowledgedAt', case
        when (assignment_row).status = 'acknowledged'
          then (assignment_row).responded_at
        else null
      end,
      'distanceMeters', pg_catalog.round((assignment_row).distance_meters::numeric, 1),
      'parcel', private.parcel_delivery_json(
        parcel,
        case
          when (assignment_row).status = 'acknowledged' then 'partner_current'
          else 'partner_offer'
        end
      )
    )
  end
  from private.parcel_deliveries as parcel
  where parcel.id = (assignment_row).parcel_id;
$$;

create function private.parcel_partner_snapshot_json(p_account_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'offer', private.parcel_assignment_json(
      (
        select assignment
        from private.parcel_assignment_attempts as assignment
        where assignment.partner_account_id = p_account_id
          and assignment.status = 'offered'
          and assignment.respond_by > pg_catalog.now()
        order by assignment.offered_at, assignment.id
        limit 1
      )
    ),
    'currentJob', private.parcel_assignment_json(
      (
        select assignment
        from private.parcel_assignment_attempts as assignment
        where assignment.partner_account_id = p_account_id
          and assignment.status = 'acknowledged'
        order by assignment.responded_at, assignment.id
        limit 1
      )
    )
  );
$$;

revoke execute on function private.parcel_payment_event_immutable()
  from public, anon, authenticated;
revoke execute on function private.parcel_handoff_secret()
  from public, anon, authenticated;
revoke execute on function private.parcel_handoff_code(uuid, text)
  from public, anon, authenticated;
revoke execute on function private.parcel_handoff_digest(text, text)
  from public, anon, authenticated;
revoke execute on function private.parcel_quote_json(private.parcel_quotes)
  from public, anon, authenticated;
revoke execute on function private.parcel_delivery_json(private.parcel_deliveries, text)
  from public, anon, authenticated;
revoke execute on function private.parcel_assignment_json(private.parcel_assignment_attempts)
  from public, anon, authenticated;
revoke execute on function private.parcel_partner_snapshot_json(uuid)
  from public, anon, authenticated;

grant execute on function private.parcel_payment_event_immutable() to service_role;
grant execute on function private.parcel_handoff_secret() to service_role;
grant execute on function private.parcel_handoff_code(uuid, text) to service_role;
grant execute on function private.parcel_handoff_digest(text, text) to service_role;
grant execute on function private.parcel_quote_json(private.parcel_quotes) to service_role;
grant execute on function private.parcel_delivery_json(private.parcel_deliveries, text)
  to service_role;
grant execute on function private.parcel_assignment_json(private.parcel_assignment_attempts)
  to service_role;
grant execute on function private.parcel_partner_snapshot_json(uuid) to service_role;

create or replace function public.upsert_parcel_rate_card(
  p_actor_id uuid,
  p_service_zone_id uuid,
  p_delivery_method text,
  p_minimum_fare_paise integer,
  p_per_kilometre_paise integer,
  p_courier_payout_bps integer,
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
  v_function_name constant text := 'upsert_parcel_rate_card';
  v_existing private.request_deduplication%rowtype;
  v_rate private.parcel_rate_cards%rowtype;
  v_version integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_actor_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_actor_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if not public.is_active_owner(p_actor_id) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied', 'message', 'An active owner account is required.'
      )
    );
    response_status := 403;
  elsif p_service_zone_id is null
    or p_delivery_method not in ('walking', 'bicycle', 'bike', 'auto')
    or p_minimum_fare_paise not between 1 and 100000000
    or p_per_kilometre_paise not between 1 and 100000000
    or p_courier_payout_bps not between 0 and 10000
    or p_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The parcel rate request is invalid.'
      )
    );
    response_status := 400;
  else
    perform 1
    from public.service_zones as zone
    where zone.id = p_service_zone_id
      and zone.active = true
    for share;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'service_zone_unavailable',
          'message', 'The service zone is not active.'
        )
      );
      response_status := 422;
    else
      select coalesce(pg_catalog.max(rate.version), 0) + 1
      into v_version
      from private.parcel_rate_cards as rate
      where rate.service_zone_id = p_service_zone_id
        and rate.delivery_method = p_delivery_method;

      update private.parcel_rate_cards as rate
      set active = false
      where rate.service_zone_id = p_service_zone_id
        and rate.delivery_method = p_delivery_method
        and rate.active = true;

      insert into private.parcel_rate_cards (
        service_zone_id, delivery_method, minimum_fare_paise,
        per_kilometre_paise, courier_payout_bps, version, active, created_by
      ) values (
        p_service_zone_id,
        p_delivery_method,
        p_minimum_fare_paise,
        p_per_kilometre_paise,
        p_courier_payout_bps,
        v_version,
        p_active,
        p_actor_id
      )
      returning * into v_rate;

      response_body := pg_catalog.jsonb_build_object(
        'rateCardId', v_rate.id,
        'serviceZoneId', v_rate.service_zone_id,
        'deliveryMethod', v_rate.delivery_method,
        'minimumFare', pg_catalog.jsonb_build_object(
          'currency', 'INR', 'paise', v_rate.minimum_fare_paise
        ),
        'perKilometre', pg_catalog.jsonb_build_object(
          'currency', 'INR', 'paise', v_rate.per_kilometre_paise
        ),
        'courierPayoutBps', v_rate.courier_payout_bps,
        'version', v_rate.version,
        'active', v_rate.active
      );
      response_status := 200;

      insert into audit.events (
        actor_id, action, entity_type, entity_id, after_state
      ) values (
        p_actor_id,
        'parcel_rate_card_version_created',
        'parcel_rate_card',
        v_rate.id,
        response_body
      );
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_actor_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create or replace function public.quote_parcel_delivery(
  p_account_id uuid,
  p_delivery_method text,
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_pickup_address text,
  p_dropoff_latitude double precision,
  p_dropoff_longitude double precision,
  p_dropoff_address text,
  p_route_distance_meters integer,
  p_route_duration_seconds integer,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'quote_parcel_delivery';
  v_existing private.request_deduplication%rowtype;
  v_pickup extensions.geometry(Point, 4326);
  v_dropoff extensions.geometry(Point, 4326);
  v_zone_id uuid;
  v_rate private.parcel_rate_cards%rowtype;
  v_quote private.parcel_quotes%rowtype;
  v_fee integer;
  v_payout integer;
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

  if p_delivery_method not in ('walking', 'bicycle', 'bike', 'auto')
    or p_pickup_latitude is null or p_pickup_latitude not between -90 and 90
    or p_pickup_longitude is null or p_pickup_longitude not between -180 and 180
    or nullif(pg_catalog.btrim(p_pickup_address), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_pickup_address)) > 300
    or p_dropoff_latitude is null or p_dropoff_latitude not between -90 and 90
    or p_dropoff_longitude is null or p_dropoff_longitude not between -180 and 180
    or nullif(pg_catalog.btrim(p_dropoff_address), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_dropoff_address)) > 300
    or p_route_distance_meters is null or p_route_distance_meters <= 0
    or p_route_duration_seconds is null or p_route_duration_seconds <= 0
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The parcel quote request is invalid.'
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
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  v_pickup := extensions.st_setsrid(
    extensions.st_makepoint(p_pickup_longitude, p_pickup_latitude), 4326
  );
  v_dropoff := extensions.st_setsrid(
    extensions.st_makepoint(p_dropoff_longitude, p_dropoff_latitude), 4326
  );

  select zone.id
  into v_zone_id
  from public.service_zones as zone
  where zone.active = true
    and extensions.st_covers(zone.boundary, v_pickup)
    and extensions.st_covers(zone.boundary, v_dropoff)
  order by zone.id
  limit 1
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'Pickup and dropoff must be inside one active service area.'
      )
    );
    response_status := 422;
  else
    select rate.*
    into v_rate
    from private.parcel_rate_cards as rate
    where rate.service_zone_id = v_zone_id
      and rate.delivery_method = p_delivery_method
      and rate.active = true
    for share;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'pricing_unavailable',
          'message', 'Parcel pricing is not configured for this service area and method.'
        )
      );
      response_status := 503;
    else
      v_fee := greatest(
        v_rate.minimum_fare_paise,
        pg_catalog.ceil(p_route_distance_meters::numeric / 1000)::integer
          * v_rate.per_kilometre_paise
      );
      v_payout := (
        v_fee::bigint * v_rate.courier_payout_bps / 10000
      )::integer;

      insert into private.parcel_quotes (
        customer_account_id, rate_card_id, rate_card_version,
        service_zone_id, delivery_method, pickup, pickup_address,
        dropoff, dropoff_address, route_distance_meters,
        route_duration_seconds, delivery_fee_paise,
        courier_payout_paise, expires_at
      ) values (
        p_account_id, v_rate.id, v_rate.version,
        v_zone_id, p_delivery_method, v_pickup, pg_catalog.btrim(p_pickup_address),
        v_dropoff, pg_catalog.btrim(p_dropoff_address), p_route_distance_meters,
        p_route_duration_seconds, v_fee, v_payout,
        pg_catalog.now() + interval '5 minutes'
      )
      returning * into v_quote;

      response_body := private.parcel_quote_json(v_quote);
      response_status := 200;

      insert into audit.events (
        actor_id, action, entity_type, entity_id, after_state
      ) values (
        p_account_id, 'parcel_quoted', 'parcel_quote', v_quote.id, response_body
      );
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create or replace function public.create_parcel_delivery(
  p_account_id uuid,
  p_quote_id uuid,
  p_recipient_phone_number text,
  p_recipient_name text,
  p_declared_contents text,
  p_declared_value_paise integer,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'create_parcel_delivery';
  v_existing private.request_deduplication%rowtype;
  v_quote private.parcel_quotes%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_recipient_ids uuid[];
  v_recipient_account_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

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
  elsif p_quote_id is null
    or p_recipient_phone_number !~ '^\+[1-9][0-9]{7,14}$'
    or nullif(pg_catalog.btrim(p_recipient_name), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_recipient_name)) > 80
    or nullif(pg_catalog.btrim(p_declared_contents), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_declared_contents)) > 300
    or p_declared_value_paise not between 0 and 100000000
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The parcel request is invalid.'
      )
    );
    response_status := 400;
  else
    select pg_catalog.array_agg(account.id order by account.id)
    into v_recipient_ids
    from public.accounts as account
    join private.account_memberships as membership
      on membership.account_id = account.id
     and membership.role = 'customer'
    where account.phone_number = p_recipient_phone_number
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      );

    if coalesce(pg_catalog.array_length(v_recipient_ids, 1), 0) <> 1 then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'recipient_unavailable',
          'message', 'The recipient must have one active Dastak account.'
        )
      );
      response_status := 422;
    else
      v_recipient_account_id := v_recipient_ids[1];

      select quote.*
      into v_quote
      from private.parcel_quotes as quote
      where quote.id = p_quote_id
        and quote.customer_account_id = p_account_id
      for update;

      if not found
        or v_quote.expires_at <= pg_catalog.now()
        or v_quote.consumed_at is not null
      then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'quote_unavailable',
            'message', 'The parcel quote is expired or already used.'
          )
        );
        response_status := 409;
      else
        insert into private.parcel_deliveries (
          quote_id, customer_account_id, recipient_account_id,
          recipient_name, recipient_phone_number, service_zone_id,
          delivery_method, pickup, pickup_address, dropoff, dropoff_address,
          route_distance_meters, route_duration_seconds,
          declared_contents, declared_value_paise,
          delivery_fee_paise, courier_payout_paise
        ) values (
          v_quote.id, p_account_id, v_recipient_account_id,
          pg_catalog.btrim(p_recipient_name), p_recipient_phone_number,
          v_quote.service_zone_id, v_quote.delivery_method,
          v_quote.pickup, v_quote.pickup_address,
          v_quote.dropoff, v_quote.dropoff_address,
          v_quote.route_distance_meters, v_quote.route_duration_seconds,
          pg_catalog.btrim(p_declared_contents), p_declared_value_paise,
          v_quote.delivery_fee_paise, v_quote.courier_payout_paise
        )
        returning * into v_parcel;

        update private.parcel_quotes as quote
        set consumed_at = pg_catalog.now()
        where quote.id = v_quote.id;

        response_body := private.parcel_delivery_json(v_parcel, 'customer');
        response_status := 201;

        insert into audit.events (
          actor_id, action, entity_type, entity_id, after_state
        ) values (
          p_account_id, 'parcel_created', 'parcel_delivery',
          v_parcel.id, response_body
        );
      end if;
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create function private.record_parcel_assignment_miss(p_account_id uuid)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_reliability private.parcel_partner_reliability_reviews%rowtype;
  v_before jsonb;
begin
  select pg_catalog.to_jsonb(review)
  into v_before
  from private.parcel_partner_reliability_reviews as review
  where review.account_id = p_account_id;

  insert into private.parcel_partner_reliability_reviews (
    account_id, window_24h_started_at, misses_24h,
    window_7d_started_at, misses_7d, updated_at
  ) values (
    p_account_id, pg_catalog.now(), 1, pg_catalog.now(), 1, pg_catalog.now()
  )
  on conflict (account_id) do update
  set window_24h_started_at = case
        when private.parcel_partner_reliability_reviews.window_24h_started_at
          <= pg_catalog.now() - interval '24 hours'
          then pg_catalog.now()
        else private.parcel_partner_reliability_reviews.window_24h_started_at
      end,
      misses_24h = case
        when private.parcel_partner_reliability_reviews.window_24h_started_at
          <= pg_catalog.now() - interval '24 hours'
          then 1
        else private.parcel_partner_reliability_reviews.misses_24h + 1
      end,
      window_7d_started_at = case
        when private.parcel_partner_reliability_reviews.window_7d_started_at
          <= pg_catalog.now() - interval '7 days'
          then pg_catalog.now()
        else private.parcel_partner_reliability_reviews.window_7d_started_at
      end,
      misses_7d = case
        when private.parcel_partner_reliability_reviews.window_7d_started_at
          <= pg_catalog.now() - interval '7 days'
          then 1
        else private.parcel_partner_reliability_reviews.misses_7d + 1
      end,
      owner_review_required = private.parcel_partner_reliability_reviews.owner_review_required
        or case
          when private.parcel_partner_reliability_reviews.window_7d_started_at
            <= pg_catalog.now() - interval '7 days'
            then false
          else private.parcel_partner_reliability_reviews.misses_7d + 1 >= 5
        end,
      owner_review_required_at = case
        when private.parcel_partner_reliability_reviews.owner_review_required then
          private.parcel_partner_reliability_reviews.owner_review_required_at
        when private.parcel_partner_reliability_reviews.window_7d_started_at
          > pg_catalog.now() - interval '7 days'
          and private.parcel_partner_reliability_reviews.misses_7d + 1 >= 5
          then pg_catalog.now()
        else null
      end,
      updated_at = pg_catalog.now()
  returning * into v_reliability;

  if v_reliability.misses_24h >= 3 then
    update private.account_memberships as membership
    set suspended_until = greatest(
      coalesce(membership.suspended_until, pg_catalog.now()),
      pg_catalog.now() + interval '30 minutes'
    )
    where membership.account_id = p_account_id
      and membership.role = 'dastak_partner';

    update private.delivery_partner_availability as availability
    set status = 'offline',
        location = null,
        service_zone_id = null,
        last_seen_at = pg_catalog.now(),
        available_until = null,
        state_version = availability.state_version + 1,
        updated_at = pg_catalog.now()
    where availability.account_id = p_account_id
      and availability.status = 'online';
  end if;

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    null,
    case
      when v_reliability.owner_review_required then 'parcel_partner_owner_review_required'
      when v_reliability.misses_24h >= 3 then 'parcel_partner_temporarily_suspended'
      else 'parcel_assignment_missed'
    end,
    'delivery_partner_reliability',
    p_account_id,
    v_before,
    pg_catalog.to_jsonb(v_reliability)
  );
end;
$$;

create function private.process_parcel_dispatch(
  p_parcel_id uuid default null,
  p_service_zone_id uuid default null
)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_assignment private.parcel_assignment_attempts%rowtype;
  v_assignment_id uuid;
  v_before jsonb;
  v_distance_meters double precision;
  v_inserted_count integer := 0;
  v_parcel private.parcel_deliveries%rowtype;
  v_partner_id uuid;
  v_reason text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak:all-delivery-dispatch', 0)
  );

  for v_assignment_id in
    select assignment.id
    from private.parcel_assignment_attempts as assignment
    join private.parcel_deliveries as parcel
      on parcel.id = assignment.parcel_id
    left join private.account_memberships as membership
      on membership.account_id = assignment.partner_account_id
     and membership.role = 'dastak_partner'
    left join private.delivery_partner_availability as availability
      on availability.account_id = assignment.partner_account_id
    where assignment.status = 'offered'
      and (p_parcel_id is null or assignment.parcel_id = p_parcel_id)
      and (
        assignment.respond_by <= pg_catalog.now()
        or parcel.status <> 'assigned'
        or membership.account_id is null
        or membership.approved_at is null
        or membership.suspended_until > pg_catalog.now()
        or availability.account_id is null
        or availability.status <> 'online'
        or availability.available_until <= pg_catalog.now()
        or availability.last_seen_at <= pg_catalog.now() - interval '90 seconds'
        or availability.service_zone_id <> parcel.service_zone_id
      )
    order by assignment.respond_by, assignment.id
    for update of assignment skip locked
  loop
    select assignment.*
    into v_assignment
    from private.parcel_assignment_attempts as assignment
    where assignment.id = v_assignment_id;

    select parcel.*
    into v_parcel
    from private.parcel_deliveries as parcel
    where parcel.id = v_assignment.parcel_id
    for update;

    v_before := private.parcel_assignment_json(v_assignment);
    if v_parcel.status <> 'assigned' then
      v_reason := 'parcel_no_longer_assignable';
      update private.parcel_assignment_attempts as assignment
      set status = 'cancelled',
          responded_at = pg_catalog.now(),
          response_reason = v_reason,
          updated_at = pg_catalog.now()
      where assignment.id = v_assignment.id
        and assignment.status = 'offered'
      returning * into v_assignment;
    else
      v_reason := case
        when v_assignment.respond_by <= pg_catalog.now() then 'acknowledgement_expired'
        else 'partner_unavailable'
      end;
      update private.parcel_assignment_attempts as assignment
      set status = 'expired',
          responded_at = pg_catalog.now(),
          response_reason = v_reason,
          updated_at = pg_catalog.now()
      where assignment.id = v_assignment.id
        and assignment.status = 'offered'
      returning * into v_assignment;

      if found then
        update private.parcel_deliveries as parcel
        set status = 'paid',
            assigned_at = null,
            state_version = parcel.state_version + 1,
            updated_at = pg_catalog.now()
        where parcel.id = v_parcel.id
          and parcel.status = 'assigned';

        perform private.record_parcel_assignment_miss(
          v_assignment.partner_account_id
        );
      end if;
    end if;

    if found then
      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason,
        before_state, after_state
      ) values (
        null,
        case
          when v_assignment.status = 'expired' then 'parcel_assignment_expired'
          else 'parcel_assignment_cancelled'
        end,
        'parcel_assignment',
        v_assignment.id,
        v_reason,
        v_before,
        private.parcel_assignment_json(v_assignment)
      );
    end if;
  end loop;

  for v_parcel in
    select parcel.*
    from private.parcel_deliveries as parcel
    where parcel.status = 'paid'
      and parcel.payment_status = 'paid'
      and (p_parcel_id is null or parcel.id = p_parcel_id)
      and (
        p_service_zone_id is null
        or parcel.service_zone_id = p_service_zone_id
      )
      and not exists (
        select 1
        from private.parcel_assignment_attempts as active_assignment
        where active_assignment.parcel_id = parcel.id
          and active_assignment.status in ('offered', 'acknowledged')
      )
    order by parcel.payment_captured_at nulls last, parcel.created_at, parcel.id
    for update of parcel skip locked
  loop
    v_partner_id := null;
    v_distance_meters := null;

    select
      availability.account_id,
      extensions.st_distance(
        availability.location::extensions.geography,
        v_parcel.pickup::extensions.geography
      )
    into v_partner_id, v_distance_meters
    from private.delivery_partner_availability as availability
    join private.delivery_partner_profiles as profile
      on profile.account_id = availability.account_id
    join private.account_memberships as membership
      on membership.account_id = availability.account_id
     and membership.role = 'dastak_partner'
    where availability.status = 'online'
      and availability.available_until > pg_catalog.now()
      and availability.last_seen_at > pg_catalog.now() - interval '90 seconds'
      and availability.service_zone_id = v_parcel.service_zone_id
      and profile.delivery_method = v_parcel.delivery_method
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
      and not exists (
        select 1
        from private.delivery_assignment_attempts as merchant_assignment
        where merchant_assignment.partner_account_id = availability.account_id
          and merchant_assignment.status in ('offered', 'accepted')
      )
      and not exists (
        select 1
        from private.parcel_assignment_attempts as active_partner_assignment
        where active_partner_assignment.partner_account_id = availability.account_id
          and active_partner_assignment.status in ('offered', 'acknowledged')
      )
      and not exists (
        select 1
        from private.parcel_assignment_attempts as recent_attempt
        where recent_attempt.parcel_id = v_parcel.id
          and recent_attempt.partner_account_id = availability.account_id
          and recent_attempt.responded_at > pg_catalog.now() - interval '15 minutes'
      )
    order by
      availability.location operator(extensions.<->) v_parcel.pickup,
      availability.account_id
    limit 1
    for update of availability skip locked;

    if v_partner_id is null then
      continue;
    end if;

    insert into private.parcel_assignment_attempts (
      parcel_id, partner_account_id, attempt_number, status,
      distance_meters, offered_at, respond_by
    ) values (
      v_parcel.id,
      v_partner_id,
      (
        select coalesce(pg_catalog.max(attempt.attempt_number), 0) + 1
        from private.parcel_assignment_attempts as attempt
        where attempt.parcel_id = v_parcel.id
      ),
      'offered',
      v_distance_meters,
      pg_catalog.now(),
      pg_catalog.now() + interval '60 seconds'
    )
    returning * into v_assignment;

    update private.parcel_deliveries as parcel
    set status = 'assigned',
        assigned_at = pg_catalog.now(),
        state_version = parcel.state_version + 1,
        updated_at = pg_catalog.now()
    where parcel.id = v_parcel.id;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, after_state
    ) values (
      null,
      'parcel_assignment_offered',
      'parcel_assignment',
      v_assignment.id,
      private.parcel_assignment_json(v_assignment)
    );

    v_inserted_count := v_inserted_count + 1;
  end loop;

  return v_inserted_count;
end;
$$;

create function private.sync_parcel_dispatch_on_availability_change()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  perform private.process_parcel_dispatch(
    null,
    case when new.status = 'online' then new.service_zone_id else null end
  );
  return new;
end;
$$;

create trigger parcel_delivery_availability_dispatch
after insert or update of status, location, service_zone_id, last_seen_at, available_until
on private.delivery_partner_availability
for each row execute function private.sync_parcel_dispatch_on_availability_change();

revoke execute on function private.record_parcel_assignment_miss(uuid)
  from public, anon, authenticated;
revoke execute on function private.process_parcel_dispatch(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function private.sync_parcel_dispatch_on_availability_change()
  from public, anon, authenticated;
grant execute on function private.record_parcel_assignment_miss(uuid) to service_role;
grant execute on function private.process_parcel_dispatch(uuid, uuid) to service_role;
grant execute on function private.sync_parcel_dispatch_on_availability_change()
  to service_role;

create or replace function public.record_parcel_payment_event(
  p_provider text,
  p_provider_event_id text,
  p_parcel_id uuid,
  p_event_type text,
  p_amount_paise integer,
  p_occurred_at timestamptz,
  p_payload_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_existing private.parcel_payment_events%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_before jsonb;
  v_pickup_salt text;
  v_delivery_salt text;
begin
  if nullif(pg_catalog.btrim(p_provider), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_provider)) > 40
    or nullif(pg_catalog.btrim(p_provider_event_id), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_provider_event_id)) > 200
    or p_parcel_id is null
    or p_event_type not in ('payment_captured', 'payment_failed', 'refund_completed')
    or p_amount_paise is null or p_amount_paise < 0
    or p_occurred_at is null
    or nullif(pg_catalog.btrim(p_payload_digest), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_payload_digest)) > 200
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The parcel payment event is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('parcel-payment:' || p_parcel_id::text, 0)
  );

  select event.*
  into v_existing
  from private.parcel_payment_events as event
  where event.provider = pg_catalog.btrim(p_provider)
    and event.provider_event_id = pg_catalog.btrim(p_provider_event_id);

  if found then
    if v_existing.parcel_id = p_parcel_id
      and v_existing.event_type = p_event_type
      and v_existing.amount_paise = p_amount_paise
      and v_existing.payload_digest = pg_catalog.btrim(p_payload_digest)
    then
      select parcel.*
      into v_parcel
      from private.parcel_deliveries as parcel
      where parcel.id = p_parcel_id;
      response_body := private.parcel_delivery_json(v_parcel, 'system');
      response_status := 200;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'provider_event_conflict',
          'message', 'The provider event identifier was already used.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select parcel.*
  into v_parcel
  from private.parcel_deliveries as parcel
  where parcel.id = p_parcel_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'parcel_not_found', 'message', 'The parcel does not exist.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  v_before := private.parcel_delivery_json(v_parcel, 'system');

  if p_event_type = 'payment_captured' then
    if p_amount_paise <> v_parcel.delivery_fee_paise then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'payment_amount_mismatch',
          'message', 'The captured amount does not match the parcel quote.'
        )
      );
      response_status := 409;
      return next;
      return;
    elsif v_parcel.status <> 'payment_pending'
      or v_parcel.payment_status <> 'pending'
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_payment_state',
          'message', 'This parcel cannot accept a payment capture.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    v_pickup_salt := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
    v_delivery_salt := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
    update private.parcel_deliveries as parcel
    set status = 'paid',
        payment_status = 'paid',
        payment_captured_at = p_occurred_at,
        pickup_code_salt = v_pickup_salt,
        pickup_code_digest = private.parcel_handoff_digest(
          v_pickup_salt, private.parcel_handoff_code(parcel.id, 'pickup')
        ),
        pickup_code_expires_at = pg_catalog.now() + interval '24 hours',
        delivery_code_salt = v_delivery_salt,
        delivery_code_digest = private.parcel_handoff_digest(
          v_delivery_salt, private.parcel_handoff_code(parcel.id, 'delivery')
        ),
        delivery_code_expires_at = pg_catalog.now() + interval '48 hours',
        state_version = parcel.state_version + 1,
        updated_at = pg_catalog.now()
    where parcel.id = p_parcel_id
    returning * into v_parcel;
  elsif p_event_type = 'payment_failed' then
    if v_parcel.status <> 'payment_pending' or v_parcel.payment_status <> 'pending' then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_payment_state',
          'message', 'This parcel cannot accept a payment failure.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    update private.parcel_deliveries as parcel
    set status = 'cancelled',
        payment_status = 'failed',
        cancelled_at = pg_catalog.now(),
        state_version = parcel.state_version + 1,
        updated_at = pg_catalog.now()
    where parcel.id = p_parcel_id
    returning * into v_parcel;
  else
    if p_amount_paise <> v_parcel.delivery_fee_paise
      or v_parcel.status <> 'cancelled'
      or v_parcel.payment_status <> 'refund_pending'
      or v_parcel.refund_status <> 'pending'
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_refund_state',
          'message', 'This parcel cannot accept a completed refund.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    update private.parcel_deliveries as parcel
    set payment_status = 'refunded',
        refund_status = 'completed',
        state_version = parcel.state_version + 1,
        updated_at = pg_catalog.now()
    where parcel.id = p_parcel_id
    returning * into v_parcel;
  end if;

  insert into private.parcel_payment_events (
    provider, provider_event_id, parcel_id, event_type,
    amount_paise, occurred_at, payload_digest
  ) values (
    pg_catalog.btrim(p_provider),
    pg_catalog.btrim(p_provider_event_id),
    p_parcel_id,
    p_event_type,
    p_amount_paise,
    p_occurred_at,
    pg_catalog.btrim(p_payload_digest)
  );

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    null,
    case p_event_type
      when 'payment_captured' then 'parcel_payment_captured'
      when 'payment_failed' then 'parcel_payment_failed'
      else 'parcel_refund_completed'
    end,
    'parcel_delivery',
    p_parcel_id,
    v_before,
    private.parcel_delivery_json(v_parcel, 'system')
  );

  if p_event_type = 'payment_captured' then
    perform private.process_parcel_dispatch(p_parcel_id, v_parcel.service_zone_id);
    select parcel.*
    into v_parcel
    from private.parcel_deliveries as parcel
    where parcel.id = p_parcel_id;
  end if;

  response_body := private.parcel_delivery_json(v_parcel, 'system');
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_parcel_delivery_snapshot(
  p_account_id uuid,
  p_parcel_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_parcel private.parcel_deliveries%rowtype;
  v_audience text;
begin
  select parcel.*
  into v_parcel
  from private.parcel_deliveries as parcel
  where parcel.id = p_parcel_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'parcel_not_found', 'message', 'The parcel does not exist.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  if v_parcel.customer_account_id = p_account_id then
    v_audience := 'customer';
  elsif v_parcel.recipient_account_id = p_account_id then
    v_audience := 'recipient';
  elsif exists (
    select 1
    from private.parcel_assignment_attempts as assignment
    where assignment.parcel_id = v_parcel.id
      and assignment.partner_account_id = p_account_id
      and assignment.status in ('offered', 'acknowledged', 'completed')
  ) then
    v_audience := 'partner_current';
  else
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied', 'message', 'This parcel is not available to the account.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  response_body := private.parcel_delivery_json(v_parcel, v_audience);
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_parcel_partner_snapshot(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1
  from private.account_memberships as membership
  join private.delivery_partner_profiles as profile
    on profile.account_id = membership.account_id
  where membership.account_id = p_account_id
    and membership.role = 'dastak_partner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    );

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An approved active delivery partner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  perform private.process_parcel_dispatch();
  response_body := private.parcel_partner_snapshot_json(p_account_id);
  response_status := 200;
  return next;
end;
$$;

create or replace function public.acknowledge_parcel_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'acknowledge_parcel_assignment';
  v_existing private.request_deduplication%rowtype;
  v_assignment private.parcel_assignment_attempts%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_before jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if p_assignment_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The assignment request is invalid.'
      )
    );
    response_status := 400;
  else
    select assignment.*
    into v_assignment
    from private.parcel_assignment_attempts as assignment
    where assignment.id = p_assignment_id
      and assignment.partner_account_id = p_account_id
    for update;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'assignment_not_found', 'message', 'The assignment does not exist.'
        )
      );
      response_status := 404;
    else
      select parcel.*
      into v_parcel
      from private.parcel_deliveries as parcel
      where parcel.id = v_assignment.parcel_id
      for update;

      if v_assignment.status <> 'offered' or v_parcel.status <> 'assigned' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'assignment_unavailable',
            'message', 'The assignment is no longer available.'
          )
        );
        response_status := 409;
      elsif v_assignment.respond_by <= pg_catalog.now() then
        v_before := private.parcel_assignment_json(v_assignment);
        update private.parcel_assignment_attempts as assignment
        set status = 'expired',
            responded_at = pg_catalog.now(),
            response_reason = 'acknowledgement_expired',
            updated_at = pg_catalog.now()
        where assignment.id = v_assignment.id
        returning * into v_assignment;

        update private.parcel_deliveries as parcel
        set status = 'paid',
            assigned_at = null,
            state_version = parcel.state_version + 1,
            updated_at = pg_catalog.now()
        where parcel.id = v_parcel.id;

        perform private.record_parcel_assignment_miss(p_account_id);
        insert into audit.events (
          actor_id, action, entity_type, entity_id, reason,
          before_state, after_state
        ) values (
          p_account_id, 'parcel_assignment_expired', 'parcel_assignment',
          v_assignment.id, 'acknowledgement_expired', v_before,
          private.parcel_assignment_json(v_assignment)
        );
        perform private.process_parcel_dispatch(v_parcel.id, v_parcel.service_zone_id);

        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'assignment_expired',
            'message', 'The assignment acknowledgement window expired.'
          )
        );
        response_status := 409;
      else
        v_before := private.parcel_assignment_json(v_assignment);
        update private.parcel_assignment_attempts as assignment
        set status = 'acknowledged',
            responded_at = pg_catalog.now(),
            updated_at = pg_catalog.now()
        where assignment.id = v_assignment.id
        returning * into v_assignment;

        insert into audit.events (
          actor_id, action, entity_type, entity_id, before_state, after_state
        ) values (
          p_account_id, 'parcel_assignment_acknowledged', 'parcel_assignment',
          v_assignment.id, v_before, private.parcel_assignment_json(v_assignment)
        );

        response_body := private.parcel_partner_snapshot_json(p_account_id);
        response_status := 200;
      end if;
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create or replace function public.decline_parcel_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
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
  v_function_name constant text := 'decline_parcel_assignment';
  v_existing private.request_deduplication%rowtype;
  v_assignment private.parcel_assignment_attempts%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_reason text;
  v_before jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  v_reason := coalesce(nullif(pg_catalog.btrim(p_reason), ''), 'partner_declined');
  if p_assignment_id is null
    or pg_catalog.char_length(v_reason) > 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The assignment response is invalid.'
      )
    );
    response_status := 400;
  else
    select assignment.*
    into v_assignment
    from private.parcel_assignment_attempts as assignment
    where assignment.id = p_assignment_id
      and assignment.partner_account_id = p_account_id
    for update;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'assignment_not_found', 'message', 'The assignment does not exist.'
        )
      );
      response_status := 404;
    elsif v_assignment.status <> 'offered' then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'assignment_unavailable',
          'message', 'The assignment is no longer available.'
        )
      );
      response_status := 409;
    else
      select parcel.*
      into v_parcel
      from private.parcel_deliveries as parcel
      where parcel.id = v_assignment.parcel_id
      for update;

      v_before := private.parcel_assignment_json(v_assignment);
      update private.parcel_assignment_attempts as assignment
      set status = 'declined',
          responded_at = pg_catalog.now(),
          response_reason = v_reason,
          updated_at = pg_catalog.now()
      where assignment.id = v_assignment.id
      returning * into v_assignment;

      if v_parcel.status = 'assigned' then
        update private.parcel_deliveries as parcel
        set status = 'paid',
            assigned_at = null,
            state_version = parcel.state_version + 1,
            updated_at = pg_catalog.now()
        where parcel.id = v_parcel.id;
      end if;

      perform private.record_parcel_assignment_miss(p_account_id);
      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason,
        before_state, after_state
      ) values (
        p_account_id, 'parcel_assignment_declined', 'parcel_assignment',
        v_assignment.id, v_reason, v_before,
        private.parcel_assignment_json(v_assignment)
      );
      perform private.process_parcel_dispatch(v_parcel.id, v_parcel.service_zone_id);

      response_body := private.parcel_partner_snapshot_json(p_account_id);
      response_status := 200;
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create or replace function public.advance_parcel_delivery(
  p_account_id uuid,
  p_assignment_id uuid,
  p_action text,
  p_verification_code text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'advance_parcel_delivery';
  v_existing private.request_deduplication%rowtype;
  v_assignment private.parcel_assignment_attempts%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_before jsonb;
  v_expected_status text;
  v_target_status text;
  v_code_valid boolean := true;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if p_assignment_id is null
    or p_action not in (
      'start_to_pickup', 'confirm_pickup', 'start_delivery', 'complete_delivery'
    )
    or (
      p_action in ('confirm_pickup', 'complete_delivery')
      and (p_verification_code is null or p_verification_code !~ '^[0-9]{6}$')
    )
    or (
      p_action in ('start_to_pickup', 'start_delivery')
      and p_verification_code is not null
    )
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The parcel transition is invalid.'
      )
    );
    response_status := 400;
  else
    select assignment.*
    into v_assignment
    from private.parcel_assignment_attempts as assignment
    where assignment.id = p_assignment_id
      and assignment.partner_account_id = p_account_id
    for update;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'assignment_not_found', 'message', 'The assignment does not exist.'
        )
      );
      response_status := 404;
    elsif v_assignment.status <> 'acknowledged' then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'assignment_unavailable',
          'message', 'The assignment is not an active acknowledged job.'
        )
      );
      response_status := 409;
    else
      select parcel.*
      into v_parcel
      from private.parcel_deliveries as parcel
      where parcel.id = v_assignment.parcel_id
      for update;

      case p_action
        when 'start_to_pickup' then
          v_expected_status := 'assigned';
          v_target_status := 'en_route_to_pickup';
        when 'confirm_pickup' then
          v_expected_status := 'en_route_to_pickup';
          v_target_status := 'picked_up';
        when 'start_delivery' then
          v_expected_status := 'picked_up';
          v_target_status := 'in_transit';
        when 'complete_delivery' then
          v_expected_status := 'in_transit';
          v_target_status := 'delivered';
      end case;

      if v_parcel.status <> v_expected_status then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_transition',
            'message', 'The parcel is not ready for this transition.'
          )
        );
        response_status := 409;
      else
        if p_action = 'confirm_pickup' then
          v_code_valid := v_parcel.pickup_code_digest is not null
            and v_parcel.pickup_code_expires_at > pg_catalog.now()
            and v_parcel.pickup_code_locked_at is null
            and v_parcel.pickup_code_digest = private.parcel_handoff_digest(
              v_parcel.pickup_code_salt, p_verification_code
            );

          if not v_code_valid then
            update private.parcel_deliveries as parcel
            set pickup_code_failed_attempts = least(
                  parcel.pickup_code_failed_attempts + 1, 5
                ),
                pickup_code_locked_at = case
                  when parcel.pickup_code_failed_attempts + 1 >= 5
                    then pg_catalog.now()
                  else parcel.pickup_code_locked_at
                end,
                state_version = parcel.state_version + 1,
                updated_at = pg_catalog.now()
            where parcel.id = v_parcel.id;
          end if;
        elsif p_action = 'complete_delivery' then
          v_code_valid := v_parcel.delivery_code_digest is not null
            and v_parcel.delivery_code_expires_at > pg_catalog.now()
            and v_parcel.delivery_code_locked_at is null
            and v_parcel.delivery_code_digest = private.parcel_handoff_digest(
              v_parcel.delivery_code_salt, p_verification_code
            );

          if not v_code_valid then
            update private.parcel_deliveries as parcel
            set delivery_code_failed_attempts = least(
                  parcel.delivery_code_failed_attempts + 1, 5
                ),
                delivery_code_locked_at = case
                  when parcel.delivery_code_failed_attempts + 1 >= 5
                    then pg_catalog.now()
                  else parcel.delivery_code_locked_at
                end,
                state_version = parcel.state_version + 1,
                updated_at = pg_catalog.now()
            where parcel.id = v_parcel.id;
          end if;
        end if;

        if not v_code_valid then
          response_body := pg_catalog.jsonb_build_object(
            'error', pg_catalog.jsonb_build_object(
              'code', 'invalid_handoff_code',
              'message', 'The parcel handoff code is invalid or unavailable.'
            )
          );
          response_status := 422;
        else
          v_before := private.parcel_delivery_json(v_parcel, 'partner_current');
          update private.parcel_deliveries as parcel
          set status = v_target_status,
              en_route_to_pickup_at = case
                when v_target_status = 'en_route_to_pickup'
                  then pg_catalog.now()
                else parcel.en_route_to_pickup_at
              end,
              picked_up_at = case
                when v_target_status = 'picked_up' then pg_catalog.now()
                else parcel.picked_up_at
              end,
              in_transit_at = case
                when v_target_status = 'in_transit' then pg_catalog.now()
                else parcel.in_transit_at
              end,
              delivered_at = case
                when v_target_status = 'delivered' then pg_catalog.now()
                else parcel.delivered_at
              end,
              state_version = parcel.state_version + 1,
              updated_at = pg_catalog.now()
          where parcel.id = v_parcel.id
          returning * into v_parcel;

          if v_target_status = 'delivered' then
            update private.parcel_assignment_attempts as assignment
            set status = 'completed',
                response_reason = 'parcel_delivered',
                updated_at = pg_catalog.now()
            where assignment.id = v_assignment.id
            returning * into v_assignment;
          end if;

          insert into audit.events (
            actor_id, action, entity_type, entity_id,
            before_state, after_state
          ) values (
            p_account_id,
            case p_action
              when 'start_to_pickup' then 'parcel_partner_started_to_pickup'
              when 'confirm_pickup' then 'parcel_pickup_handoff_verified'
              when 'start_delivery' then 'parcel_delivery_started'
              else 'parcel_delivery_handoff_verified'
            end,
            'parcel_delivery',
            v_parcel.id,
            v_before,
            private.parcel_delivery_json(v_parcel, 'partner_current')
          );

          response_body := private.parcel_partner_snapshot_json(p_account_id);
          response_status := 200;
        end if;
      end if;
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create or replace function public.cancel_parcel_delivery(
  p_account_id uuid,
  p_parcel_id uuid,
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
  v_function_name constant text := 'cancel_parcel_delivery';
  v_existing private.request_deduplication%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_assignment private.parcel_assignment_attempts%rowtype;
  v_before jsonb;
  v_reason text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  v_reason := nullif(pg_catalog.btrim(p_reason), '');
  if p_parcel_id is null
    or v_reason is null
    or pg_catalog.char_length(v_reason) > 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The parcel cancellation is invalid.'
      )
    );
    response_status := 400;
  else
    select parcel.*
    into v_parcel
    from private.parcel_deliveries as parcel
    where parcel.id = p_parcel_id
      and parcel.customer_account_id = p_account_id
    for update;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'parcel_not_found', 'message', 'The parcel does not exist.'
        )
      );
      response_status := 404;
    elsif v_parcel.status not in (
      'payment_pending', 'paid', 'assigned', 'en_route_to_pickup'
    ) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'cancellation_not_allowed',
          'message', 'A parcel cannot be cancelled after pickup.'
        )
      );
      response_status := 409;
    else
      v_before := private.parcel_delivery_json(v_parcel, 'customer');

      for v_assignment in
        select assignment.*
        from private.parcel_assignment_attempts as assignment
        where assignment.parcel_id = v_parcel.id
          and assignment.status in ('offered', 'acknowledged')
        for update of assignment
      loop
        update private.parcel_assignment_attempts as assignment
        set status = 'cancelled',
            responded_at = coalesce(assignment.responded_at, pg_catalog.now()),
            response_reason = 'customer_cancelled',
            updated_at = pg_catalog.now()
        where assignment.id = v_assignment.id;
      end loop;

      update private.parcel_deliveries as parcel
      set status = 'cancelled',
          payment_status = case
            when parcel.payment_status = 'pending' then 'cancelled'
            else 'refund_pending'
          end,
          refund_status = case
            when parcel.payment_status = 'pending' then 'not_requested'
            else 'pending'
          end,
          cancelled_at = pg_catalog.now(),
          state_version = parcel.state_version + 1,
          updated_at = pg_catalog.now()
      where parcel.id = v_parcel.id
      returning * into v_parcel;

      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason,
        before_state, after_state
      ) values (
        p_account_id,
        case
          when v_parcel.payment_status = 'refund_pending'
            then 'parcel_cancelled_refund_pending'
          else 'parcel_cancelled_before_payment'
        end,
        'parcel_delivery',
        v_parcel.id,
        v_reason,
        v_before,
        private.parcel_delivery_json(v_parcel, 'customer')
      );

      perform private.process_parcel_dispatch(null, v_parcel.service_zone_id);
      response_body := private.parcel_delivery_json(v_parcel, 'customer');
      response_status := 200;
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create or replace function public.report_parcel_safety_incident(
  p_account_id uuid,
  p_parcel_id uuid,
  p_incident_type text,
  p_report_text text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'report_parcel_safety_incident';
  v_existing private.request_deduplication%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_case private.safety_cases%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if p_parcel_id is null
    or nullif(pg_catalog.btrim(p_incident_type), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_incident_type)) > 80
    or nullif(pg_catalog.btrim(p_report_text), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_report_text)) > 1000
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The safety report is invalid.'
      )
    );
    response_status := 400;
  else
    select parcel.*
    into v_parcel
    from private.parcel_deliveries as parcel
    where parcel.id = p_parcel_id
      and (
        parcel.customer_account_id = p_account_id
        or parcel.recipient_account_id = p_account_id
        or exists (
          select 1
          from private.parcel_assignment_attempts as assignment
          where assignment.parcel_id = parcel.id
            and assignment.partner_account_id = p_account_id
        )
      );

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'access_denied',
          'message', 'The parcel is not available to this account.'
        )
      );
      response_status := 403;
    elsif v_parcel.status in ('delivered', 'cancelled')
      and v_parcel.updated_at < pg_catalog.now() - interval '24 hours'
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'report_window_closed',
          'message', 'The in-app safety report window has closed.'
        )
      );
      response_status := 409;
    else
      insert into private.safety_cases (
        job_id, reporter_account_id, incident_type,
        report_text, route_evidence_reference
      ) values (
        v_parcel.id,
        p_account_id,
        pg_catalog.btrim(p_incident_type),
        pg_catalog.btrim(p_report_text),
        'parcel:' || v_parcel.id::text
      )
      returning * into v_case;

      response_body := pg_catalog.jsonb_build_object(
        'incidentId', v_case.id,
        'status', v_case.status,
        'emergencyNumber', '112'
      );
      response_status := 200;

      insert into audit.events (
        actor_id, action, entity_type, entity_id, after_state
      ) values (
        p_account_id,
        'parcel_safety_incident_reported',
        'safety_case',
        v_case.id,
        pg_catalog.jsonb_build_object(
          'parcelId', v_parcel.id,
          'incidentType', v_case.incident_type,
          'status', v_case.status
        )
      );
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

revoke execute on function public.upsert_parcel_rate_card(
  uuid, uuid, text, integer, integer, integer, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_parcel_rate_card(
  uuid, uuid, text, integer, integer, integer, boolean, text, text
) to service_role;

revoke execute on function public.quote_parcel_delivery(
  uuid, text, double precision, double precision, text,
  double precision, double precision, text, integer, integer, text, text
) from public, anon, authenticated;
grant execute on function public.quote_parcel_delivery(
  uuid, text, double precision, double precision, text,
  double precision, double precision, text, integer, integer, text, text
) to service_role;

revoke execute on function public.create_parcel_delivery(
  uuid, uuid, text, text, text, integer, text, text
) from public, anon, authenticated;
grant execute on function public.create_parcel_delivery(
  uuid, uuid, text, text, text, integer, text, text
) to service_role;

revoke execute on function public.record_parcel_payment_event(
  text, text, uuid, text, integer, timestamp with time zone, text
) from public, anon, authenticated;
grant execute on function public.record_parcel_payment_event(
  text, text, uuid, text, integer, timestamp with time zone, text
) to service_role;

revoke execute on function public.get_parcel_delivery_snapshot(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.get_parcel_delivery_snapshot(uuid, uuid)
  to service_role;

revoke execute on function public.get_parcel_partner_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function public.get_parcel_partner_snapshot(uuid)
  to service_role;

revoke execute on function public.acknowledge_parcel_assignment(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.acknowledge_parcel_assignment(
  uuid, uuid, text, text
) to service_role;

revoke execute on function public.decline_parcel_assignment(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.decline_parcel_assignment(
  uuid, uuid, text, text, text
) to service_role;

revoke execute on function public.advance_parcel_delivery(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.advance_parcel_delivery(
  uuid, uuid, text, text, text, text
) to service_role;

revoke execute on function public.cancel_parcel_delivery(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.cancel_parcel_delivery(
  uuid, uuid, text, text, text
) to service_role;

revoke execute on function public.report_parcel_safety_incident(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.report_parcel_safety_incident(
  uuid, uuid, text, text, text, text
) to service_role;

select cron.schedule(
  'dastak-parcel-dispatch',
  '10 seconds',
  'select private.process_parcel_dispatch();'
);

create or replace function private.process_courier_dispatch(
  p_order_id uuid default null,
  p_service_zone_id uuid default null
)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_attempt private.delivery_assignment_attempts%rowtype;
  v_attempt_id uuid;
  v_before_state jsonb;
  v_distance_meters double precision;
  v_inserted_count integer := 0;
  v_order private.merchant_orders%rowtype;
  v_order_status text;
  v_partner_id uuid;
  v_reason text;
  v_status text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak:all-delivery-dispatch', 0)
  );

  for v_attempt_id in
    select assignment.id
    from private.delivery_assignment_attempts as assignment
    join private.merchant_orders as merchant_order
      on merchant_order.id = assignment.order_id
    left join private.account_memberships as membership
      on membership.account_id = assignment.partner_account_id
     and membership.role = 'dastak_partner'
    left join private.delivery_partner_availability as availability
      on availability.account_id = assignment.partner_account_id
    where assignment.status = 'offered'
      and (p_order_id is null or assignment.order_id = p_order_id)
      and (
        assignment.respond_by <= pg_catalog.now()
        or merchant_order.status <> 'ready'
        or membership.account_id is null
        or membership.approved_at is null
        or membership.suspended_until > pg_catalog.now()
        or availability.account_id is null
        or availability.status <> 'online'
        or availability.available_until <= pg_catalog.now()
        or availability.last_seen_at <= pg_catalog.now() - interval '90 seconds'
        or availability.service_zone_id <> merchant_order.service_zone_id
      )
    order by assignment.respond_by, assignment.id
    for update of assignment skip locked
  loop
    select assignment.*
    into v_attempt
    from private.delivery_assignment_attempts as assignment
    where assignment.id = v_attempt_id;

    select merchant_order.status
    into v_order_status
    from private.merchant_orders as merchant_order
    where merchant_order.id = v_attempt.order_id;

    v_before_state := private.delivery_assignment_json(v_attempt);
    if v_order_status <> 'ready' then
      v_status := 'cancelled';
      v_reason := 'order_no_longer_ready';
    elsif v_attempt.respond_by <= pg_catalog.now() then
      v_status := 'expired';
      v_reason := 'offer_expired';
    else
      v_status := 'expired';
      v_reason := 'partner_unavailable';
    end if;

    update private.delivery_assignment_attempts as assignment
    set status = v_status,
        responded_at = pg_catalog.now(),
        response_reason = v_reason,
        updated_at = pg_catalog.now()
    where assignment.id = v_attempt.id
      and assignment.status = 'offered'
    returning assignment.* into v_attempt;

    if found then
      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason,
        before_state, after_state
      ) values (
        null,
        case
          when v_status = 'expired' then 'delivery_assignment_expired'
          else 'delivery_assignment_cancelled'
        end,
        'delivery_assignment',
        v_attempt.id,
        v_reason,
        v_before_state,
        private.delivery_assignment_json(v_attempt)
      );
    end if;
  end loop;

  for v_order in
    select merchant_order.*
    from private.merchant_orders as merchant_order
    where merchant_order.status = 'ready'
      and (p_order_id is null or merchant_order.id = p_order_id)
      and (
        p_service_zone_id is null
        or merchant_order.service_zone_id = p_service_zone_id
      )
      and not exists (
        select 1
        from private.delivery_assignment_attempts as active_assignment
        where active_assignment.order_id = merchant_order.id
          and active_assignment.status in ('offered', 'accepted')
      )
    order by merchant_order.ready_at nulls last, merchant_order.created_at,
      merchant_order.id
    for update of merchant_order skip locked
  loop
    v_partner_id := null;
    v_distance_meters := null;

    select
      availability.account_id,
      extensions.st_distance(
        availability.location::extensions.geography,
        store.location::extensions.geography
      )
    into v_partner_id, v_distance_meters
    from private.delivery_partner_availability as availability
    join private.delivery_partner_profiles as profile
      on profile.account_id = availability.account_id
    join private.account_memberships as membership
      on membership.account_id = availability.account_id
     and membership.role = 'dastak_partner'
    join private.merchant_stores as store
      on store.id = v_order.store_id
    where availability.status = 'online'
      and availability.available_until > pg_catalog.now()
      and availability.last_seen_at > pg_catalog.now() - interval '90 seconds'
      and availability.service_zone_id = v_order.service_zone_id
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
      and not exists (
        select 1
        from private.delivery_assignment_attempts as active_partner_assignment
        where active_partner_assignment.partner_account_id = availability.account_id
          and active_partner_assignment.status in ('offered', 'accepted')
      )
      and not exists (
        select 1
        from private.parcel_assignment_attempts as active_parcel_assignment
        where active_parcel_assignment.partner_account_id = availability.account_id
          and active_parcel_assignment.status in ('offered', 'acknowledged')
      )
      and not exists (
        select 1
        from private.delivery_assignment_attempts as prior_attempt
        where prior_attempt.order_id = v_order.id
          and prior_attempt.partner_account_id = availability.account_id
      )
    order by
      availability.location operator(extensions.<->) store.location,
      availability.account_id
    limit 1
    for update of availability skip locked;

    if v_partner_id is null then
      continue;
    end if;

    insert into private.delivery_assignment_attempts (
      order_id, partner_account_id, attempt_number, status,
      distance_meters, offered_at, respond_by
    ) values (
      v_order.id,
      v_partner_id,
      (
        select coalesce(pg_catalog.max(attempt.attempt_number), 0) + 1
        from private.delivery_assignment_attempts as attempt
        where attempt.order_id = v_order.id
      ),
      'offered',
      v_distance_meters,
      pg_catalog.now(),
      pg_catalog.now() + interval '60 seconds'
    )
    returning * into v_attempt;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, after_state
    ) values (
      null,
      'delivery_assignment_offered',
      'delivery_assignment',
      v_attempt.id,
      private.delivery_assignment_json(v_attempt)
    );

    v_inserted_count := v_inserted_count + 1;
  end loop;

  return v_inserted_count;
end;
$$;

revoke execute on function private.process_courier_dispatch(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.process_courier_dispatch(uuid, uuid)
  to service_role;
