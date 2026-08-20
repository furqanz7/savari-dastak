-- A direct parcel deep link must carry the same public audience marker as the
-- customer list so sender/recipient redaction and actions remain deterministic.
create or replace function public.get_parcel_delivery_snapshot(
  p_account_id uuid,
  p_parcel_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_parcel private.parcel_deliveries%rowtype;
  v_audience text;
begin
  select parcel.* into v_parcel
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
        'code', 'access_denied',
        'message', 'This parcel is not available to the account.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  response_body := case
    when v_audience in ('customer', 'recipient') then
      private.customer_parcel_delivery_json(v_parcel, v_audience, p_account_id)
      || pg_catalog.jsonb_build_object(
        'audience', case when v_audience = 'customer' then 'sender' else 'recipient' end
      )
    else private.parcel_delivery_json(v_parcel, v_audience)
  end;
  response_status := 200;
  return next;
end;
$$;

alter table private.customer_order_support_cases
  add column if not exists resolution text check (
    resolution is null
    or pg_catalog.char_length(pg_catalog.btrim(resolution)) between 5 and 500
  ),
  add column if not exists resolved_by_account_id uuid references public.accounts(id) on delete set null,
  add column if not exists resolved_at timestamptz;

update private.customer_order_support_cases as support_case
set resolution = 'Resolved before owner operations were enabled.',
    resolved_at = support_case.updated_at
where support_case.status in ('resolved', 'closed');

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'private.customer_order_support_cases'::pg_catalog.regclass
      and conname = 'customer_order_support_cases_resolution_check'
  ) then
    alter table private.customer_order_support_cases
      add constraint customer_order_support_cases_resolution_check check (
        (status in ('open', 'in_review') and resolution is null and resolved_at is null)
        or (status in ('resolved', 'closed') and resolution is not null and resolved_at is not null)
      );
  end if;
end
$$;

create or replace function private.customer_order_support_case_json(
  support_case private.customer_order_support_cases
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'caseId', (support_case).id,
    'reference', 'DST-' || pg_catalog.upper(
      pg_catalog.substr(pg_catalog.replace((support_case).id::text, '-', ''), 1, 8)
    ),
    'entityKind', (support_case).entity_kind,
    'entityId', (support_case).entity_id,
    'category', (support_case).category,
    'message', (support_case).message,
    'status', (support_case).status,
    'resolution', (support_case).resolution,
    'createdAt', (support_case).created_at,
    'updatedAt', (support_case).updated_at,
    'resolvedAt', (support_case).resolved_at
  ));
$$;

create or replace function public.get_owner_order_operations(
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
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The exception limit must be between 1 and 100.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied', 'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  with exception_rows as (
    select
      'support:' || support_case.id::text as exception_id,
      'support'::text as kind,
      case when support_case.category = 'safety' then 'critical' else 'attention' end as severity,
      support_case.entity_kind,
      support_case.entity_id,
      'Customer support request'::text as title,
      support_case.message as detail,
      support_case.status,
      null::text as purpose,
      support_case.created_at as occurred_at
    from private.customer_order_support_cases as support_case
    where support_case.status in ('open', 'in_review')

    union all

    select
      'refund:' || decision.id::text,
      'refund_review', 'attention', 'merchant_order', decision.order_id,
      'Refund decision required', decision.reason, decision.decision_status,
      null::text, decision.created_at
    from private.merchant_order_refund_decisions as decision
    where decision.decision_status = 'review_required'
      and not exists (
        select 1
        from private.merchant_order_refund_decisions as later
        where later.order_id = decision.order_id
          and (later.created_at, later.id) > (decision.created_at, decision.id)
      )

    union all

    select
      'merchant-code:' || merchant_order.id::text || ':' || code.purpose,
      'handoff_locked', 'critical', 'merchant_order', merchant_order.id,
      case code.purpose when 'pickup' then 'Pickup code locked' else 'Delivery code locked' end,
      'Five unsuccessful code attempts require owner recovery.', 'locked', code.purpose,
      coalesce(code.locked_at, merchant_order.updated_at)
    from private.merchant_orders as merchant_order
    cross join lateral (
      values
        ('pickup'::text, merchant_order.pickup_code_locked_at),
        ('delivery'::text, merchant_order.delivery_code_locked_at)
    ) as code(purpose, locked_at)
    where code.locked_at is not null
      and merchant_order.status not in ('delivered', 'cancelled')

    union all

    select
      'parcel-code:' || parcel.id::text || ':' || code.purpose,
      'handoff_locked', 'critical', 'parcel_delivery', parcel.id,
      case code.purpose when 'pickup' then 'Parcel pickup code locked' else 'Parcel delivery code locked' end,
      'Five unsuccessful code attempts require owner recovery.', 'locked', code.purpose,
      coalesce(code.locked_at, parcel.updated_at)
    from private.parcel_deliveries as parcel
    cross join lateral (
      values
        ('pickup'::text, parcel.pickup_code_locked_at),
        ('delivery'::text, parcel.delivery_code_locked_at)
    ) as code(purpose, locked_at)
    where code.locked_at is not null
      and parcel.status not in ('delivered', 'cancelled')

    union all

    select
      'stalled-merchant:' || merchant_order.id::text,
      'stalled_order', 'attention', 'merchant_order', merchant_order.id,
      'Merchant order needs attention',
      'No lifecycle progress has been recorded within the expected window.',
      merchant_order.status, null::text, merchant_order.updated_at
    from private.merchant_orders as merchant_order
    where (
      merchant_order.status in ('merchant_accepted', 'ready', 'at_store')
      and merchant_order.updated_at < pg_catalog.now() - interval '30 minutes'
    ) or (
      merchant_order.status in ('assigned')
      and merchant_order.updated_at < pg_catalog.now() - interval '15 minutes'
    ) or (
      merchant_order.status in ('en_route_to_pickup')
      and merchant_order.updated_at < pg_catalog.now() - interval '60 minutes'
    ) or (
      merchant_order.status in ('picked_up', 'in_transit', 'returning_to_merchant')
      and merchant_order.updated_at < pg_catalog.now() - interval '2 hours'
    )

    union all

    select
      'stalled-parcel:' || parcel.id::text,
      'stalled_order', 'attention', 'parcel_delivery', parcel.id,
      'Parcel delivery needs attention',
      'No lifecycle progress has been recorded within the expected window.',
      parcel.status, null::text, parcel.updated_at
    from private.parcel_deliveries as parcel
    where (
      parcel.status in ('paid', 'assigned')
      and parcel.updated_at < pg_catalog.now() - interval '15 minutes'
    ) or (
      parcel.status = 'en_route_to_pickup'
      and parcel.updated_at < pg_catalog.now() - interval '60 minutes'
    ) or (
      parcel.status in ('picked_up', 'in_transit')
      and parcel.updated_at < pg_catalog.now() - interval '2 hours'
    )
  ),
  recent_exceptions as (
    select * from exception_rows order by occurred_at desc, exception_id limit p_limit
  ),
  recent_parcels as (
    select parcel.*
    from private.parcel_deliveries as parcel
    order by parcel.created_at desc, parcel.id desc
    limit p_limit
  )
  select pg_catalog.jsonb_build_object(
    'summary', pg_catalog.jsonb_build_object(
      'openSupport', (select pg_catalog.count(*) from exception_rows where kind = 'support'),
      'refundReviews', (select pg_catalog.count(*) from exception_rows where kind = 'refund_review'),
      'lockedHandoffs', (select pg_catalog.count(*) from exception_rows where kind = 'handoff_locked'),
      'stalledOrders', (select pg_catalog.count(*) from exception_rows where kind = 'stalled_order'),
      'totalExceptions', (select pg_catalog.count(*) from exception_rows)
    ),
    'exceptions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'exceptionId', exception.exception_id,
        'kind', exception.kind,
        'severity', exception.severity,
        'entityKind', exception.entity_kind,
        'entityId', exception.entity_id,
        'title', exception.title,
        'detail', exception.detail,
        'status', exception.status,
        'purpose', exception.purpose,
        'occurredAt', exception.occurred_at
      )) order by exception.occurred_at desc, exception.exception_id)
      from recent_exceptions as exception
    ), '[]'::jsonb),
    'parcels', coalesce((
      select pg_catalog.jsonb_agg(
        private.parcel_delivery_json(parcel, 'owner')
        order by parcel.created_at desc, parcel.id desc
      ) from recent_parcels as parcel
    ), '[]'::jsonb)
  ) into response_body;

  response_status := 200;
  return next;
end;
$$;

create or replace function public.owner_resolve_customer_support_case(
  p_account_id uuid,
  p_case_id uuid,
  p_resolution text,
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
  v_existing private.request_deduplication%rowtype;
  v_case private.customer_order_support_cases%rowtype;
  v_resolution text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_resolution, '')), '\s+', ' ', 'g');
  v_function_name constant text := 'owner_resolve_customer_support_case';
begin
  if p_case_id is null
    or pg_catalog.char_length(v_resolution) not between 5 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 8 and 200
    or coalesce(p_request_digest, '') !~ '^[0-9a-f]{64}$'
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'validation_failed', 'message', 'The support resolution is invalid.'
    ));
    response_status := 400;
    return next;
    return;
  end if;

  perform 1 from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An active Dastak owner account is required.'
    ));
    response_status := 403;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict', 'message', 'The idempotency key was already used.'
      ));
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select support_case.* into v_case
  from private.customer_order_support_cases as support_case
  where support_case.id = p_case_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'support_case_not_found', 'message', 'The support case was not found.'
    ));
    response_status := 404;
  elsif v_case.status not in ('open', 'in_review') then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'support_case_closed', 'message', 'This support case is already closed.'
    ));
    response_status := 409;
  else
    update private.customer_order_support_cases as support_case
    set status = 'resolved', resolution = v_resolution,
        resolved_by_account_id = p_account_id, resolved_at = pg_catalog.now(),
        updated_at = pg_catalog.now()
    where support_case.id = v_case.id
    returning support_case.* into v_case;
    response_body := private.customer_order_support_case_json(v_case);
    response_status := 200;
    insert into audit.events (actor_id, action, entity_type, entity_id, reason, after_state)
    values (p_account_id, 'customer_order_support_resolved', 'customer_order_support_case',
      v_case.id, v_resolution, response_body);
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest, response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    p_request_digest, response_body, response_status
  );
  return next;
end;
$$;

create or replace function public.owner_reset_parcel_handoff_code(
  p_account_id uuid,
  p_parcel_id uuid,
  p_purpose text,
  p_reason text,
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
  v_existing private.request_deduplication%rowtype;
  v_parcel private.parcel_deliveries%rowtype;
  v_salt text;
  v_code text;
  v_reason text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_reason, '')), '\s+', ' ', 'g');
  v_function_name constant text := 'owner_reset_parcel_handoff_code';
begin
  if p_parcel_id is null or p_purpose not in ('pickup', 'delivery')
    or pg_catalog.char_length(v_reason) not between 5 and 300
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 8 and 200
    or coalesce(p_request_digest, '') !~ '^[0-9a-f]{64}$'
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'validation_failed', 'message', 'The parcel handoff recovery request is invalid.'
    ));
    response_status := 400;
    return next;
    return;
  end if;

  perform 1 from private.account_memberships as membership
  where membership.account_id = p_account_id and membership.role = 'owner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An active Dastak owner account is required.'
    ));
    response_status := 403;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing from private.request_deduplication as dedup
  where dedup.account_id = p_account_id and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body; response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict', 'message', 'The idempotency key was already used.'
      )); response_status := 409;
    end if;
    return next; return;
  end if;

  select parcel.* into v_parcel from private.parcel_deliveries as parcel
  where parcel.id = p_parcel_id for update;
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'parcel_not_found', 'message', 'The parcel was not found.'
    )); response_status := 404;
  elsif (p_purpose = 'pickup' and (v_parcel.status not in ('assigned', 'en_route_to_pickup')
      or v_parcel.pickup_code_locked_at is null))
    or (p_purpose = 'delivery' and (v_parcel.status not in ('picked_up', 'in_transit')
      or v_parcel.delivery_code_locked_at is null))
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'handoff_code_not_recoverable', 'message', 'This parcel code is not locked.'
    )); response_status := 409;
  else
    v_salt := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
    v_code := private.parcel_handoff_code(v_parcel.id, p_purpose);
    if p_purpose = 'pickup' then
      update private.parcel_deliveries as parcel
      set pickup_code_salt = v_salt,
          pickup_code_digest = private.parcel_handoff_digest(v_salt, v_code),
          pickup_code_expires_at = pg_catalog.now() + interval '6 hours',
          pickup_code_failed_attempts = 0, pickup_code_locked_at = null,
          state_version = parcel.state_version + 1, updated_at = pg_catalog.now()
      where parcel.id = v_parcel.id returning parcel.* into v_parcel;
    else
      update private.parcel_deliveries as parcel
      set delivery_code_salt = v_salt,
          delivery_code_digest = private.parcel_handoff_digest(v_salt, v_code),
          delivery_code_expires_at = pg_catalog.now() + interval '6 hours',
          delivery_code_failed_attempts = 0, delivery_code_locked_at = null,
          state_version = parcel.state_version + 1, updated_at = pg_catalog.now()
      where parcel.id = v_parcel.id returning parcel.* into v_parcel;
    end if;
    response_body := private.parcel_delivery_json(v_parcel, 'owner'); response_status := 200;
    insert into audit.events (actor_id, action, entity_type, entity_id, reason, after_state)
    values (p_account_id, 'parcel_handoff_code_reset', 'parcel_delivery', v_parcel.id,
      v_reason, pg_catalog.jsonb_build_object('purpose', p_purpose, 'locked', false));
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest, response_body, response_status
  ) values (p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    p_request_digest, response_body, response_status);
  return next;
end;
$$;

create or replace function public.owner_reconcile_order_lifecycle(p_account_id uuid)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  perform 1 from private.account_memberships as membership
  where membership.account_id = p_account_id and membership.role = 'owner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An active Dastak owner account is required.'
    )); response_status := 403; return next; return;
  end if;
  response_body := private.reconcile_order_lifecycle();
  response_status := 200;
  insert into audit.events (actor_id, action, entity_type, entity_id, after_state)
  values (p_account_id, 'order_lifecycle_reconciled', 'marketplace', p_account_id, response_body);
  return next;
end;
$$;

-- Location publication is intentionally separate from availability. It keeps
-- live tracking current without extending the 15-minute online window.
create or replace function public.publish_delivery_partner_location(
  p_account_id uuid,
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
  v_function_name constant text := 'publish_delivery_partner_location';
  v_existing private.request_deduplication%rowtype;
  v_availability private.delivery_partner_availability%rowtype;
  v_point extensions.geometry(Point, 4326);
  v_zone_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body; response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict', 'message', 'The idempotency key was already used with a different request.'
      )); response_status := 409;
    end if;
    return next; return;
  end if;

  if p_latitude is null or p_latitude < -90 or p_latitude > 90
    or p_longitude is null or p_longitude < -180 or p_longitude > 180
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'validation_failed', 'message', 'The location update is invalid.'
    )); response_status := 400; return next; return;
  end if;

  perform 1 from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'dastak_partner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An approved active delivery partner account is required.'
    )); response_status := 403; return next; return;
  end if;

  select availability.* into v_availability
  from private.delivery_partner_availability as availability
  where availability.account_id = p_account_id
  for update;
  if not found or v_availability.status <> 'online'
    or v_availability.available_until <= pg_catalog.now()
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'partner_offline', 'message', 'Go online again before sharing location.'
    )); response_status := 409; return next; return;
  end if;

  v_point := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326);
  select zone.id into v_zone_id
  from public.service_zones as zone
  where zone.active = true and extensions.st_covers(zone.boundary, v_point)
  order by zone.id limit 1;
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'outside_service_area', 'message', 'Dastak is not available at this location.'
    )); response_status := 422; return next; return;
  end if;

  update private.delivery_partner_availability as availability
  set location = v_point,
      service_zone_id = v_zone_id,
      last_seen_at = pg_catalog.now(),
      state_version = availability.state_version + 1,
      updated_at = pg_catalog.now()
  where availability.account_id = p_account_id
  returning availability.* into v_availability;

  response_body := private.delivery_partner_availability_json(v_availability, true);
  response_status := 200;
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest, response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    p_request_digest, response_body, response_status
  );
  return next;
end;
$$;

revoke execute on function public.get_parcel_delivery_snapshot(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function private.customer_order_support_case_json(
  private.customer_order_support_cases
) from public, anon, authenticated;
revoke execute on function public.get_owner_order_operations(uuid, integer)
  from public, anon, authenticated;
revoke execute on function public.owner_resolve_customer_support_case(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
revoke execute on function public.owner_reset_parcel_handoff_code(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.owner_reconcile_order_lifecycle(uuid)
  from public, anon, authenticated;
revoke execute on function public.publish_delivery_partner_location(
  uuid, double precision, double precision, text, text
) from public, anon, authenticated;

grant execute on function public.get_parcel_delivery_snapshot(uuid, uuid) to service_role;
grant execute on function private.customer_order_support_case_json(
  private.customer_order_support_cases
) to service_role;
grant execute on function public.get_owner_order_operations(uuid, integer) to service_role;
grant execute on function public.owner_resolve_customer_support_case(
  uuid, uuid, text, text, text
) to service_role;
grant execute on function public.owner_reset_parcel_handoff_code(
  uuid, uuid, text, text, text, text
) to service_role;
grant execute on function public.owner_reconcile_order_lifecycle(uuid) to service_role;
grant execute on function public.publish_delivery_partner_location(
  uuid, double precision, double precision, text, text
) to service_role;
