create extension if not exists pg_cron;

create table private.delivery_assignment_attempts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  order_id uuid not null references private.merchant_orders(id) on delete cascade,
  partner_account_id uuid not null
    references private.delivery_partner_profiles(account_id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  status text not null default 'offered' check (
    status in ('offered', 'accepted', 'declined', 'expired', 'cancelled', 'completed')
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
  unique (order_id, partner_account_id),
  unique (order_id, attempt_number),
  check (respond_by > offered_at),
  check (
    (
      status = 'offered'
      and responded_at is null
      and response_reason is null
    )
    or (
      status = 'accepted'
      and responded_at is not null
      and response_reason is null
    )
    or (
      status = 'declined'
      and responded_at is not null
    )
    or (
      status in ('expired', 'cancelled', 'completed')
      and responded_at is not null
      and response_reason is not null
    )
  )
);

create unique index delivery_assignment_order_offer_uidx
  on private.delivery_assignment_attempts(order_id)
  where status = 'offered';
create unique index delivery_assignment_order_accepted_uidx
  on private.delivery_assignment_attempts(order_id)
  where status = 'accepted';
create unique index delivery_assignment_partner_active_uidx
  on private.delivery_assignment_attempts(partner_account_id)
  where status in ('offered', 'accepted');
create index delivery_assignment_order_history_idx
  on private.delivery_assignment_attempts(order_id, attempt_number desc);
create index delivery_assignment_offer_expiry_idx
  on private.delivery_assignment_attempts(respond_by)
  where status = 'offered';

alter table private.delivery_assignment_attempts enable row level security;

revoke all on table private.delivery_assignment_attempts
  from public, anon, authenticated;
grant select, insert, update on table private.delivery_assignment_attempts
  to service_role;

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

create or replace function private.delivery_partner_dispatch_snapshot_json(
  p_account_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'offer', private.delivery_assignment_json(
      (
        select assignment
        from private.delivery_assignment_attempts as assignment
        join private.account_memberships as membership
          on membership.account_id = assignment.partner_account_id
         and membership.role = 'dastak_partner'
         and membership.approved_at is not null
         and (
           membership.suspended_until is null
           or membership.suspended_until <= pg_catalog.now()
         )
        where assignment.partner_account_id = p_account_id
          and assignment.status = 'offered'
          and assignment.respond_by > pg_catalog.now()
        order by assignment.offered_at, assignment.id
        limit 1
      )
    ),
    'currentJob', private.delivery_assignment_json(
      (
        select assignment
        from private.delivery_assignment_attempts as assignment
        where assignment.partner_account_id = p_account_id
          and assignment.status = 'accepted'
        order by assignment.responded_at, assignment.id
        limit 1
      )
    )
  );
$$;

revoke execute on function private.delivery_assignment_json(
  private.delivery_assignment_attempts
) from public, anon, authenticated;
revoke execute on function private.delivery_partner_dispatch_snapshot_json(uuid)
  from public, anon, authenticated;
grant execute on function private.delivery_assignment_json(
  private.delivery_assignment_attempts
) to service_role;
grant execute on function private.delivery_partner_dispatch_snapshot_json(uuid)
  to service_role;

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

create or replace function private.sync_courier_dispatch_on_order_change()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_attempt private.delivery_assignment_attempts%rowtype;
  v_before_state jsonb;
begin
  if new.status = 'ready' then
    perform private.process_courier_dispatch(new.id, new.service_zone_id);
  elsif new.status in ('cancelled', 'delivered') then
    for v_attempt in
      select assignment.*
      from private.delivery_assignment_attempts as assignment
      where assignment.order_id = new.id
        and assignment.status in ('offered', 'accepted')
      order by assignment.attempt_number
      for update of assignment
    loop
      v_before_state := private.delivery_assignment_json(v_attempt);
      update private.delivery_assignment_attempts as assignment
      set status = case when new.status = 'delivered' then 'completed' else 'cancelled' end,
          responded_at = coalesce(assignment.responded_at, pg_catalog.now()),
          response_reason = case
            when new.status = 'delivered' then 'order_delivered'
            else 'order_cancelled'
          end,
          updated_at = pg_catalog.now()
      where assignment.id = v_attempt.id
      returning assignment.* into v_attempt;

      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason,
        before_state, after_state
      ) values (
        null,
        case
          when new.status = 'delivered' then 'delivery_assignment_completed'
          else 'delivery_assignment_cancelled'
        end,
        'delivery_assignment',
        v_attempt.id,
        v_attempt.response_reason,
        v_before_state,
        private.delivery_assignment_json(v_attempt)
      );
    end loop;
  end if;

  return new;
end;
$$;

create or replace function private.sync_courier_dispatch_on_availability_change()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  perform private.process_courier_dispatch(
    null,
    case when new.status = 'online' then new.service_zone_id else null end
  );
  return new;
end;
$$;

revoke execute on function private.sync_courier_dispatch_on_order_change()
  from public, anon, authenticated;
revoke execute on function private.sync_courier_dispatch_on_availability_change()
  from public, anon, authenticated;
grant execute on function private.sync_courier_dispatch_on_order_change()
  to service_role;
grant execute on function private.sync_courier_dispatch_on_availability_change()
  to service_role;

create trigger merchant_order_courier_dispatch
after insert or update of status on private.merchant_orders
for each row execute function private.sync_courier_dispatch_on_order_change();

create trigger delivery_partner_availability_dispatch
after insert or update of status, location, service_zone_id, available_until
on private.delivery_partner_availability
for each row execute function private.sync_courier_dispatch_on_availability_change();

create or replace function public.get_delivery_partner_dispatch_snapshot(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
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
    and membership.approved_at is not null;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An approved delivery partner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  perform private.process_courier_dispatch();
  response_body := private.delivery_partner_dispatch_snapshot_json(p_account_id);
  response_status := 200;
  return next;
end;
$$;

create or replace function public.accept_delivery_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
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
  v_attempt private.delivery_assignment_attempts%rowtype;
  v_before_state jsonb;
  v_existing_dedup private.request_deduplication%rowtype;
  v_function_name constant text := 'accept_delivery_assignment';
  v_order private.merchant_orders%rowtype;
begin
  if p_account_id is null
    or p_assignment_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The delivery assignment acceptance request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_assignment_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing_dedup.request_digest = pg_catalog.btrim(p_request_digest) then
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

  select assignment.*
  into v_attempt
  from private.delivery_assignment_attempts as assignment
  where assignment.id = p_assignment_id
    and assignment.partner_account_id = p_account_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'assignment_not_found',
        'message', 'The delivery assignment was not found.'
      )
    );
    response_status := 404;
  elsif v_attempt.status = 'accepted' then
    response_body := private.delivery_partner_dispatch_snapshot_json(p_account_id);
    response_status := 200;
  elsif v_attempt.status <> 'offered' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_assignment_transition',
        'message', 'This delivery assignment can no longer be accepted.'
      )
    );
    response_status := 409;
  elsif v_attempt.respond_by <= pg_catalog.now() then
    v_before_state := private.delivery_assignment_json(v_attempt);
    update private.delivery_assignment_attempts as assignment
    set status = 'expired',
        responded_at = pg_catalog.now(),
        response_reason = 'offer_expired',
        updated_at = pg_catalog.now()
    where assignment.id = v_attempt.id
    returning assignment.* into v_attempt;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, reason,
      before_state, after_state
    ) values (
      null, 'delivery_assignment_expired', 'delivery_assignment',
      v_attempt.id, 'offer_expired', v_before_state,
      private.delivery_assignment_json(v_attempt)
    );
    perform private.process_courier_dispatch(v_attempt.order_id, null);
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'assignment_expired',
        'message', 'The delivery assignment response window has expired.'
      )
    );
    response_status := 409;
  elsif not exists (
    select 1
    from private.account_memberships as membership
    join private.delivery_partner_availability as availability
      on availability.account_id = membership.account_id
    where membership.account_id = p_account_id
      and membership.role = 'dastak_partner'
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
      and availability.status = 'online'
      and availability.available_until > pg_catalog.now()
  ) then
    v_before_state := private.delivery_assignment_json(v_attempt);
    update private.delivery_assignment_attempts as assignment
    set status = 'expired',
        responded_at = pg_catalog.now(),
        response_reason = 'partner_unavailable',
        updated_at = pg_catalog.now()
    where assignment.id = v_attempt.id
    returning assignment.* into v_attempt;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, reason,
      before_state, after_state
    ) values (
      null, 'delivery_assignment_expired', 'delivery_assignment',
      v_attempt.id, 'partner_unavailable', v_before_state,
      private.delivery_assignment_json(v_attempt)
    );
    perform private.process_courier_dispatch(v_attempt.order_id, null);
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'partner_unavailable',
        'message', 'The delivery partner is no longer available for this offer.'
      )
    );
    response_status := 409;
  else
    select merchant_order.*
    into v_order
    from private.merchant_orders as merchant_order
    where merchant_order.id = v_attempt.order_id
    for update;

    if v_order.status <> 'ready' then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_order_transition',
          'message', 'The merchant order is no longer ready for assignment.'
        )
      );
      response_status := 409;
    else
      v_before_state := private.delivery_assignment_json(v_attempt);
      update private.delivery_assignment_attempts as assignment
      set status = 'accepted',
          responded_at = pg_catalog.now(),
          updated_at = pg_catalog.now()
      where assignment.id = v_attempt.id
      returning assignment.* into v_attempt;

      update private.merchant_orders as merchant_order
      set status = 'assigned',
          state_version = merchant_order.state_version + 1,
          updated_at = pg_catalog.now()
      where merchant_order.id = v_order.id;

      response_body := private.delivery_partner_dispatch_snapshot_json(p_account_id);
      response_status := 200;

      insert into audit.events (
        actor_id, action, entity_type, entity_id,
        before_state, after_state
      ) values (
        p_account_id,
        'delivery_assignment_accepted',
        'delivery_assignment',
        v_attempt.id,
        v_before_state,
        private.delivery_assignment_json(v_attempt)
      );
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id,
    v_function_name,
    pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest),
    response_body,
    response_status
  );

  return next;
end;
$$;

create or replace function public.decline_delivery_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
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
  v_attempt private.delivery_assignment_attempts%rowtype;
  v_before_state jsonb;
  v_existing_dedup private.request_deduplication%rowtype;
  v_function_name constant text := 'decline_delivery_assignment';
  v_reason text;
begin
  v_reason := coalesce(
    nullif(pg_catalog.btrim(p_reason), ''),
    'Partner declined the offer.'
  );

  if p_account_id is null
    or p_assignment_id is null
    or pg_catalog.char_length(v_reason) > 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The delivery assignment decline request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_assignment_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing_dedup.request_digest = pg_catalog.btrim(p_request_digest) then
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

  select assignment.*
  into v_attempt
  from private.delivery_assignment_attempts as assignment
  where assignment.id = p_assignment_id
    and assignment.partner_account_id = p_account_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'assignment_not_found',
        'message', 'The delivery assignment was not found.'
      )
    );
    response_status := 404;
  elsif v_attempt.status = 'declined' then
    response_body := private.delivery_partner_dispatch_snapshot_json(p_account_id);
    response_status := 200;
  elsif v_attempt.status <> 'offered' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_assignment_transition',
        'message', 'This delivery assignment can no longer be declined.'
      )
    );
    response_status := 409;
  elsif v_attempt.respond_by <= pg_catalog.now() then
    v_before_state := private.delivery_assignment_json(v_attempt);
    update private.delivery_assignment_attempts as assignment
    set status = 'expired',
        responded_at = pg_catalog.now(),
        response_reason = 'offer_expired',
        updated_at = pg_catalog.now()
    where assignment.id = v_attempt.id
    returning assignment.* into v_attempt;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, reason,
      before_state, after_state
    ) values (
      null, 'delivery_assignment_expired', 'delivery_assignment',
      v_attempt.id, 'offer_expired', v_before_state,
      private.delivery_assignment_json(v_attempt)
    );
    perform private.process_courier_dispatch(v_attempt.order_id, null);
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'assignment_expired',
        'message', 'The delivery assignment response window has expired.'
      )
    );
    response_status := 409;
  else
    v_before_state := private.delivery_assignment_json(v_attempt);
    update private.delivery_assignment_attempts as assignment
    set status = 'declined',
        responded_at = pg_catalog.now(),
        response_reason = v_reason,
        updated_at = pg_catalog.now()
    where assignment.id = v_attempt.id
    returning assignment.* into v_attempt;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, reason,
      before_state, after_state
    ) values (
      p_account_id,
      'delivery_assignment_declined',
      'delivery_assignment',
      v_attempt.id,
      v_reason,
      v_before_state,
      private.delivery_assignment_json(v_attempt)
    );

    perform private.process_courier_dispatch(v_attempt.order_id, null);
    response_body := private.delivery_partner_dispatch_snapshot_json(p_account_id);
    response_status := 200;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id,
    v_function_name,
    pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest),
    response_body,
    response_status
  );

  return next;
end;
$$;

revoke execute on function public.get_delivery_partner_dispatch_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function public.get_delivery_partner_dispatch_snapshot(uuid)
  to service_role;

revoke execute on function public.accept_delivery_assignment(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.accept_delivery_assignment(
  uuid, uuid, text, text
) to service_role;

revoke execute on function public.decline_delivery_assignment(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.decline_delivery_assignment(
  uuid, uuid, text, text, text
) to service_role;

select cron.schedule(
  'dastak-courier-dispatch',
  '10 seconds',
  'select private.process_courier_dispatch();'
);
